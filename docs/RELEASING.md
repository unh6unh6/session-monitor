# 릴리스

마일스톤의 이슈가 모두 끝나면 **사용자가** 실행한다(또는 사용자가 명시적으로 요청할 때만 Claude가 실행한다). GitHub Release와 공개 Homebrew tap을 갱신하는 외부 공개 작업이기 때문이다.

```sh
./scripts/release.sh 0.2.0 --dry-run   # DMG까지만. 커밋·푸시·게시 없음 (버전 변경 자동 복구)
./scripts/release.sh 0.2.0             # 실제 릴리스
```

SpaceSwitcher의 `scripts/release.sh`를 기반으로 만들었다. 서명 인증서(`SpaceSwitcher Signing`)와 tap 저장소(`unh6unh6/homebrew-tap`)를 SpaceSwitcher와 함께 쓴다.

## release.sh가 하는 일

1. **버전**: `app/project.yml`의 `MARKETING_VERSION`을 인자 값으로, `CURRENT_PROJECT_VERSION`을 +1로 바꾼다. `plugin/.claude-plugin/plugin.json`의 `version`도 같은 값으로 바꾼다.
2. **테스트**: 플러그인 테스트(`plugin/tests/run.sh`)와 앱 전체 테스트를 실행한다.
3. **빌드**: Release Universal 빌드(Apple Silicon + Intel) 후 `SpaceSwitcher Signing` 서명인지 검증한다.
4. **DMG와 cask**:
   - `build/release/SessionMonitor-<버전>.dmg`를 만든다(앱 + Applications 링크).
   - DMG에 서명한다.
   - sha256을 계산한다.
   - `scripts/cask.rb.template`로 `build/release/Casks/session-monitor.rb`를 만들고 `brew style`로 검사한다.
5. **커밋과 태그**: `release: v<버전>` 커밋과 태그를 만들고 `git push origin main v<버전>`을 실행한다.
6. **GitHub Release**: `gh release create`로 만든다. DMG를 첨부하고 앱과 플러그인 설치 안내, 자동 생성 노트를 넣는다.
7. **tap 갱신**: `unh6unh6/homebrew-tap`을 임시로 클론해서 `Casks/session-monitor.rb`를 교체하고 푸시한다.

5단계 커밋 전에 실패하면 `project.yml`과 `plugin.json`은 자동으로 원래대로 돌아간다(trap).

## 플러그인 배포

플러그인은 별도로 배포하지 않는다. 이 저장소가 곧 marketplace(`.claude-plugin/marketplace.json`)이다.
- 사용자는 `/plugin marketplace update session-monitor`로 `main`의 최신 플러그인을 받는다.
- 그래서 플러그인 변경은 `main`에 푸시되는 순간 배포된다. 앱 릴리스와 상관없다.
- hook과 앱이 주고받는 파일 형식(DECISIONS.md D9, `schema`)을 바꿀 때는 앱 릴리스와 순서를 맞춘다.

## 릴리스 후

- **마일스톤 닫기**: `gh api -X PATCH repos/unh6unh6/session-monitor/milestones/<번호> -f state=closed`
- **실제 설치 검증**: 설치본을 건드리지 않게 임시 폴더로 설치한다.
  ```sh
  brew install --cask --appdir="$TMPDIR/Apps" unh6unh6/tap/session-monitor
  xattr "$TMPDIR/Apps/SessionMonitor.app"      # com.apple.quarantine 이 없어야 함
  brew uninstall --cask session-monitor         # 주의: uninstall quit 이 실행 중인 앱을 종료함
  ```

## 중간에 실패했을 때

| 어디서 | 상태 | 복구 |
|--------|------|------|
| 1~4 | 아무것도 안 나감 | 원인 고치고 다시 실행 |
| 5 푸시 후 6 실패 | 태그는 GitHub에 있음, 릴리스 없음 | `gh release create v<버전> build/release/SessionMonitor-<버전>.dmg --title "Session Monitor <버전>" --generate-notes` 수동 실행 → 7단계 수동 |
| 7 실패 | 릴리스는 있음, tap이 옛 버전 | tap 클론 → `build/release/Casks/session-monitor.rb` 복사 → 커밋·푸시 |
| 같은 버전 다시 | 태그 중복으로 스크립트가 거부 | 패치 버전을 올려서 릴리스 (게시된 태그는 지우지 않는 것을 원칙으로) |

## Homebrew cask

- **tap**: 저장소는 `unh6unh6/homebrew-tap`, 사용자에게 보이는 이름은 `unh6unh6/tap`이다(brew가 `homebrew-` 접두어를 생략).
- **템플릿**: `scripts/cask.rb.template`. `{{VERSION}}`과 `{{SHA256}}`을 치환한다. `{{appdir}}`는 Homebrew 자체 템플릿 문법이라 그대로 둔다.
- **Homebrew 최신 규칙**: `postflight do`는 쓸 수 없고 `postflight_steps`를 쓴다. macOS 버전은 `depends_on macos: :sonoma`로 표기한다.
- **`caveats`**: 설치가 끝나면 플러그인 설치 명령을 보여준다.
- **`zap`**: `~/.session-monitor`(플러그인과 공유하는 기록)까지 지운다.
- **공식 homebrew/cask**: 공증이 필요하다(#7).
