# 결정 기록

설계 결정과 그 근거를 남긴다. 새 결정은 아래에 추가하고, 바뀐 결정은 지우지 않고 "대체됨"으로 표시한다.

검증 환경: Claude Code 2.1.296, macOS (Darwin 27), Warp 0.2026.09.16 / 2026-10-13, M0(#8)

---

## D1. hook은 플러그인으로 항상 켜둔다

- **결정**: hook은 Claude Code 플러그인의 `hooks/hooks.json`으로 모든 세션에 상시 등록하고, 등록 여부는 hook 스크립트가 판단한다.
- **근거**:
  - 스킬 frontmatter의 `hooks`는 스킬을 호출한 시점부터 같은 프롬프트의 `UserPromptSubmit`까지 포함해 동작한다.
  - 그러나 `/clear` 뒤의 새 세션과 `--resume`으로 다시 연 프로세스에서는 발생하지 않았다.
  - 등록 상태가 `/clear`와 resume을 넘어 유지되어야 하므로 스킬 hook으로는 부족하다.

## D2. 등록은 스킬의 실행 구문으로 한다

- **결정**: 등록 스킬은 `` !`... ${CLAUDE_SESSION_ID} ...` `` 실행 구문으로 등록 스크립트를 호출한다.
- **근거**:
  - `${CLAUDE_SESSION_ID}`는 실행 구문 안에서도 치환된다.
  - Claude가 도구를 쓰지 않아도 스킬을 불러오는 순간 등록된다.
  - 대화형(auto 모드)에서는 이 실행이 `PreToolUse`/`PostToolUse`(Bash)로도 관측됐다.
- **주의**: `claude -p`에서 Bash 권한이 없으면 실행 구문이 거부되고 스킬 호출 전체가 결과 없이 끝났다. 권한 허용 방식은 M1에서 확정한다.
- **참고**: Bash 도구 환경에는 `CLAUDE_CODE_SESSION_ID`, `CLAUDE_PID` 환경 변수도 있다. 대체 수단으로 쓸 수 있다.

## D3. 추적 키는 session_id, 보조 키는 CLAUDE_PID

| 상황 | session_id | 프로세스 | 관측된 이벤트 |
|---|---|---|---|
| `/clear` | 새 ID | 같음 | `SessionEnd(reason: clear)` → `SessionStart(source: clear)` |
| `--resume` / `--continue` | 유지 | 새 PID | `SessionStart(source: resume)` |
| `/exit` | - | 종료 | `SessionEnd(reason: prompt_input_exit)` |
| `-p` 종료 | - | 종료 | `SessionEnd(reason: other)` |

- hook 환경 변수 `CLAUDE_PID`는 claude 프로세스 PID이고, hook의 `$PPID`와 같았다.
- `/clear` 승계는 `pids/<CLAUDE_PID>` 매핑으로 처리한다.
- resume은 session_id가 같으므로 별도 처리 없이 기록이 이어진다.

## D4. 마지막 응답은 Stop.last_assistant_message

- `Stop` 입력에 `last_assistant_message`가 있다. 공식 문서도 Stop 시점의 transcript에는 마지막 메시지가 없을 수 있으니 이 필드를 쓰라고 안내한다.
- transcript 파싱은 하지 않는다. `transcript_path`는 상세 보기의 링크 용도로만 보관한다.

## D5. 응답 필요는 PermissionRequest, 복귀는 PostToolUse

관측 (permission mode `default`):

```
PreToolUse(Bash) → PermissionRequest(Bash) [즉시] → Notification(permission_prompt) [+6초] → (승인) → PostToolUse(Bash) → Stop
PreToolUse(AskUserQuestion) → PermissionRequest(AskUserQuestion) [즉시] → Notification(permission_prompt) [+6초] → (응답) → PostToolUse(AskUserQuestion) → Stop
```

- **결정**:
  - "응답 필요"는 `PermissionRequest`로 즉시 전환한다. `Notification`은 보조 신호로 쓴다.
  - "생성중" 복귀는 `PostToolUse`로 판단한다. 도구 호출마다 실행되므로 `async: true`로 등록한다.
  - `PreToolUse`는 구독하지 않는다.
- **M1에서 추가 확인** (#9):
  - auto 모드에서도 AskUserQuestion은 `PermissionRequest`를 낸다.
  - 권한 요청을 Esc로 거부하면 턴이 중단되고 그 뒤로 `Stop`, `PostToolUseFailure`를 포함해 아무 이벤트도 오지 않는다. 그래서 다음 `UserPromptSubmit`까지 "응답 필요"가 유지된다. 사용자가 이미 그 터미널 앞에 있는 상황이라 MVP에서는 허용한다. 개선 후보: 일정 시간 뒤 오는 `Notification(idle_prompt)`을 "입력 대기"로 처리.

## D6. hook 성능

M1 구현(#9) 기준, 1회 평균 (프로세스 생성 오버헤드 포함):

| 경로 | 시간 | 빈도 |
|---|---|---|
| 미등록 세션의 `PostToolUse` (무시) | 7.4ms | 도구 호출마다, async |
| 미등록 세션의 `Stop` (seen 기록) | 14.0ms | 턴마다 |
| 등록 세션의 `Stop` (spool 기록) | 15.8ms | 턴마다 |

M0 측정치(필터 경로만):

- 등록하지 않은 세션의 필터 경로(셸 파라미터 확장으로 session_id 추출 → 파일 존재 확인 → 종료)는 1회 평균 6.6ms였다. 측정 방식에 따른 프로세스 생성 오버헤드를 포함한 값이다. 같은 조건에서 `/usr/bin/true`는 1.2ms였다.
- hook 입력은 compact JSON이고 `session_id`가 첫 필드였다. 다만 파서는 공백이나 필드 순서에 의존하지 않게 만든다.

## D7. Warp 이동은 MVP에서 창 단위까지

- **AppleScript**: sdef가 없다 (`error -192`).
- **URL scheme**: `warp://` 하나뿐이고, 기존 탭 포커스는 지원하지 않는다.
- **AX**:
  - 앱의 `AXWindows`는 빈 배열이다.
  - `AXFocusedWindow`, `AXMainWindow`는 얻을 수 있다. 창 제목은 활성 탭 제목이며, Claude Code가 세션 이름으로 설정한다 (`◐ session-monitor`).
  - 창 하위에는 텍스트 영역(화면 일부 텍스트)과 창 버튼만 있고 탭/pane 요소는 없다.
  - Window 메뉴에 창 목록(활성 탭 제목)이 나온다.
- **탭 전환 시도**:
  - Tab 메뉴의 "Switch to Next/Previous Tab" 항목은 `AXEnabled = false`라 눌러지지 않았다.
  - `CGEvent.postToPid`로 보낸 `Cmd+Shift+[`도 반영되지 않았다.
- **결론**: MVP는 Warp 활성화 + 창 선택(+ Space 전환)까지 구현한다. 탭/pane 단위는 #1에서 전역 키 입력과 제목 매칭 순회 방식을 계속 조사한다.

## D8. 이벤트 파일 스키마 (v1) — D9로 대체됨

append-only JSONL(`events/<session_id>.jsonl`) 방식이었으나 동시 쓰기 문제로 D9의 spool 방식으로 바꿨다.

## D9. 저장 구조: 이벤트는 spool, 등록 정보는 값별 파일

- **문제**:
  - 한 세션에서도 hook이 동시에 실행된다 (async `PostToolUse`, 병렬 서브에이전트).
  - 셸의 `>>` append는 긴 데이터(`last_assistant_message`, 긴 프롬프트)를 write() 한 번으로 쓴다는 보장이 없어 줄이 섞일 수 있다.
  - 등록 정보 하나의 JSON을 스킬과 앱이 동시에 수정하면 한쪽 변경이 유실될 수 있다.
- **결정**: 아래 구조를 쓴다.

```
~/.session-monitor/
├── spool/<session_id>/<ts>-<pid>-<rand>.json   이벤트 1건 = 파일 1개 (hook이 .tmp에 쓰고 rename)
├── sessions/<session_id>/                      이 디렉토리가 있으면 "등록됨"
│   ├── group                                   그룹 이름 (스킬, 앱)
│   ├── recap.md                                recap (스킬)
│   └── meta.json                               등록 시각, previous(clear 이전 session_id) (등록 시 1회)
├── seen/<session_id>.json                      미등록 세션의 최신 이벤트 1건 (tmp + rename으로 덮어쓰기)
├── pids/<claude_pid>                           현재 session_id (tmp + rename)
└── bin/session-monitor                         다른 스킬용 CLI 링크 (D12)
```

- **쓰기 규칙**: 모든 쓰기는 같은 디렉토리의 임시 파일에 쓰고 `mv`(rename)로 교체한다. 그래서 읽는 쪽은 완성된 파일만 본다.
- **앱의 처리**:
  - spool 파일을 이름 순(타임스탬프)으로 읽어 앱 저장소(Application Support)에 반영하고 삭제한다.
  - 앱이 꺼져 있으면 spool에 쌓였다가 다음 실행 때 처리된다.
- **순서 역전 대응**: async `PostToolUse`가 `Stop`보다 늦게 기록될 수 있다. 그래서 `PostToolUse`는 "응답 필요 → 생성중" 전이에만 쓰고 다른 상태에서는 무시한다.
- **삭제 순서**: 앱이 세션을 지울 때는 `sessions/<id>/`를 먼저 지운다. 그 뒤에 오는 hook은 미등록으로 판단해 spool에 쓰지 않는다.

spool 파일 형식:

```json
{"schema":1,"ts":"2026-10-13T22:54:50+09:00","pid":63748,"tty":"ttys003",
 "term":{"program":"WarpTerminal","session":"","iterm":"","tmux":"","tmux_pane":""},
 "input":{ /* hook stdin 원본 JSON */ }}
```

- `input`은 원본 그대로 저장하고 해석은 앱이 한다. Claude Code가 필드를 추가해도 hook을 고칠 필요가 없다.
- 정렬은 파일 수정 시각(APFS는 나노초 단위)을 먼저 보고, 같으면 파일명(`<epoch초>-<pid>-<hook pid>`)으로 정한다. 셸에서는 밀리초를 얻을 수 없어 파일명만으로는 같은 초 안의 순서를 알 수 없기 때문이다. 등록 직전 상태는 `0-seen.json`으로 들어간다.

## D10. `/clear` 후 화면 표시: 세션 기준 카드

- **결정**: 카드는 `session_id`마다 하나다. `/clear`하면 이전 세션은 "종료(clear)" 카드로 남고, 새 세션이 같은 그룹에 새 카드로 추가된다.
- 새 세션은 그룹을 자동으로 이어받고, `meta.json`의 `previous`에 이전 세션 ID를 남긴다. 나중에 "이어보기" 같은 기능에 쓸 수 있다.
- 종료 카드는 "종료 세션 접기" 토글로 숨길 수 있다.

## D11. 스킬의 실행 구문 권한은 allowed-tools로 허용한다

- 스킬 frontmatter의 `allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/session-monitor.sh *)`가 `` !`...` `` 실행 구문에도 적용된다.
- `-p` 모드, default 모드, auto 모드 모두에서 권한 요청 없이 등록과 recap 저장이 됐다 (M1, #9).
- **모델이 호출할 수 있는 `register` 스킬에는 `$ARGUMENTS`를 실행 구문에 넣지 않는다.** 인자를 셸 명령에 그대로 이어 붙이면 명령 주입이 가능하기 때문이다. 그룹 지정은 Claude가 별도 명령으로 실행하고, 이 명령은 일반 권한 검사를 거친다.
- 사용자만 호출할 수 있는 `group` 스킬(`disable-model-invocation: true`)은 인자를 실행 구문에 넣는다.

## D12. 다른 스킬용 고정 경로 `~/.session-monitor/bin/session-monitor`

- 플러그인 설치 경로는 버전마다 바뀌고, 다른 플러그인의 스킬에서는 `${CLAUDE_PLUGIN_ROOT}`가 그 플러그인을 가리킨다.
- 그래서 hook이 `SessionStart` 때마다 `~/.session-monitor/bin/session-monitor`를 현재 버전의 `session-monitor.sh`로 향하는 심볼릭 링크로 갱신한다.
- 다른 스킬은 이 경로를 실행 구문과 `allowed-tools`에 쓴다 (README 참고). 실제로 다른 플러그인 스킬에서 등록되는 것을 확인했다.
- 이 경로는 `SESSION_MONITOR_HOME`을 따르므로, 저장 위치를 바꾸면 링크 위치도 바뀐다.

## D13. 앱 코어: spool을 앱 저장소로 옮기고, 생존 확인은 시작 시각까지 본다

- **저장소**: 등록 세션의 상태와 타임라인(최근 300건)은 `~/Library/Application Support/SessionMonitor/sessions.json`에 저장한다.
  - spool 파일은 이 저장이 끝난 뒤에 지운다. 그래서 앱이 중간에 죽어도 이벤트를 다시 적용할 수는 있어도 잃지는 않는다.
  - 미등록 세션은 `seen/`에서 매번 다시 계산하고 저장하지 않는다. 종료된 지 24시간이 지난 seen 파일은 앱이 지운다.
- **갱신**: `~/.session-monitor`를 FSEvents로 감시하고, 5초마다 타이머로도 갱신한다. 타이머는 생존 확인과, FSEvents를 놓쳤을 때를 대비한 것이다.
- **생존 확인**: 아래 둘 중 하나면 "종료(processGone)"로 처리한다. pid 재사용을 막기 위해서다.
  - `kill(pid, 0)`으로 프로세스가 없다고 확인될 때
  - 프로세스는 있지만 그 시작 시각(`sysctl KERN_PROC_PID`)이 이 pid로 처음 받은 이벤트 시각 + 5초보다 늦을 때 (다른 프로세스가 같은 pid를 받은 경우)
- **상태 머신**: `SessionReducer`는 순수 함수로 테스트한다. 종료된 세션은 `SessionStart`(resume)나 `UserPromptSubmit`이 와야만 되살아나고, 늦게 도착한 async 이벤트는 무시한다.
- **테스트 격리**: 단위 테스트는 앱을 test host로 실행한다. 이때 앱이 실제 `~/.session-monitor`를 만들지 않도록 테스트 환경에서는 임시 경로를 쓴다.

## D14. 앱 UI 구성 (M3)

- **메뉴바**
  - 아이콘: 응답 필요가 있으면 `!` 말풍선과 개수, 없고 생성중이 있으면 `…` 말풍선과 개수, 둘 다 없으면 기본 아이콘.
  - 팝오버: 종료되지 않은 등록 세션을 급한 순서(응답 필요 → 생성중 → 응답 완료, 같은 상태면 최근 순)로 최대 12개 보여준다. 항목을 누르면 메인 윈도우에서 그 세션을 연다.
- **메인 윈도우** (3단)
  - 사이드바: 전체 / 그룹들 / 미분류 / 미등록. 숫자는 활성 세션 수이고, 응답 필요 세션이 있는 항목은 아이콘이 주황색으로 바뀐다.
  - 목록: 세션 행. "전체"에서는 그룹별 섹션으로 나눈다(그룹 이름순, 미분류는 맨 아래). 각 섹션 안은 급한 순서로 정렬한다.
  - 상세: recap, 마지막 요청/응답, 타임라인(최근 50건), 세션 정보.
- **그룹 관리**: 그룹은 따로 저장하지 않고 세션의 `group` 값에서 만든다. 그래서 세션이 하나도 없는 빈 그룹은 존재하지 않는다.
  - 세션을 사이드바의 그룹으로 드래그하면 그 그룹으로 옮긴다.
  - 우클릭 메뉴나 상세의 "작업" 메뉴로 그룹 이동, 새 그룹, 등록 해제, 종료 세션 삭제를 한다.
  - 미등록 세션을 그룹에 드롭하거나 "등록" 메뉴를 쓰면 등록된다.
- **Dock 아이콘**: 메인 윈도우가 열려 있는 동안만 보인다 (activation policy를 `.regular`와 `.accessory` 사이에서 전환).
- **스냅샷**: `TEST_RUNNER_SNAPSHOT_DIR=<dir> xcodebuild test ... -only-testing:SessionMonitorTests/SnapshotTests`로 샘플 데이터 화면을 PNG로 만든다. 화면 녹화 권한 없이 UI를 확인하기 위한 것이다. 오프스크린 렌더링이라 사이드바의 선택 행과 아이콘 색은 실제와 다르게 나온다.

## D15. 알림 (M4)

- **대상**: 등록 세션만 알린다. 플러그인을 정식 설치하면 모든 세션에 hook이 걸리므로, 미등록 세션까지 알리면 너무 많아진다.
- **알리는 경우**:
  - **응답 필요**: 다른 상태에서 "응답 필요"로 처음 바뀔 때. 이미 응답 필요인데 Notification이 뒤따라와도 다시 알리지 않는다. 소리를 낸다.
  - **응답 완료**: 생성중 또는 응답 필요에서 "응답 완료"로 바뀔 때. 세션 시작이나 resume으로 "응답 완료"가 되는 경우는 알리지 않는다. 본문은 마지막 응답의 첫 부분(200자)이고, API 오류가 있으면 오류를 보여준다. 소리는 내지 않는다.
- **제외하는 경우**:
  - 상태가 바뀐 지 2분이 지난 경우. 앱을 켤 때 밀려 있던 spool을 한꺼번에 처리하면서 지난 일을 알리지 않기 위해서다.
  - 사용자가 앱 안에서 그 세션을 보고 있는 경우.
- **알림 하나만 유지**: 알림 식별자를 `session-<id>`로 써서, 같은 세션의 새 알림이 이전 알림을 대체한다. 응답 필요 상태에서 터미널로 답해 생성중으로 돌아가면, 남아 있던 알림을 지운다.
- **클릭**: 알림을 누르면 메인 윈도우에서 그 세션을 연다. SwiftUI의 `openWindow`는 뷰 안에서만 쓸 수 있다. 그래서 항상 떠 있는 메뉴바 아이콘 뷰가 `Navigation.windowRequest` 값의 변화를 감지해서 창을 연다.
- **설정**: 메뉴바 팝오버의 종 아이콘에서 응답 필요/응답 완료 알림을 각각 끈다 (UserDefaults `notifyNeedsResponse`, `notifyDone`, 기본값 켜짐).

## D16. 세션으로 이동 (M5)

- **범위**: Warp와 Terminal.app만 지원한다(직접 확인할 수 있는 두 가지). 그 외 터미널은 앱 활성화만 하고, iTerm2와 tmux는 #5로 넘긴다.
- **터미널 앱 찾기**:
  - claude 프로세스에서 부모 프로세스를 따라 올라가다 처음 만나는 GUI 앱(`NSRunningApplication`에 번들 ID가 있는 프로세스)을 터미널로 본다.
  - Warp는 `claude → -zsh → Warp 보조 프로세스 → Warp`인데, 보조 프로세스는 앱으로 잡히지 않아 건너뛴다.
  - 부모를 따라갈 수 없으면 `TERM_PROGRAM`으로 대신 찾는다.
- **Warp**:
  - Window 메뉴 항목은 AX로 누를 수 있다(M0의 Tab 메뉴와 달리 활성 상태).
  - 창 제목은 활성 탭 제목이고, 앞에 Claude Code의 상태 기호가 붙는다(`◐ 세션이름`). 기호를 떼고 세션 제목과 같은 창이 있으면 그 창을 띄운다.
  - 같은 창이 없으면 Warp를 활성화한다. 창을 띄울 때 손쉬운 사용 권한이 필요하고, 권한이 없으면 앱 활성화만 한다.
- **Terminal.app**: AppleScript로 `tty`가 같은 탭을 선택하고 그 창을 맨 앞으로 가져온다. 자동화 권한이 필요하다(`NSAppleEventsUsageDescription`).
- **Space 전환**: 앱을 활성화하거나 창을 띄우면 macOS가 그 Space로 넘어간다(시스템 기본 설정). private API(SpaceSwitcher 방식)는 이 방식이 실패하는 경우가 확인되면 도입한다.
- **활성화**: macOS 14의 협조적 활성화에 맞춰 `NSApp.yieldActivation(to:)` 후 `activate()`를 호출한다.
- **진입점**:
  - 목록에서 더블클릭
  - 우클릭 메뉴와 상세의 "터미널로 이동" 버튼
  - 메뉴바 팝오버 각 행의 화살표 버튼
  - 알림 클릭(이동에 실패하면 앱에서 세션을 연다)
- **알림 클릭 타이밍**: 알림을 클릭하면 macOS가 이 앱을 활성화하는데, 이 활성화가 클릭 처리보다 늦게 끝날 수 있다. 그러면 먼저 넘겨준 터미널 포커스를 다시 빼앗아간다(실제로 확인됨). 그래서 앱이 활성화되기를 `didBecomeActive`로 기다린 뒤 터미널로 넘긴다. 1초 안에 활성화되지 않으면 그냥 넘긴다.
