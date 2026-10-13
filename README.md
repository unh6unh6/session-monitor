# session-monitor

여러 Claude Code 세션의 상태를 그룹 단위로 한곳에서 보는 macOS 메뉴바 앱입니다.

- **상태**: 생성중 / 응답 완료 / 응답 필요(권한 요청, 질문) / 종료를 실시간으로 표시
- **그룹**: 세션을 `이슈A`처럼 그룹으로 묶어서 보기
- **내용**: 세션별 recap, 마지막 요청과 응답, 타임라인
- **알림**: 응답이 필요하거나 응답이 끝나면 macOS 알림
- **이동**: 세션에서 그 터미널 창으로 바로 이동 (Warp, Terminal.app)

계획은 [docs/plan.md](docs/plan.md), 결정 기록은 [docs/DECISIONS.md](docs/DECISIONS.md), 진행 상황은 [Issues](https://github.com/unh6unh6/session-monitor/issues)에서 관리합니다.

## 설치

두 가지를 설치합니다. 앱은 화면을 보여주고, Claude Code 플러그인은 세션 상태를 앱에 전달합니다.

### 1. 앱

```sh
brew install --cask unh6unh6/tap/session-monitor
```

업데이트는 `brew upgrade --cask session-monitor`입니다. 앱을 실행하면 메뉴바에 말풍선 아이콘이 생깁니다.

Homebrew 없이 설치하려면 [Releases](https://github.com/unh6unh6/session-monitor/releases)에서 DMG를 받아 Applications 폴더로 드래그합니다. 이 앱은 공증(notarization)을 받지 않아서 처음 실행이 막힙니다. **시스템 설정 → 개인정보 보호 및 보안 → "그래도 열기"**를 한 번 누르면 됩니다. brew로 설치하면 이 단계가 필요 없습니다.

### 2. Claude Code 플러그인

Claude Code 안에서:

```
/plugin marketplace add unh6unh6/session-monitor
/plugin install session-monitor@session-monitor
```

업데이트는 `/plugin marketplace update session-monitor`입니다.

## 사용

추적할 세션에서 등록합니다.

| 명령 | 동작 |
|---|---|
| `/session-monitor:register [그룹]` | 현재 세션을 등록하고(그룹 선택), Claude가 지금까지의 recap을 저장 |
| `/session-monitor:recap` | recap 갱신 |
| `/session-monitor:group [그룹]` | 그룹 변경 (이름 없이 실행하면 미분류) |
| `/session-monitor:leave` | 등록 해제 |

- `/clear`를 하면 새 세션이 같은 그룹으로 자동 등록되고, 이전 세션은 "종료(clear)"로 남습니다.
- `claude --resume`으로 다시 열면 기존 등록과 기록이 이어집니다.
- 등록하지 않은 세션도 앱의 "미등록"에 흐리게 보이고, 앱에서 바로 등록할 수 있습니다.

앱에서는 이렇게 씁니다.
- **메뉴바**: 응답 필요/생성중 개수와 세션 목록을 봅니다. 각 행의 화살표 버튼을 누르면 그 세션의 터미널로 이동합니다.
- **메인 윈도우**:
  - 그룹별로 세션을 봅니다.
  - 세션을 그룹으로 드래그해 옮깁니다.
  - 우클릭 메뉴로 그룹 이동, 새 그룹, 등록 해제를 합니다.
  - 세션을 더블클릭하면 그 터미널로 이동합니다.
- **알림**: 알림을 클릭하면 그 세션의 터미널로 이동합니다. 메뉴바 팝오버의 종 아이콘에서 알림 종류별로 끌 수 있습니다.

### 권한

| 권한 | 언제 | 없으면 |
|---|---|---|
| 알림 | 첫 실행 때 요청 | 알림이 오지 않음 |
| 자동화 (Terminal) | Terminal.app 세션으로 처음 이동할 때 요청 | Terminal.app은 앱 활성화만 됨 |
| 손쉬운 사용 (선택) | 세션 상세의 "권한 설정" | Warp 창이 여러 개일 때 맞는 창을 고르지 못하고 Warp만 활성화 |

## 다른 스킬에서 세션 등록하기

스킬이 실행될 때 세션이 자동으로 등록되게 하려면, 그 스킬의 `SKILL.md`에 아래처럼 넣습니다.

```markdown
---
name: my-skill
allowed-tools: Bash(~/.session-monitor/bin/session-monitor *)
---

!`~/.session-monitor/bin/session-monitor register "${CLAUDE_SESSION_ID}" '이슈A'`

(이후 스킬 본문)
```

- `~/.session-monitor/bin/session-monitor`는 플러그인이 세션을 시작할 때마다 만들어두는 고정 경로입니다. 플러그인 버전이 바뀌어도 그대로 쓸 수 있습니다.
- 이미 등록된 세션이면 그룹만 갱신합니다.
- recap까지 남기려면 등록 대신 본문에 "작업 시작 전에 `/session-monitor:register 이슈A` 스킬을 실행하라"고 지시하세요.

## 제거

```sh
brew uninstall --cask session-monitor          # 앱만
brew uninstall --zap --cask session-monitor    # 앱 + 기록(~/.session-monitor, Application Support)
```

플러그인은 Claude Code에서 `/plugin uninstall session-monitor@session-monitor`로 제거합니다.

## 개발

```sh
# 앱 (app/)
cd app && xcodegen generate                          # 파일 추가/삭제 후. .xcodeproj는 커밋하지 않음
xcodebuild test -scheme SessionMonitor -destination 'platform=macOS' -derivedDataPath build/DerivedData
xcodebuild -scheme SessionMonitor -configuration Debug -derivedDataPath build/DerivedData build

# 플러그인
plugin/tests/run.sh                                  # 스크립트 테스트
claude --plugin-dir ./plugin                         # 로컬 플러그인으로 실행
SESSION_MONITOR_HOME=/tmp/sm claude --plugin-dir ./plugin   # 저장 위치 바꿔서 실행

# 릴리스
./scripts/release.sh 0.2.0 --dry-run                 # docs/RELEASING.md
```
