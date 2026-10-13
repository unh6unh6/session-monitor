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
| 6 | 종료된 세션 | "종료" 상태로 남겨둔다. resume하면 다시 활성 상태가 된다. 사용자가 삭제할 수 있고 "종료 세션 접기" 토글을 둔다. `/clear` 이전 세션도 "종료(clear)" 카드로 남는다 (D10) |
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
                        │ 이벤트 1건 = 파일 1개 (tmp → rename)
                        ▼
              ~/.session-monitor/
              ├── spool/<session_id>/*.json    등록 세션의 이벤트 (앱이 읽고 삭제)
              ├── sessions/<session_id>/       등록 정보: group, recap.md, meta.json
              ├── seen/<session_id>.json       미등록 세션의 최신 상태 1건 (덮어쓰기)
              └── pids/<claude_pid>            claude PID → 현재 session_id
                        ▲
                        │ FSEvents 감시 + 읽기/쓰기
┌───────────────────────┴──────────────────────────────┐
│  SessionMonitor.app (SwiftUI, 메뉴바 + 윈도우)        │
└──────────────────────────────────────────────────────┘
```

### 핵심 원칙
- **hook은 플러그인으로 항상 켜두고, 등록 여부는 hook 안에서 판단한다.** 스킬 frontmatter의 hook은 호출 시점부터 동작하지만 `/clear`와 resume 뒤에는 사라진다 (M0 검증, DECISIONS.md D1).
- **추적 키는 `session_id`, 보조 키는 claude PID.**
  - PID는 hook 환경 변수 `CLAUDE_PID`에서 얻는다 (없으면 `$PPID`). 프로세스 생존 확인과 `/clear` 이후 등록 승계에 쓴다.
- **앱과 hook은 파일로만 통신한다.** 앱이 꺼져 있어도 이벤트가 유실되지 않는다.
- **모든 쓰기는 임시 파일 + rename이다.** 동시 실행되는 hook끼리, 또는 스킬과 앱이 서로의 쓰기를 깨뜨리지 않는다 (DECISIONS.md D9).
- **hook은 외부 의존성 없이(jq, python 없이) POSIX shell로 작성한다.** 미등록 세션은 수 ms 안에 종료한다.

### 3.1 구독 이벤트

| hook 이벤트 | 용도 | 상태 전이 |
|---|---|---|
| `SessionStart` | 세션 시작(`source`: startup / resume / clear / compact / fork). PID, tty, 터미널 정보 기록 | 응답 완료(입력 대기) |
| `UserPromptSubmit` | 사용자 요청 기록 (`prompt`) | 생성중 |
| `PermissionRequest` | 권한 요청과 AskUserQuestion 모두 대화상자를 띄우는 즉시 발생 (`tool_name`) | 응답 필요 |
| `Notification` (`permission_prompt`, `idle_prompt`, `elicitation_dialog`) | 보조 신호. 권한 요청은 약 6초 늦게 옴 | 응답 필요 |
| `PostToolUse` (`async: true`) | 권한 승인/질문 응답 후 작업 재개 감지 | 응답 필요 → 생성중 |
| `Stop` | 응답 종료. `last_assistant_message`에 마지막 응답 포함 | 응답 완료 |
| `StopFailure` | API 오류로 턴 종료 (`error`) | 응답 완료 (오류 표시) |
| `SessionEnd` | 종료 (`reason`: clear / resume / logout / prompt_input_exit / other) | 종료 (`clear`면 승계 대기) |

- `PostToolUse`는 도구 호출마다 실행되므로 `async: true`로 Claude를 막지 않게 한다. hook은 상태가 "응답 필요"일 때만 의미가 있으므로 앱에서 그 외에는 무시한다.
- `PreToolUse`는 구독하지 않는다. AskUserQuestion도 `PermissionRequest`로 잡힌다 (DECISIONS.md D5).

### 3.2 hook 동작

```
stdin JSON 읽기
→ session_id, hook_event_name 추출
   (입력은 compact JSON이고 session_id가 첫 필드지만, 공백 유무에 관계없이 추출한다)
→ pid = $CLAUDE_PID (없으면 $PPID)
→ SessionStart이고 source=clear이며 pids/<pid>가 등록된 세션을 가리키면
     → sessions/<새 id>/ 생성: group 복사, meta.json에 previous=<이전 id>
→ pids/<pid> 갱신 (SessionStart일 때)
→ sessions/<session_id>/ 디렉토리가 있으면
     → spool/<session_id>/<ts>-<pid>-<rand>.json 에 {schema, ts, pid, tty, term, raw 입력} 기록 (tmp → rename)
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

- 스킬은 `` !`${CLAUDE_PLUGIN_ROOT}/scripts/register.sh ${CLAUDE_SESSION_ID} ...` `` 형태의 실행 구문으로 등록한다. Claude가 도구를 호출하지 않아도 스킬을 불러오는 순간 등록된다 (D2).
- 실행 구문은 권한 규칙의 적용을 받는다. `-p` 모드에서 Bash 권한이 없으면 스킬 호출 전체가 조용히 실패하므로, `allowed-tools`나 설치 안내로 스크립트 실행을 허용하는 방법을 M1에서 확정한다.
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
  - 상세: recap, 요청/응답 타임라인(마지막 응답은 `Stop`의 `last_assistant_message`), 세션 정보(PID, tty, 터미널)
  - 세션 카드 더블클릭, "세션으로 이동" 버튼, 알림 클릭 시 해당 터미널로 이동 (3.5)
  - 그룹 이동은 드래그나 컨텍스트 메뉴로 한다. 미등록 세션의 "등록" 버튼도 있다
- **생존 확인**: 주기적으로 `kill(pid, 0)`을 호출한다. PID가 사라졌는데 `SessionEnd`가 오지 않았으면 "종료"로 표시한다.
- **알림**: 응답 필요와 응답 완료 상태로 바뀔 때 `UserNotifications`로 띄운다.
- **기술 스택**: Swift, SwiftUI(`@Observable`, `MenuBarExtra`), XcodeGen(`project.yml`). SpaceSwitcher와 같은 구성이다.

### 3.5 세션으로 이동

이동은 "어느 창/탭인지 찾기"와 "그 창이 있는 Space로 전환해서 앞으로 가져오기" 두 단계로 나뉜다.

**hook이 기록하는 정보** (`SessionStart`마다)
- claude PID(`CLAUDE_PID`), tty
- 환경 변수: `TERM_PROGRAM`, `TERM_SESSION_ID`, `ITERM_SESSION_ID`, `TMUX`, `TMUX_PANE`
- 부모 프로세스를 거슬러 올라가 찾은 터미널 앱의 PID와 번들 ID

**터미널별 지원 수준**

| 터미널 | MVP 이동 수준 | 방법 |
|---|---|---|
| Warp (주력) | 창 단위 + Space 전환 | Warp 활성화 후 Window 메뉴의 창 항목(활성 탭 제목)으로 창을 고른다. 탭/pane 단위는 #1 |
| Terminal.app | 탭 단위 | AppleScript로 tty가 같은 탭을 선택한다 |
| iTerm2 | 탭/pane 단위 | AppleScript로 tty 또는 `ITERM_SESSION_ID`로 세션을 선택한다 |
| tmux | pane 단위 + 바깥 터미널 창 | `tmux select-window`/`select-pane` 후 바깥 터미널은 위 방식으로 처리 |
| 그 외 | 앱 단위 | 앱 활성화 |

**Space 전환**
- 창을 앞으로 가져와도 macOS가 해당 Space로 전환하지 않는 경우가 있다. 이때는 SpaceSwitcher의 Space 전환 코드(창이 속한 Space를 찾아 직접 전환)를 가져와 쓴다.
- 손쉬운 사용(Accessibility) 권한이 필요하다. Terminal.app과 iTerm2 제어에는 자동화(Automation) 권한도 필요하다. 고정 서명 인증서와 번들 ID를 유지해서 업데이트 후에도 권한이 유지되게 한다.

**Warp 조사 결과 (M0, DECISIONS.md D7)**
- AppleScript 사전이 없고, `warp://` URL scheme은 기존 탭 포커스를 지원하지 않는다.
- AX: `AXWindows`는 비어 있다. 포커스/메인 창과 Window 메뉴의 창 목록은 얻을 수 있다.
- 창 제목은 활성 탭의 제목이고, Claude Code가 세션 이름으로 설정한다 (예: `◐ session-monitor`, 앞 글자는 스피너).
- AX 트리에 탭과 pane은 없다. 창의 텍스트 영역에서 화면 일부 텍스트를 읽을 수 있다.
- Tab 메뉴의 "Switch to Next Tab"은 AX로 비활성 상태로 보여 누를 수 없었다. 프로세스 지정 키 입력도 동작하지 않았다.
- 결론: MVP는 창 단위까지. 탭/pane 단위(전역 키 입력 + 제목 매칭 순회 등)는 #1에서 계속 조사한다.

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

## 7. M0 검증 결과

M0(#8)에서 검증을 마쳤다. 결과와 근거는 `docs/DECISIONS.md`에 있다.

| # | 항목 | 결과 |
|---|---|---|
| 1 | 스킬의 `${CLAUDE_SESSION_ID}` | ✅ 동작 (실행 구문 안에서도 치환) |
| 2 | 스킬 frontmatter hook 범위 | ⚠️ `/clear`·resume 후 사라짐 → 플러그인 hook 상시 |
| 3 | `/clear` | ✅ 같은 PID에서 새 session_id, `SessionStart(source: clear)` |
| 4 | resume/continue | ✅ session_id 유지, PID만 변경 |
| 5 | 마지막 응답 | ✅ `Stop.last_assistant_message` |
| 6 | 응답 필요와 복귀 | ✅ `PermissionRequest` 즉시 발생, 복귀는 `PostToolUse` |
| 7 | hook 실행 시간 | ✅ 미등록 세션 약 6.6ms |
| 8 | Warp 이동 | 창 단위까지. 탭/pane은 #1 |
| 9 | Space 자동 전환 | 미검증. M5에서 확인 |

---

## 8. MVP 마일스톤

1. **M0 검증**: 7장의 항목을 확인하고 이벤트 스키마를 확정한다.
2. **M1 플러그인**: hook.sh, 등록 스킬 4종, marketplace 구성. 앱 없이 `~/.session-monitor`에 파일이 쌓이는지 확인한다.
3. **M2 앱 코어**: spool 처리, 상태 머신, 생존 확인, 데이터 모델 (그룹, 세션, 이벤트).
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
