# session-monitor

여러 Claude Code 세션의 상태(생성중 / 응답 완료 / 응답 필요 / 종료)를 그룹 단위로 한곳에서 보는 macOS 메뉴바 앱.

> 개발 중입니다. MVP 계획은 [docs/plan.md](docs/plan.md), 결정 기록은 [docs/DECISIONS.md](docs/DECISIONS.md), 진행 상황은 [Issues](https://github.com/unh6unh6/session-monitor/issues)에서 관리합니다.

## Claude Code 플러그인

세션 이벤트를 기록하는 hook과 등록 스킬입니다. 앱은 이 플러그인이 `~/.session-monitor/`에 남긴 파일을 읽습니다.

### 설치

Claude Code에서:

```
/plugin marketplace add unh6unh6/session-monitor
/plugin install session-monitor@session-monitor
```

### 사용

| 명령 | 동작 |
|---|---|
| `/session-monitor:register [그룹]` | 현재 세션을 등록하고(그룹 선택), Claude가 지금까지의 recap을 저장 |
| `/session-monitor:recap` | recap 갱신 |
| `/session-monitor:group [그룹]` | 그룹 변경 (이름 없이 실행하면 미분류) |
| `/session-monitor:leave` | 등록 해제 |

`/clear`를 하면 새 세션이 같은 그룹으로 자동 등록됩니다. `claude --resume`으로 다시 열면 기존 등록이 그대로 이어집니다.

### 다른 스킬에서 세션 등록하기

스킬이 실행될 때 세션이 자동으로 등록되게 하려면, 그 스킬의 `SKILL.md`에 아래 두 줄을 넣습니다.

```markdown
---
name: my-skill
allowed-tools: Bash(~/.session-monitor/bin/session-monitor *)
---

!`~/.session-monitor/bin/session-monitor register "${CLAUDE_SESSION_ID}" '이슈A'`

(이후 스킬 본문)
```

- `~/.session-monitor/bin/session-monitor`는 플러그인이 세션 시작 때마다 만들어두는 고정 경로입니다. 플러그인 버전이 바뀌어도 그대로 쓸 수 있습니다.
- 이미 등록된 세션이면 그룹만 갱신합니다.
- recap까지 남기려면 등록 대신 본문에 "작업 시작 전에 `/session-monitor:register 이슈A` 스킬을 실행하라"고 지시하세요.

### 개발

```sh
plugin/tests/run.sh                                  # 스크립트 테스트
claude --plugin-dir ./plugin                         # 로컬 플러그인으로 실행
SESSION_MONITOR_HOME=/tmp/sm claude --plugin-dir ./plugin   # 저장 위치 바꿔서 실행
```
