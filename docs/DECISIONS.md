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
- **미확인**:
  - 거부했을 때의 이벤트(`PostToolUseFailure` 또는 다음 `Stop`)
  - auto 모드에서 AskUserQuestion이 `PermissionRequest`를 내는지
  - M1에서 `PostToolUseFailure`도 구독해 확인한다.

## D6. hook 성능

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
└── pids/<claude_pid>                           현재 session_id (tmp + rename)
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
- 파일명의 `ts`는 정렬용이다. 셸에서 밀리초를 얻을 수 없으므로, 같은 초 안의 순서는 앱이 `hook_event_name` 규칙(D5)으로 보완한다.

## D10. `/clear` 후 화면 표시: 세션 기준 카드

- **결정**: 카드는 `session_id`마다 하나다. `/clear`하면 이전 세션은 "종료(clear)" 카드로 남고, 새 세션이 같은 그룹에 새 카드로 추가된다.
- 새 세션은 그룹을 자동으로 이어받고, `meta.json`의 `previous`에 이전 세션 ID를 남긴다. 나중에 "이어보기" 같은 기능에 쓸 수 있다.
- 종료 카드는 "종료 세션 접기" 토글로 숨길 수 있다.
