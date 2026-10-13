#!/usr/bin/env bash
# Publish a new session-monitor version: the macOS app (GitHub Release + Homebrew tap) and the
# Claude Code plugin (version bump; the plugin itself is installed from this repo's marketplace).
#
#   ./scripts/release.sh 0.2.0            # bump, test, build DMG, commit + tag, push, create release, update tap
#   ./scripts/release.sh 0.2.0 --dry-run  # everything up to the DMG; no commit, push or release
#
# Signed with the self-signed "SpaceSwitcher Signing" cert (shared with SpaceSwitcher) and NOT notarized
# (no paid Apple account). Using the same cert every time keeps permission grants across updates.
# Based on SpaceSwitcher's scripts/release.sh; see docs/RELEASING.md.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="SessionMonitor"
PROJECT_DIR="app"
PROJECT_YML="$PROJECT_DIR/project.yml"
PLUGIN_JSON="plugin/.claude-plugin/plugin.json"
IDENTITY="SpaceSwitcher Signing"
DERIVED="build/release/DerivedData"
BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"
TAP_REPO="unh6unh6/homebrew-tap"
TAP_NAME="unh6unh6/tap"   # how users refer to it: brew strips the "homebrew-" prefix
CASK="session-monitor"

VERSION="${1:-}"
DRY_RUN="${2:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "사용법: $0 <버전 예: 0.2.0> [--dry-run]" >&2
    exit 1
fi
TAG="v$VERSION"
DMG="build/release/$APP_NAME-$VERSION.dmg"

if [[ "$DRY_RUN" != "--dry-run" ]]; then
    [[ -z "$(git status --porcelain)" ]] || { echo "커밋 안 된 변경이 있습니다. 먼저 커밋하세요." >&2; exit 1; }
    [[ "$(git branch --show-current)" == "main" ]] || { echo "main 브랜치에서 실행하세요." >&2; exit 1; }
    ! git rev-parse "$TAG" >/dev/null 2>&1 || { echo "$TAG 태그가 이미 있습니다." >&2; exit 1; }
fi

# Undo the version bump if anything fails before the release commit (and always on a dry run).
COMMITTED=""
restore() { [[ -n "$COMMITTED" ]] || git checkout -q -- "$PROJECT_YML" "$PLUGIN_JSON"; }
trap restore EXIT

echo "==> 1/7 버전 설정: $VERSION (앱 + 플러그인)"
BUILD=$(( $(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' "$PROJECT_YML") + 1 ))
sed -i '' -E "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/" "$PROJECT_YML"
sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" "$PROJECT_YML"
sed -i '' -E "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" "$PLUGIN_JSON"
(cd "$PROJECT_DIR" && xcodegen generate --quiet)

echo "==> 2/7 테스트 (플러그인 + 앱)"
plugin/tests/run.sh >/dev/null || { echo "플러그인 테스트 실패: plugin/tests/run.sh" >&2; exit 1; }
xcodebuild test -project "$PROJECT_DIR/$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$DERIVED" -quiet

echo "==> 3/7 Release 빌드 (Apple Silicon + Intel)"
rm -rf "$BUILT"
xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" build -quiet
codesign --verify --deep --strict "$BUILT"
AUTHORITY=$(codesign -dvv "$BUILT" 2>&1 | sed -n 's/^Authority=//p' | head -1)
[[ "$AUTHORITY" == "$IDENTITY" ]] || { echo "서명 인증서가 '$AUTHORITY' 입니다 ('$IDENTITY' 여야 함)." >&2; exit 1; }
echo "    아키텍처: $(lipo -archs "$BUILT/Contents/MacOS/$APP_NAME")"

echo "==> 4/7 DMG 생성"
STAGING="build/release/dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$BUILT" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"   # drag-to-install target
hdiutil create -volname "Session Monitor $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
codesign --sign "$IDENTITY" "$DMG"
SHA256=$(shasum -a 256 "$DMG" | cut -d' ' -f1)   # after signing: codesign rewrites the DMG
echo "    $DMG ($(du -h "$DMG" | cut -f1)), sha256 $SHA256"

# Under a Casks/ directory so `brew style` applies cask rules rather than generic Ruby ones.
CASK_FILE="build/release/Casks/$CASK.rb"
mkdir -p "$(dirname "$CASK_FILE")"
sed -e "s/{{VERSION}}/$VERSION/" -e "s/{{SHA256}}/$SHA256/" scripts/cask.rb.template > "$CASK_FILE"
brew style --quiet "$CASK_FILE" >/dev/null || { echo "cask 문법 오류: brew style $CASK_FILE" >&2; exit 1; }

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "드라이런 완료: 커밋·푸시·릴리스는 하지 않았습니다. (cask: $CASK_FILE)"
    exit 0
fi

echo "==> 5/7 커밋 + 태그 + 푸시"
git add "$PROJECT_YML" "$PLUGIN_JSON"
git commit -q -m "release: $TAG"
COMMITTED=1
git tag -a "$TAG" -m "Session Monitor $VERSION"
git push -q origin main "$TAG"

echo "==> 6/7 GitHub Release"
REPO_URL=$(gh repo view --json url -q .url)
gh release create "$TAG" "$DMG" --title "Session Monitor $VERSION" --generate-notes --notes "$(cat <<NOTES
## 설치
**1. 앱 — Homebrew (권장):** \`brew install --cask $TAP_NAME/$CASK\` · 업데이트는 \`brew upgrade --cask $CASK\`

**2. Claude Code 플러그인** (Claude Code 안에서):
\`\`\`
/plugin marketplace add unh6unh6/session-monitor
/plugin install session-monitor@session-monitor
\`\`\`
플러그인 업데이트: \`/plugin marketplace update session-monitor\`

**앱 직접 설치:** 아래 **$APP_NAME-$VERSION.dmg** 다운로드 → 열기 → $APP_NAME 을 Applications 폴더로 드래그 → 처음 실행이 막히면 **시스템 설정 → 개인정보 보호 및 보안 → "그래도 열기"**

자세한 설명: $REPO_URL#readme
NOTES
)"

echo "==> 7/7 Homebrew tap 갱신: $TAP_REPO"
TAP_DIR=$(mktemp -d)
gh repo clone "$TAP_REPO" "$TAP_DIR" -- -q
mkdir -p "$TAP_DIR/Casks"
cp "$CASK_FILE" "$TAP_DIR/Casks/$CASK.rb"
git -C "$TAP_DIR" add "Casks/$CASK.rb"
git -C "$TAP_DIR" commit -q -m "$CASK $VERSION"
git -C "$TAP_DIR" push -q
rm -rf "$TAP_DIR"

echo "완료: $(gh release view "$TAG" --json url -q .url)"
echo "      brew install --cask $TAP_NAME/$CASK"
