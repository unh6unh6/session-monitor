# session-monitor MVP 계획

여러 Claude Code 세션의 상태를 한곳에서 보는 macOS 앱.
세션의 hook 이벤트를 모아 "지금 어떤 세션이 일하는 중이고, 어떤 세션이 나를 기다리는지"를 그룹 단위로 보여준다.

이 문서는 MVP 방향을 정하는 기준 문서다. MVP 이후의 기능은 GitHub 이슈로 기획하고 우선순위를 조정한다.

---

## 1. 목표와 범위

### MVP에서 하는 것
- 등록된 세션의 상태를 실시간으로 표시한다 (생성중 / 응답 완료 / 응답 필요 / 종료).
- 세션별 마지막 요청, 마지막 응답, recap을 보여준다.
- 세션을 그룹(예: `이슈A`)으로 묶어서 본다.
- 등록과 그룹 변경은 스킬과 GUI 양쪽에서 할 수 있다.
- 응답 필요와 응답 완료 상태가 되면 macOS 알림을 띄운다.
- 세션 카드에서 그 세션이 실행 중인 터미널 창으로 바로 이동한다. 다른 Space에 있는 창이어도 이동한다.
- brew 한 줄로 앱을 설치하고, Claude Code 플러그인으로 hook과 스킬을 설치한다.

### MVP에서 하지 않는 것 (이슈로 관리)
- Warp에서 특정 탭이나 pane 단위까지 이동하는 기능 (조사 결과에 따라 MVP로 당길 수 있음, 3.5 참고).
- LLM 자동 recap (Stop마다 haiku로 요약).
- 앱에서 세션으로 입력이나 응답을 보내는 기능.
- 공증(notarization)과 공식 homebrew/cask 등록.

---

## 2. 결정 사항

| # | 항목 | 결정 |
|---|---|---|
| 1 | 표시 범위 | 등록된 세션은 정식으로 표시하고, 미등록 세션은 접힌 영역에 흐리게 표시한다. GUI에서 바로 등록할 수 있다 |
| 2 | 등록과 그룹 관리 | 스킬과 GUI 모두에서 등록, 해제, 그룹 지정과 변경을 할 수 있다 |
| 3 | 그룹 모델 | 세션당 그룹은 1개다. 그룹이 없는 세션은 "미분류"로 표시한다 |
| 4 | recap | (a) 첫 요청과 최근 요청/응답 기록 표시 (LLM 없음), (b) 스킬 호출 시 Claude가 직접 작성한 요약 |
| 5 | 상태 | 생성중 / 응답 완료(입력 대기) / 응답 필요(권한 요청, AskUserQuestion) / 종료 |
| 6 | 종료된 세션 | "종료" 상태로 남겨둔다. resume하면 다시 활성 상태가 된다. 사용자가 삭제할 수 있고 "종료 세션 접기" 토글을 둔다 |
| 7 | 세션 이동 | MVP에 포함한다. 터미널마다 지원 수준이 다르다 (3.5 참고). 주 사용 터미널은 Warp |
| 8 | 알림 | 응답 필요와 응답 완료 모두 알린다. 설정에서 각각 끌 수 있다 |
| 9 | 서명과 배포 | SpaceSwitcher와 같은 방식이다. 자체 서명 인증서 `SpaceSwitcher Signing`을 함께 쓰고, 공증 없이 전용 tap과 postflight quarantine 해제로 배포한다 |
| 10 | UI | 메뉴바(상태 배지와 간단한 목록)와 메인 윈도우(그룹, 세션, 상세) |
| 11 | hook과 스킬 설치 | Claude Code 플러그인으로 설치한다. repo 자체를 플러그인 marketplace로 쓴다 |
| 12 | 최소 macOS | 14 Sonoma |
| 13 | 저장소 | public 모노레포 `unh6unh6/session-monitor` |

---

## 3. 아키텍처

```
┌──────────── claude 프로세스 (터미널마다) ────────────┐
│  이벤트 발생 → 플러그인 hook 실행 (짧게 떴다 종료)    │
└───────────────────────┬──────────────────────────────┘
                        │ append (JSONL)
                        ▼
              ~/.session-monitor/
              ├── sessions/<session_id>.json   등록 정보 (그룹, recap)
              ├── events/<session_id>.jsonl    등록 세션의 이벤트 로그
              ├── seen/<session_id>.json       미등록 세션의 최신 상태 1건 (덮어쓰기)
              └── pids/<pid>                   claude PID → 현재 session_id
                        ▲
                        │ FSEvents 감시 + 읽기/쓰기
┌───────────────────────┴──────────────────────────────┐
│  SessionMonitor.app (SwiftUI, 메뉴바 + 윈도우)        │
└──────────────────────────────────────────────────────┘
```

