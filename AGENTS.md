# AGENTS.md — Build & test commands for Aevum

## First-time setup

```sh
# 1. Install Xcode.app from the Mac App Store, then select it:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# 2. Install Homebrew packages:
brew install xcodegen

# 3. Create the Python venv + install magenta-rt[mlx] and cmake<3.28:
uv venv --python 3.12 .venv
source .venv/bin/activate
uv pip install "magenta-rt[mlx]" "cmake<3.28"

# 4. Download model assets to ~/.cache/magenta-rt-v2:
mkdir -p ~/.cache/magenta-rt-v2
export MAGENTA_HOME=~/.cache
mrt models init --download-path ~/.cache/magenta-rt-v2
mrt models download mrt2_small --download-path ~/.cache/magenta-rt-v2
```

The `~/Documents/Magenta/` default path is TCC-protected on a fresh macOS
terminal; `~/.cache` avoids the permission prompt. The app's dev paths
point at `~/.cache/magenta-rt-v2` (see `AevumApp.swift`).

## Build commands

```sh
# Full end-to-end build (engine static lib + Xcode app):
./build.sh

# Or step-by-step:
./build.sh engine   # CMake build of magentart::core + deps, merged into build/engine/libaevum_engine.a
./build.sh app      # XcodeGen generate + xcodebuild
./build.sh run      # build + launch the app
./build.sh release  # build Release + package a distributable DMG at build/release/Aevum-<ver>.dmg

# Clean everything:
./build.sh clean
```

The first `./build.sh engine` run takes 10–20 minutes (MLX + TFLite +
SentencePiece from source). Subsequent runs are incremental.

## Lint / typecheck

Swift: there is no standalone typecheck target — `xcodebuild build` is the
canonical check. To just typecheck without linking:

```sh
xcodebuild -project Aevum.xcodeproj -scheme Aevum -configuration Debug \
    -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

There is no lint config yet (no SwiftLint). Add one if/when needed.

## Tests

No test target exists yet. When adding tests, create a `AevumTests`
target in `project.yml` and run:

```sh
xcodebuild test -project Aevum.xcodeproj -scheme Aevum -destination 'platform=macOS'
```

## Architecture notes

- `Sources/Engine/EngineBridge.h` + `.mm` is the Obj-C++ facade over
  `magentart::core::RealtimeRunner`. Pure Obj-C in the public API so Swift
  can import it via the bridging header.
- `Sources/Engine/AudioEngine.swift` pulls stereo Float32 from the bridge
  via `AVAudioSourceNode` on the audio thread.
- `Sources/Engine/MIDIManager.swift` routes CoreMIDI notes + CC to bridge
  setters, with a CC→param map (MIDI-learnable).
- `Sources/Engine/EngineController.swift` is the `@MainActor` orchestrator
  ObservableObject that SwiftUI views observe.
- `Sources/Import/` is the offline pipeline: decode → beat-track → slice →
  MusicCoCa-embed → store. `BeatTracker` is native vDSP; embedding
  extraction talks to the bridge.
- `Sources/Similarity/` computes cosine similarity over 768-dim
  MusicCoCa embeddings and suggests setlists (smooth/contrast/cluster).
- `Sources/Storage/LibraryStore.swift` is SQLite (system libsqlite3, no
  external dep). Embeddings are Float32 BLOBs.

## Known constants (from mlx_engine.h)

- `kMaxPrompts = 6` (6 blend slots)
- `kMusicCoCaEmbeddingDim = 768`
- `kMaxPCAComponents = 6`, `kMaxCentroids = 6`
- `kFrameSamples = 1920` @ 48 kHz / 25 Hz stereo
- `kNumRVQLevels = 12`

## Current blocker (resolve after Xcode install)

The C++ engine build fails with `xcrun: error: unable to find utility
"metal"` because only Command Line Tools are installed. The Metal compiler
ships with Xcode.app only. Once Xcode is installed and selected via
`xcode-select`, `./build.sh engine` will work. The Python pipeline
(`mrt mlx generate`) already works — it uses prebuilt MLX wheels.
