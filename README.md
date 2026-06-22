# Aevum

A macOS app for live AI music performance built on [Magenta RealTime 2](https://magenta.withgoogle.com/magenta-realtime-2). Load songs, auto-extract musical loops, morph between them in real time, and control every generation parameter live with a MIDI controller.

> **Status:** scaffolding in progress. Requires Xcode.app (for the Metal compiler). See `AGENTS.md` for the current blocker.

## What it does

1. **Import songs** → drag in WAV/MP3/FLAC/M4A files.
2. **Auto-extract loops** → beat-track each song, slice 2/4/8-bar candidates at downbeat boundaries, embed each with MusicCoCa, dedupe by similarity, rank by novelty × energy.
3. **Morph in real time** → the Ableton-style clip grid launches loops into 6 blend slots. A 2D prompt-surface pad morphs between them via inverse-distance-weighted blending — Magenta generates the crossfade continuously.
4. **Absolute live control** → every MRT2 parameter (CFG per modality, temperature, top-k, masking width, drumless, onset mode, MIDI gate) is exposed and MIDI-learnable. Play notes via a MIDI controller to steer pitch in real time.
5. **Setlist suggestions** → cosine similarity over 768-dim MusicCoCa embeddings. Three modes: *smooth* (greedy nearest-neighbor walk), *contrast* (max dissimilarity for dramatic morphs), *cluster* (hierarchical grouping into runs).

## Architecture

```
Aevum.app (SwiftUI · macOS 14+ · Apple Silicon)
├── SwiftUI Layer
│   ├── ClipGridView        — Ableton-style clip/scene grid
│   ├── PromptSurfacePad    — 2D XY morph pad (IDW blend weights)
│   ├── ParamPanel          — CFG/mask/temp/top-k/drumless/onset
│   ├── SetlistView         — similarity-ordered setlist
│   ├── ImportWizard        — drop songs → loops
│   └── LibrarySidebar      — songs, loops, sessions
├── Audio/MIDI Layer
│   ├── AVAudioEngine + AVAudioSourceNode  — pulls from bridge.readAudio
│   └── CoreMIDI Manager                   — notes + CC → bridge setters
├── EngineBridge (Obj-C++ wrapper, Swift-facing)
│   └── owns magentart::core::RealtimeRunner
├── magentart::core  (C++ static lib, pulled from GitHub)
│   ├── RealtimeRunner  (inference thread, ring buffers, prompt blending,
│   │   MIDI gate, prefill, recording, save/load state)
│   └── MLXEngine + MusicCoCa TFLite assets (embeddings for similarity)
├── ImportPipeline (background queue)
│   └── decode → beat-track → slice 2/4/8-bar → MusicCoCa embed → rank
└── LoopLibrary (SQLite in App Support: songs, loops, embeddings, sessions)
```

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

The `~/Documents/Magenta/` default download path is TCC-protected on a
fresh macOS terminal; `~/.cache` avoids the permission prompt.

## Build & run

```sh
./build.sh          # build engine + app
./build.sh run      # build + launch
```

The first `./build.sh engine` takes 10–20 minutes (MLX + TFLite +
SentencePiece from source). Subsequent runs are incremental.

## Hardware

- **`mrt2_small`** (230M params) — real-time on any Apple Silicon Mac.
- **`mrt2_base`** (2.4B params) — requires M2 Max / M3 Pro / M4 Pro or higher for real-time; higher quality.

The app uses `mrt2_small` by default. To switch to `mrt2_base`, download
it (`mrt models download mrt2_base`) and change `modelPath` in
`Sources/AevumApp/AevumApp.swift`.

## License

Source code in this repository: see `LICENSE` (to be added). The bundled
`magenta-realtime` submodule is Apache-2.0. Model weights are released by
Google under their own license (see
[HuggingFace](https://huggingface.co/google/magenta-realtime-2)).