### 핵심 원칙
- **hook은 플러그인으로 항상 켜두고, 등록 여부는 hook 안에서 판단한다.** 스킬 frontmatter의 hook은 스킬이 활성화된 동안에만 동작하고, 세션 도중에 추가한 hook 설정은 반영되지 않을 수 있어서 이 구조를 택했다.
- **추적 키는 `session_id`, 보조 키는 claude PID.**
  - PID는 프로세스 생존 확인과 `/clear` 이후 등록 승계에 쓴다.
- **앱과 hook은 파일로만 통신한다.** 앱이 꺼져 있어도 이벤트가 유실되지 않는다.
- **hook은 외부 의존성 없이(jq, python 없이) POSIX shell로 작성한다.** 미등록 세션은 수 ms 안에 종료한다.

### 3.1 구독 이벤트

| hook 이벤트 | 용도 | 상태 전이 |
|---|---|---|
| `SessionStart` | 세션 시작, resume, `/clear` 감지. PID와 tty 기록 | 응답 완료(입력 대기) |
| `UserPromptSubmit` | 사용자 요청 기록 (`prompt`) | 생성중 |
| `PreToolUse` (matcher: `AskUserQuestion`) | Claude의 질문 감지 | 응답 필요 |
| `Notification` | 권한 요청 (`permission_prompt`) 등 | 응답 필요 |
| `Stop` | 응답 종료. 마지막 응답은 transcript에서 추출 | 응답 완료 |
| `SessionEnd` | 정상 종료 | 종료 |

모든 도구 호출(`PreToolUse` 전체, `PostToolUse`)은 MVP에서 구독하지 않는다. 턴당 hook 실행을 2~3회로 유지하기 위해서다.

**권한 승인 후 상태 복귀**: 권한을 승인한 뒤 응답 필요에서 생성중으로 돌아가는 시점은 다음 이벤트로 추정한다. 정확하게 처리하는 방법은 구현 중에 검증한다 (아래 7장 참고).

### 3.2 hook 동작

```
stdin JSON 읽기
→ session_id, hook_event_name 추출
→ SessionStart이고 source=clear이며 pids/<PPID>가 등록된 세션을 가리키면
     → 새 session_id로 등록 정보 승계 (그룹 유지)
→ pids/<PPID> 갱신 (SessionStart일 때)
→ sessions/<session_id>.json이 있으면
     → events/<session_id>.jsonl에 {ts, ppid, tty, raw 입력} 한 줄 append
   없으면
     → seen/<session_id>.json을 최신 상태 1건으로 덮어쓰기
→ exit 0 (Claude 동작에는 절대 영향을 주지 않음)
```

### 3.3 스킬 (플러그인 네임스페이스 `session-monitor:`)

| 스킬 | 동작 |
|---|---|
| `/session-monitor:register [그룹]` | 현재 세션을 등록하고 그룹을 지정한다. Claude가 현재 맥락의 recap을 작성해서 함께 저장한다 |
| `/session-monitor:recap` | recap을 다시 작성해서 갱신한다 |
| `/session-monitor:group <그룹>` | 그룹을 변경한다 |
| `/session-monitor:leave` | 등록을 해제한다 |

- 스킬은 `${CLAUDE_SESSION_ID}` 치환으로 세션 ID를 얻고 플러그인의 스크립트를 호출한다.
- **다른 스킬과의 연동**: 스킬 간에 공식적인 의존성 선언은 없다. 다른 스킬의 SKILL.md에 아래 둘 중 하나를 넣는다.
  - "작업 시작 전에 `/session-monitor:register <그룹>`을 실행하라"는 지시
  - 등록 스크립트를 직접 호출하는 코드

### 3.4 앱

- **메뉴바**
  - 아이콘 배지: 응답 필요 n개, 생성중 n개
  - 응답 필요 세션을 가장 위에 보여주는 간단한 목록
