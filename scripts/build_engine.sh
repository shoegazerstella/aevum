#!/usr/bin/env bash
# build_engine.sh — Build magentart::core + dependencies (MLX, TFLite,
# SentencePiece) via CMake, then merge all static archives into a single
# libaevum_engine.a that the Xcode app links against.
#
# Output:
#   build/engine/libaevum_engine.a      (merged static lib)
#   build/engine/headers/magentart/*.h  (public headers)
#
# Requires: Xcode.app (for the Metal compiler), cmake, a Python venv with
# cmake<3.28 (provides the `cmake` binary used by the magenta-realtime
# build scripts).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MRT_DIR="$ROOT/magenta-realtime"
MRT_BUILD="$ROOT/build/mrt-cmake"
ENGINE_OUT="$ROOT/build/engine"
VENV="$ROOT/.venv"

# Locate a usable cmake. The magenta-realtime README pins cmake<3.28; we
# install that into the venv. Prefer the venv copy if present.
CMAKE="${CMAKE:-}"
if [[ -z "$CMAKE" ]]; then
    if [[ -x "$VENV/bin/cmake" ]]; then
        CMAKE="$VENV/bin/cmake"
    elif command -v cmake >/dev/null 2>&1; then
        CMAKE="$(command -v cmake)"
    else
        echo "ERROR: cmake not found. Run: source .venv/bin/activate" >&2
        exit 1
    fi
fi

echo "==> Using cmake: $CMAKE ($("$CMAKE" --version | head -1))"

# Sanity: the Metal compiler must be reachable. It ships with Xcode.app,
# NOT the standalone Command Line Tools, so fail fast with a clear message.
if ! xcrun --find metal >/dev/null 2>&1; then
    echo "ERROR: 'metal' compiler not found." >&2
    echo "       Install Xcode.app from the Mac App Store, then run:" >&2
    echo "         sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi

# 1. Configure (only if not already configured).
if [[ ! -f "$MRT_BUILD/CMakeCache.txt" ]]; then
    echo "==> Configuring magenta-realtime (one-time, ~2 min)…"
    "$CMAKE" "$MRT_DIR" -B "$MRT_BUILD" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -Wno-dev
else
    echo "==> CMake cache found — skipping configure."
fi

# 2. Build magentart::core (and its dependencies). Skip example apps —
#    we only need the core static library and its transitive deps.
echo "==> Building magentart_core + dependencies (10–20 min first time)…"
"$CMAKE" --build "$MRT_BUILD" --target magentart_core -j"$(sysctl -n hw.ncpu)"

# 3. Collect every static archive produced by the build. CMake scatters
#    them across _deps/<name>-build/ and the core build dir. We merge them
#    all with `libtool -static` so the Xcode linker only needs one binary.
#
#    Unlike the old approach (ar -x on each .a then re-merging .o files),
#    we merge .a files directly to avoid silent data loss from duplicate
#    object-file names within a single archive (e.g. libtensorflow-lite.a
#    has two common.cc.o members — ar -x overwrites the first with the
#    second, dropping symbols like _TfLiteDelegateCreate).
echo "==> Collecting static archives…"
mkdir -p "$ENGINE_OUT"
rm -f "$ENGINE_OUT/libaevum_engine.a"

# Find every .a produced by the build. Restrict to actual build output
# dirs (`core/` and `_deps/*-build/`) so we skip: (a) source-provided
# fat binaries like supercollider's scUBlibsndfile.a that libtool can't
# merge, and (b) test fixtures under *-src/.../testdata/*.a.
ARCHIVES=()
while IFS= read -r -d '' archive; do
    ARCHIVES+=("$archive")
done < <(find "$MRT_BUILD/core" "$MRT_BUILD"/_deps/*-build \
    -name '*.a' -type f -not -path '*/testdata/*' -print0)

# 4. Merge all .a files into one big static archive.
#    libtool -static on macOS can merge .a files directly — it adds every
#    object member from each input archive into the output archive.
echo "==> Merging into libaevum_engine.a…"
LIBTOOL_OUTPUT=$(libtool -static -o "$ENGINE_OUT/libaevum_engine.a" \
    "${ARCHIVES[@]}" 2>&1) || {
    echo "ERROR: libtool -static failed." >&2
    echo "$LIBTOOL_OUTPUT" >&2
    exit 1
}
# Log non-fatal libtool warnings (e.g. "has no symbols").
echo "$LIBTOOL_OUTPUT" >&2
# Collect the list of merged member filenames for diagnostics.
# ar -t on the final archive gives us the cumulative member list.
ar -t "$ENGINE_OUT/libaevum_engine.a" > "$ENGINE_OUT/objects.txt"

# 5. Copy public headers so Xcode can find them via USER_HEADER_SEARCH_PATHS.
echo "==> Copying headers…"
mkdir -p "$ENGINE_OUT/headers"
rm -rf "$ENGINE_OUT/headers/magentart"
cp -R "$MRT_DIR/core/include/magentart" "$ENGINE_OUT/headers/magentart"

# 6. Copy the MLX metallib (precompiled Metal shaders) next to where the
#    app bundle will look for it at runtime. The app copies it into
#    Contents/MacOS/ during the install phase.
MLX_METALLIB="$MRT_BUILD/_deps/mlx-build/mlx/backend/metal/kernels/mlx.metallib"
if [[ -f "$MLX_METALLIB" ]]; then
    cp "$MLX_METALLIB" "$ENGINE_OUT/mlx.metallib"
    echo "==> Copied mlx.metallib"
else
    echo "WARNING: mlx.metallib not found at $MLX_METALLIB" >&2
fi

OBJ_COUNT=$(wc -l < "$ENGINE_OUT/objects.txt" | tr -d ' ')
LIB_SIZE=$(du -h "$ENGINE_OUT/libaevum_engine.a" | cut -f1)
echo ""
echo "==> Done."
echo "    libaevum_engine.a : $LIB_SIZE ($OBJ_COUNT object files)"
echo "    headers             : $ENGINE_OUT/headers/magentart/"
echo "    mlx.metallib        : $ENGINE_OUT/mlx.metallib"
