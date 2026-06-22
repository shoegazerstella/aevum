# Aevum — Project Status

**Last updated:** 2026-06-20
**State:** Phase 1 (scaffold + UI) complete. Engine build fixed and app builds successfully.

---

## The idea

A macOS app for live AI music performance built on Magenta RealTime 2 (`mrt2_small`, 230M params, real-time on any Apple Silicon). Load songs → auto-extract beat-aligned loops → morph between them in real time with a 2D prompt-surface pad → control every generation parameter live via MIDI. UI is an Ableton-style clip grid with a dark "studio instrument" aesthetic.

## User's design decisions (locked in)

- **UI:** SwiftUI native macOS app (not the React WebView pattern Magenta's reference apps use)
- **Loop extraction:** Beat-grid + MusicCoCa similarity (auto, with optional manual trim)
- **Live I/O:** Audio out + MIDI controller in (no live audio in for v1)
- **Plugin target:** Standalone only for v1 (no AUv3)
- **Project name:** Aevum (renamed from `xformer`)
- **UI aesthetic:** Slick, minimal, cool, modern — "like it was made by a cool designer"

## Confirmed model constants (from `magenta-realtime/core/include/magentart/mlx_engine.h`)

- `kMaxPrompts = 6` (6 blend slots)
- `kMusicCoCaEmbeddingDim = 768`
- `kMaxPCAComponents = 6`, `kMaxCentroids = 6`
- `kFrameSamples = 1920` @ 48 kHz / 25 Hz stereo
- `kNumRVQLevels = 12`
- Frame rate 25 Hz → 40 ms control latency

## Phase 0 — Spike (DONE)

- [x] Cloned `magenta-realtime` with submodules into `magenta-realtime/`
- [x] Created `.venv` (Python 3.12) + installed `magenta-rt[mlx]` and `cmake<3.28`
- [x] Downloaded models to `~/.cache/magenta-rt-v2` (avoids TCC-protected `~/Documents`):
  - `mrt models init --download-path ~/.cache/magenta-rt-v2` → MusicCoCa + SpectroStream
  - `mrt models download mrt2_small --download-path ~/.cache/magenta-rt-v2`
- [x] Python MLX generation works: `MAGENTA_HOME=~/.cache mrt mlx generate --prompt "disco funk with slap bass" --duration 4.0 --model=mrt2_small` → 4s WAV in 1.4s (72.5 steps/s, well above 25 real-time threshold)
- [x] MusicCoCa audio embedding extraction works: returns 768-dim Float32 + 12 RVQ tokens
- [x] Inspected `mlx_engine.h` and `realtime_runner.h` — API surface mapped

## Phase 1 — Scaffold (DONE, build pending)

All source files written and renamed to Aevum. Build integration ready.

### File layout

```
/Users/stella/Desktop/projects/xformer/       (root — could be renamed to Aevum later)
├── AGENTS.md                                  — build/lint/test commands for agents
├── README.md                                  — project overview + setup
├── STATUS.md                                  — this file
├── build.sh                                   — top-level orchestrator (engine|app|run|clean)
├── project.yml                                — XcodeGen config (target: Aevum, bundle com.aevum.app)
├── scripts/
│   └── build_engine.sh                        — CMake build + merge into libaevum_engine.a
├── magenta-realtime/                          — submodule (upstream repo, Apache-2.0)
├── .venv/                                     — Python 3.12 venv (magenta-rt[mlx], cmake<3.28)
└── Aevum/
    ├── Resources/                             — (empty; will hold bundled models for release)
    └── Sources/
        ├── AevumApp/
        │   ├── AevumApp.swift                  — @main app entry, loads engine on startup
        │   ├── Aevum-Bridging-Header.h         — exposes EngineBridge.h to Swift
        │   ├── Info.plist                      — bundle metadata + usage strings
        │   └── Aevum.entitlements              — sandbox off, audio input, file access
        ├── Engine/
        │   ├── EngineBridge.h                  — Obj-C facade (pure Obj-C public API)
        │   ├── EngineBridge.mm                 — Obj-C++ impl wrapping RealtimeRunner
        │   ├── AudioEngine.swift               — AVAudioSourceNode pulls from bridge
        │   ├── MIDIManager.swift               — CoreMIDI in + CC→param maps (MIDI-learnable)
        │   └── EngineController.swift          — @MainActor orchestrator ObservableObject
        ├── Models/
        │   └── Models.swift                    — Song, Loop, Session, Setlist, MIDIMap
        ├── Storage/
        │   └── LibraryStore.swift              — SQLite (system libsqlite3, no external dep)
        ├── Import/
        │   ├── AudioDecoder.swift              — AVAssetReader → Float32 48k stereo
        │   ├── BeatTracker.swift               — native vDSP spectral-flux + autocorr BPM
        │   ├── LoopExtractor.swift             — slices 2/4/8-bar candidates at downbeats
        │   └── EmbeddingExtractor.swift        — batch MusicCoCa embeds via bridge slot 0
        ├── Similarity/
        │   ├── SimilarityEngine.swift          — cosine sim via Accelerate vDSP
        │   └── SetlistSuggester.swift          — smooth/contrast/cluster modes
        └── UI/
            ├── Theme.swift                     — Aevum design system (colors, type, controls)
            ├── ContentView.swift               — 3-pane layout + transport bar
            ├── ClipGridView.swift              — Ableton-style clip/scene grid
            ├── PromptSurfacePad.swift          — 2D XY morph pad (hero control)
            ├── ParamPanel.swift                — all MRT2 params, MIDI-learnable
            ├── SetlistView.swift               — similarity-ordered setlist + 3 modes
            ├── LibrarySidebar.swift            — songs list
            ├── ImportWizard.swift              — drag-and-drop song import
            └── WaveformView.swift              — Canvas waveform with loop markers
```

### Architecture decisions

- **Swift ↔ C++ bridge:** Obj-C++ `EngineBridge.mm` wraps `magentart::core::RealtimeRunner`. Public API is pure Obj-C so Swift imports it via the bridging header. This is the proven pattern from Magenta's `collider` example.
- **Engine integration:** Build `magenta-realtime` via CMake → merge all static libs (MLX, TFLite, SentencePiece, magentart_core) into one `libaevum_engine.a` via `libtool -static` → link from Xcode. Copy `mlx.metallib` into the app bundle's `Contents/MacOS/`.
- **Storage:** SQLite via system `libsqlite3` (no external dependency). Embeddings stored as Float32 BLOBs (768 × 4 = 3072 bytes per loop).
- **Audio:** `AVAudioEngine` + custom `AVAudioSourceNode` pulling 48k/2ch Float32 from `bridge.readAudioStereo` on the audio thread.
- **MIDI:** CoreMIDI input port + virtual destination. CC→param map is MIDI-learnable; default map covers CC1-5 + sustain + 3 blend slots.
- **Beat tracking:** Native vDSP spectral-flux onsets + autocorrelation BPM + downbeat heuristic. Good for 4/4 electronic. Optional Python `madmom` helper deferred to v2 if needed.

### UI design system (Aevum)

- **Palette:** `bgDeep #060709` / `bg #0A0B0E` / `panel #13151A` / `panelRaised #1C1F26`; text in 3 weights (`#E8E9ED` / `#8B8E96` / `#5A5D65`); signature **amber `#FFB547` → cyan `#3DD9EB`** blend axis (the visual metaphor for morphing); danger `#FF5E6C`, good `#4ADE80`.
- **Type:** SF Pro rounded for headings/big numbers, monospaced for BPM/time/metrics, uppercase tracked captions for section labels.
- **Spacing/radii:** 4/8/12/16/24 grid; 6/10/14 radii.
- **Motion:** spring (response 0.28, damping 0.78) for clip launch; breathing glow (1.8s easeInOut repeatForever) for the prompt-surface cursor.
- **Reusable:** `.glass()` modifier, `AevumSlider` (gradient fill + glowing thumb), `AevumToggle` (pill switch), `AevumPillButton`.
- **Hero control:** Prompt surface pad — radial-gradient field, faint grid + center crosshair, slot dots that grow and glow with their blend weight, cursor in blend-axis color with breathing ring.
- **Clip cells:** inner gradient + top sheen highlight, glow ∝ blend weight, active pulse dot, spring scale on launch.

## Blocker history

### Blocker 1 — Metal Toolchain (RESOLVED)

The C++ engine build failed with `error: cannot execute tool 'metal' due to missing Metal Toolchain`. Root cause: Xcode 26.5 ships the Metal Toolchain as a separate cryptex component that requires a reboot before `xcrun` can find it. Resolution:
1. ✅ `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
2. ✅ `sudo xcodebuild -license accept`
3. ✅ `sudo xcodebuild -runFirstLaunch`
4. ✅ `sudo xcodebuild -downloadComponent MetalToolchain`
5. ✅ Reboot → `xcrun metal --version` returns `Apple metal version 32023.883`

### Blocker 2 — Missing symbols at link (RESOLVED)

First app build failed at link with ~300 undefined TFLite + MLX symbols. Root cause: `scripts/build_engine.sh` used `ar -x` to extract `.o` files from each `.a` archive, then re-merged them with `libtool -static`. Some archives (notably `libtensorflow-lite.a`) contain multiple object files with the same filename (e.g., two `common.cc.o` members). `ar -x` silently overwrites the first with the second, dropping symbols like `_TfLiteDelegateCreate`.

**Fix:** Changed `build_engine.sh` to merge `.a` files directly with `libtool -static` instead of extracting + re-merging `.o` files. This preserves all members even when filenames collide within an archive.

## Current build state

Both engine and app build successfully:

```sh
./build.sh engine   # → build/engine/libaevum_engine.a (46 MB, 576 objects)
./build.sh app      # → DerivedData/.../Debug/Aevum.app (build succeeds)
```

### Remaining warnings (cosmetic, no errors)

- 4 Swift warnings: unused variables (`beatSec`, `duration`, `outputFormat`), unused `withUnsafeMutableBufferPointer` result, deprecated `onChange(of:perform:)` (use two-parameter variant on macOS 14+).
- `Copy Metallib` script phase warning: no declared outputs (harmless, runs every build).
- ld: `-lc++` linked twice; missing `CoreAudioTypes` auto-link (non-fatal).

## Phased roadmap (remaining)

| Phase | Scope | Est. |
|---|---|---|
| 1 | Scaffold, engine build, app build (DONE) | — |
| 2 | Import pipeline test on real audio | 5–7 days |
| 3 | Clip grid interaction polish + scene launching | 4–6 days |
| 4 | Prompt surface morphing + optional PCA basis | 4–5 days |
| 5 | MIDI learn UI + param automation per scene | 3–4 days |
| 6 | Setlist suggestion validation + auto-advance | 3–4 days |
| 7 | Session save/load, performance recording, notarization | 3–4 days |

## Key paths at runtime (dev)

- **Models:** `~/.cache/magenta-rt-v2/models/mrt2_small/mrt2_small.mlxfn`
- **Resources:** `~/.cache/magenta-rt-v2/resources` (MusicCoCa TFLite + SpectroStream)
- **SpectroStream encoder:** `~/.cache/magenta-rt-v2/resources/spectrostream/spectrostream_encoder.mlxfn`
- **Library DB:** `~/Library/Application Support/Aevum/library.sqlite`

These are hardcoded in `Aevum/Sources/AevumApp/AevumApp.swift` for dev. Release builds should bundle assets in `.app/Contents/Resources/` and switch the paths.

## Known gotchas

- `~/Documents/Magenta/` is TCC-protected on a fresh terminal → use `~/.cache` + `MAGENTA_HOME` env var.
- The Python venv's `bin/` scripts have hardcoded shebang paths to the venv location. If the root folder `xformer/` is renamed to `Aevum/`, the venv breaks — re-run `uv venv --python 3.12 .venv` and `uv pip install ...`.
- `magenta-realtime/` and `.venv/` contain unrelated `xformer` references (MLX internal variable names like `mlx_xformer`) — those are NOT project-name references and must not be touched.
- MLX needs `mlx.metallib` next to the executable at runtime; the postBuildScript in `project.yml` copies it.
- `RealtimeRunner::prefill_state` trims ~1s from each end of the audio automatically (SpectroStream encoder edges are unreliable) — the bridge's `prefillStateWithSamples:` does NOT pass trim args.
- `build_engine.sh` used `ar -x` + re-merge for the static lib, but `libtensorflow-lite.a` has duplicate `.o` filenames (e.g., two `common.cc.o`). The fix: merge `.a` files directly with `libtool -static`. If adding new static lib dependencies, do NOT go back to the extract-then-merge pattern.