- **메인 윈도우**
  - 사이드바: 그룹 목록, "미분류", "미등록(흐리게)", "종료 세션 접기" 토글
  - 세션 카드: 상태, 프로젝트 경로, 마지막 요청, 경과 시간
  - 상세: recap, 요청/응답 타임라인(마지막 응답은 transcript에서 추출), 세션 정보(PID, tty, 터미널)
  - 세션 카드 더블클릭, "세션으로 이동" 버튼, 알림 클릭 시 해당 터미널로 이동 (3.5)
  - 그룹 이동은 드래그나 컨텍스트 메뉴로 한다. 미등록 세션의 "등록" 버튼도 있다
- **생존 확인**: 주기적으로 `kill(pid, 0)`을 호출한다. PID가 사라졌는데 `SessionEnd`가 오지 않았으면 "종료"로 표시한다.
- **알림**: 응답 필요와 응답 완료 상태로 바뀔 때 `UserNotifications`로 띄운다.
- **기술 스택**: Swift, SwiftUI(`@Observable`, `MenuBarExtra`), XcodeGen(`project.yml`). SpaceSwitcher와 같은 구성이다.

### 3.5 세션으로 이동

이동은 "어느 창/탭인지 찾기"와 "그 창이 있는 Space로 전환해서 앞으로 가져오기" 두 단계로 나뉜다.

**hook이 기록하는 정보** (`SessionStart`마다)
- claude PID, tty
- 환경 변수: `TERM_PROGRAM`, `TERM_SESSION_ID`, `ITERM_SESSION_ID`, `TMUX`, `TMUX_PANE`
- 부모 프로세스를 거슬러 올라가 찾은 터미널 앱의 PID와 번들 ID

**터미널별 지원 수준**

| 터미널 | MVP 이동 수준 | 방법 |
|---|---|---|
| Warp (주력) | 창 단위 + Space 전환 | 터미널 앱 PID로 AX 창 목록을 얻어 창을 앞으로 가져온다. 탭과 pane 단위는 아래 조사 결과에 따라 결정 |
| Terminal.app | 탭 단위 | AppleScript로 tty가 같은 탭을 선택한다 |
| iTerm2 | 탭/pane 단위 | AppleScript로 tty 또는 `ITERM_SESSION_ID`로 세션을 선택한다 |
| tmux | pane 단위 + 바깥 터미널 창 | `tmux select-window`/`select-pane` 후 바깥 터미널은 위 방식으로 처리 |
| 그 외 | 앱 단위 | 앱 활성화 |

**Space 전환**
- 창을 앞으로 가져와도 macOS가 해당 Space로 전환하지 않는 경우가 있다. 이때는 SpaceSwitcher의 Space 전환 코드(창이 속한 Space를 찾아 직접 전환)를 가져와 쓴다.
- 손쉬운 사용(Accessibility) 권한이 필요하다. Terminal.app과 iTerm2 제어에는 자동화(Automation) 권한도 필요하다. 고정 서명 인증서와 번들 ID를 유지해서 업데이트 후에도 권한이 유지되게 한다.

**Warp 탭 단위 이동 조사 (M0)**
- Warp에는 AppleScript 사전이 없고, `warp://` URL scheme에도 기존 탭으로 포커스를 옮기는 기능이 확인되지 않았다.
- 다음 방법을 시도해보고 가능한 수준을 정한다.
  1. AX 트리에 탭이나 pane이 노출되는지
  2. 창 제목(활성 탭 제목)과 세션 정보를 매칭할 수 있는지. Claude Code가 터미널 제목을 설정하므로 이를 활용할 수 있는지
  3. 탭 전환 단축키를 보내며 창 제목이 일치할 때까지 순회하는 우회 방법이 실용적인지
- 창이 여러 개일 때 맞는 창을 찾는 방법도 같이 확인한다.

---

## 4. 저장소 구조

```
session-monitor/
├── .claude-plugin/marketplace.json   # repo를 플러그인 marketplace로
├── plugin/
│   ├── .claude-plugin/plugin.json
│   ├── hooks/hooks.json
│   ├── scripts/                      # hook.sh, register.sh 등 (POSIX sh)
│   └── skills/{register,recap,group,leave}/SKILL.md
├── app/
│   ├── project.yml                   # XcodeGen
│   └── SessionMonitor/               # Swift 소스
├── scripts/release.sh                # SpaceSwitcher release.sh 기반
└── docs/
    ├── plan.md                       # 이 문서
    ├── DECISIONS.md                  # 이후 결정 기록
    └── RELEASING.md
```

---

## 5. 설치 흐름 (사용자 관점)

