#!/usr/bin/env bash
# build.sh — End-to-end build of Aevum.
#
#   ./build.sh           # build everything (engine + app)
#   ./build.sh engine    # just the C++ engine static lib
#   ./build.sh app       # just the Xcode app (assumes engine is built)
#   ./build.sh run       # build + launch the app
#   ./build.sh release   # build Release + package a distributable DMG
#   ./build.sh clean     # wipe all build artifacts
#
# Prereqs: Xcode.app installed + selected, Homebrew, uv, the .venv with
# magenta-rt[mlx] and cmake<3.28 installed. See README.md for first-time
# setup.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ACTION="${1:-all}"

# Ensure Xcode (not just CLT) is active — MLX needs the Metal compiler.
ensure_xcode() {
    if ! xcrun --find metal >/dev/null 2>&1; then
        echo "ERROR: 'metal' compiler not found." >&2
        echo "       Install Xcode.app from the Mac App Store, then:" >&2
        echo "         sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
        exit 1
    fi
}

build_engine() {
    bash "$ROOT/scripts/build_engine.sh"
}

build_app() {
    ensure_xcode
    if [[ ! -f "$ROOT/build/engine/libaevum_engine.a" ]]; then
        echo "==> Engine lib missing — building it first."
        build_engine
    fi
    echo "==> Generating Xcode project with XcodeGen…"
    xcodegen generate 2>&1 | tail -5
    echo "==> Building app with xcodebuild…"
    set -o pipefail
    xcodebuild -project "$ROOT/Aevum.xcodeproj" \
        -scheme Aevum \
        -configuration Debug \
        -destination 'platform=macOS' \
        build \
        CODE_SIGNING_ALLOWED=NO \
        2>&1 | tail -30 || { echo "BUILD FAILED — see above."; exit 1; }
    # xcodebuild places the app in DerivedData unless CONFIGURATION_BUILD_DIR is set.
    local derivedData=$(xcodebuild -project "$ROOT/Aevum.xcodeproj" -showBuildSettings \
        -configuration Debug 2>/dev/null | grep " BUILT_PRODUCTS_DIR " | awk '{print $3}')
    APP_PATH="$derivedData/Aevum.app"
    echo ""
    echo "==> App built: $APP_PATH"
}

run_app() {
    build_app
    echo "==> Launching $APP_PATH"
    open "$APP_PATH"
}

release_app() {
    ensure_xcode
    bash "$ROOT/scripts/package_release.sh"
}

clean_all() {
    echo "==> Cleaning build artifacts…"
    rm -rf "$ROOT/build" "$ROOT/Aevum.xcodeproj" "$ROOT/Aevum.xcworkspace"
    echo "==> Done."
}

case "$ACTION" in
    engine)  build_engine ;;
    app)     build_app ;;
    run)     run_app ;;
    release) release_app ;;
    clean)   clean_all ;;
    all)     build_engine && build_app ;;
    *) echo "Usage: $0 [engine|app|run|release|clean|all]"; exit 1 ;;
esac
