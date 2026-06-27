#!/usr/bin/env bash
# package_release.sh — build a Release .app and wrap it in a distributable DMG.
#
# Output: build/release/Aevum-<version>.dmg
#
# The DMG contains Aevum.app + a symlink to /Applications (drag-to-install).
# No code signing / notarization — users right-click → Open the first time
# (documented on the landing page). Re-running this script overwrites the
# previous DMG.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Engine lib must exist (preBuildScript would rebuild it, but be explicit).
if [[ ! -f "$ROOT/build/engine/libaevum_engine.a" ]]; then
    echo "==> Engine lib missing — building it first."
    bash "$ROOT/scripts/build_engine.sh"
fi

# Read the marketing version from project.yml (fallback to "0.0.0").
VERSION=$(grep MARKETING_VERSION "$ROOT/project.yml" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
[[ -z "$VERSION" ]] && VERSION="0.0.0"

REL_DIR="$ROOT/build/release"
APP_DIR="$REL_DIR/Aevum.app"
DMG="$REL_DIR/Aevum-${VERSION}.dmg"

echo "==> Generating Xcode project…"
xcodegen generate 2>&1 | tail -3

echo "==> Building Release configuration…"
# Wipe any previous app bundle so stale resources (renamed/moved files)
# don't leak into the DMG via incremental builds.
rm -rf "$APP_DIR"
# Set CONFIGURATION_BUILD_DIR so the app lands in a known place (not DerivedData).
xcodebuild -project "$ROOT/Aevum.xcodeproj" \
    -scheme Aevum \
    -configuration Release \
    -destination 'platform=macOS' \
    build \
    CONFIGURATION_BUILD_DIR="$REL_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tail -20 || { echo "BUILD FAILED — see above."; exit 1; }

if [[ ! -d "$APP_DIR" ]]; then
    echo "ERROR: expected app at $APP_DIR, not found." >&2
    exit 1
fi

APP_SIZE=$(du -sh "$APP_DIR" | awk '{print $1}')
echo "==> App built: $APP_DIR ($APP_SIZE)"

# Sanity-check the Metal shader got copied.
if [[ ! -f "$APP_DIR/Contents/MacOS/mlx.metallib" ]]; then
    echo "WARNING: mlx.metallib missing from bundle — MLX will fail at runtime." >&2
fi

echo "==> Packaging DMG → $DMG"
STAGING="$REL_DIR/dmg-staging"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "Aevum ${VERSION}" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG" 2>&1 | tail -5

rm -rf "$STAGING"

DMG_SIZE=$(du -sh "$DMG" | awk '{print $1}')
echo ""
echo "==> Done."
echo "    DMG:   $DMG ($DMG_SIZE)"
echo "    App:   $APP_DIR"
echo ""
echo "Next: create a GitHub Release and attach the DMG as an asset."