```sh
# 1. 앱 설치
brew install --cask unh6unh6/tap/session-monitor

# 2. Claude Code에서 플러그인 설치
/plugin marketplace add unh6unh6/session-monitor
/plugin install session-monitor@session-monitor

# 3. 추적할 세션에서 등록
/session-monitor:register 이슈A
```

- 앱은 첫 실행 때 플러그인이 설치됐는지 확인한다. 기준은 `~/.session-monitor`에 이벤트가 들어오는지이고, 들어오지 않으면 설치 방법을 안내한다.

---

## 6. 배포

SpaceSwitcher(`docs/DECISIONS.md`의 "배포 · 서명" 절, `docs/RELEASING.md`)와 같은 방식이다.

- **서명**: 자체 서명 인증서 `SpaceSwitcher Signing`을 재사용한다. 번들 ID는 고정한다.
  - 권한 승인은 번들 ID별로 따로 관리된다.
- **배포 채널**: GitHub Releases에 Universal DMG를 올리고, `unh6unh6/homebrew-tap`에 `Casks/session-monitor.rb`를 추가한다.
- **Gatekeeper**: cask postflight에서 `xattr -dr com.apple.quarantine`를 실행한다.
- **릴리스 자동화**: `./scripts/release.sh x.y.z`
  - 빌드, 서명 검증, DMG 생성, sha256 계산
  - cask 생성, 태그, Release 생성, tap 갱신
- **플러그인 버전**: `plugin.json` 버전을 앱 버전과 맞춘다. 이벤트 파일에는 `schema` 버전 필드를 넣는다.

---

## 7. 구현 전에 검증할 것

Claude Code의 동작을 가정한 부분이다. 구현 첫 단계에서 실제로 확인하고, 결과를 DECISIONS.md에 기록한다.

1. 스킬에서 `${CLAUDE_SESSION_ID}` 치환이 동작하는가?
2. 스킬 frontmatter hook의 유효 범위. "항상 켜둔 플러그인 hook" 구조를 택한 근거를 재확인한다.
3. `/clear` 때 새 session_id가 발급되고 `SessionStart(source: clear)`가 오는가? hook의 PPID가 같은 claude 프로세스를 가리키는가?
4. `--resume`/`--continue` 때 session_id가 유지되는가? 유지되지 않으면 transcript 경로로 기존 세션과 연결한다.
5. `Stop` 입력에 마지막 응답 필드가 있는가? 없으면 transcript JSONL을 파싱한다.
6. `Notification`의 종류(`permission_prompt`, `idle_prompt` 등)와 권한 승인 후 상태 복귀 시점.
7. hook의 실제 실행 시간 (미등록 세션 기준 목표 10ms 이하).
8. Warp 탭/창 단위 이동 가능성 (3.5의 조사 항목).
9. 터미널 창을 앞으로 가져올 때 Space 전환이 자동으로 되는지, SpaceSwitcher 코드가 필요한지.

---

## 8. MVP 마일스톤

1. **M0 검증**: 7장의 항목을 확인하고 이벤트 스키마를 확정한다.
2. **M1 플러그인**: hook.sh, 등록 스킬 4종, marketplace 구성. 앱 없이 `~/.session-monitor`에 파일이 쌓이는지 확인한다.
3. **M2 앱 코어**: 파일 감시, 상태 머신, 생존 확인, 데이터 모델 (그룹, 세션, 이벤트).
4. **M3 앱 UI**: 메뉴바, 메인 윈도우, 그룹 관리, 미등록 세션 표시.
5. **M4 알림**: 응답 필요와 응답 완료 알림, 설정.
6. **M5 세션 이동**: 터미널 정보 수집, Warp 창 이동과 Space 전환, Terminal.app/iTerm2/tmux 탭 이동, 권한 안내.
7. **M6 배포**: release.sh, cask, README.

---

## 9. MVP 이후 이슈 후보

- Warp 탭/pane 단위 이동 (M0 조사 결과 MVP에 들어가지 못한 경우)
- 그 외 터미널(Ghostty, WezTerm, Kitty, VS Code 내장 터미널) 이동 지원
- Stop마다 haiku로 자동 recap
- 앱에서 세션으로 응답 보내기
- 도구 사용 상세 표시 (PreToolUse/PostToolUse 선택 구독)
- 그룹별 통계와 작업 시간
- 공증과 공식 homebrew/cask 등록
