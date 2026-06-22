// ClipGridView.swift — Ableton-style clip/scene grid, Aevum-styled.
// Rows = source songs; cells = loops. Click launches into a blend slot.
// Cell brightness/glow ∝ its current blend weight.

import SwiftUI

struct ClipGridView: View {
    @EnvironmentObject var controller: EngineController
    var selectedSongId: Int64?
    @State private var selectedSlots: Set<Int> = []
    @State private var sceneNamePopup = false
    @State private var newSceneName = ""

    private var displayedSongs: [Song] {
        if let sid = selectedSongId {
            return controller.songs.filter { $0.id == sid }
        }
        return controller.songs
    }

    var body: some View {
        HStack(spacing: 0) {
            // Scene strip — like Ableton's session view scene launch column
            SceneStrip()

            Divider().overlay(AevumColors.divider)

            // Song / clip grid
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    if controller.songs.isEmpty {
                        emptyState
                    } else if displayedSongs.isEmpty && selectedSongId != nil {
                        // Selected a song but it has no loops yet — still show it
                        // so the user can see what they picked.
                        VStack(spacing: AevumSpacing.m) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(AevumColors.textFaint)
                            Text("No loops extracted yet")
                                .font(AevumFont.headline).foregroundStyle(AevumColors.textDim)
                            Text("Loops appear here after import completes.")
                                .font(AevumFont.caption).foregroundStyle(AevumColors.textFaint)
                        }
                        .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        ForEach(Array(displayedSongs.enumerated()), id: \.element.id) { idx, song in
                            SongRow(song: song,
                                    loops: controller.loops.filter { $0.songId == song.id },
                                    selectedSlots: $selectedSlots)
                            if idx < displayedSongs.count - 1 {
                                Divider().overlay(AevumColors.divider)
                            }
                        }
                    }
                }
                .padding(AevumSpacing.m)
            }
        }
        .background(AevumColors.bg)
    }

    private var emptyState: some View {
        VStack(spacing: AevumSpacing.m) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(AevumColors.textFaint)
            Text("No songs yet").font(AevumFont.headline).foregroundStyle(AevumColors.textDim)
            Text("Drop audio files into the importer to extract loops.")
                .font(AevumFont.caption).foregroundStyle(AevumColors.textFaint)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

// MARK: — Scene strip (left column)

private struct SceneStrip: View {
    @EnvironmentObject var controller: EngineController

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SCENES")
                    .font(AevumFont.caption)
                    .foregroundStyle(AevumColors.textFaint)
                Spacer()
                Button {
                    controller.captureScene(
                        name: "Scene \(controller.scenes.count + 1)",
                        slotPositions: controller.slotPositions,
                        cursorPosition: controller.cursorPosition)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AevumColors.textDim)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(AevumColors.panelRaised))
                }
                .buttonStyle(.plain)
                .help("Capture current slot arrangement as a new scene")
            }
            .padding(.horizontal, AevumSpacing.s)
            .padding(.vertical, 6)

            Divider().overlay(AevumColors.divider)

            if controller.scenes.isEmpty {
                VStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "rectangle.3.group").font(.system(size: 18))
                        .foregroundStyle(AevumColors.textFaint)
                    Text("No scenes")
                        .font(AevumFont.caption)
                        .foregroundStyle(AevumColors.textFaint)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(controller.scenes) { scene in
                            SceneRow(scene: scene)
                        }
                    }
                    .padding(AevumSpacing.xs)
                }
            }
        }
        .frame(width: 110)
        .background(AevumColors.panel)
    }
}

private struct SceneRow: View {
    let scene: Scene
    @EnvironmentObject var controller: EngineController

    var body: some View {
        VStack(spacing: 2) {
            Button {
                controller.recallScene(scene)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(AevumColors.amber)
                    Text(scene.name)
                        .font(AevumFont.micro)
                        .foregroundStyle(AevumColors.textDim)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: AevumRadius.small)
                        .fill(AevumColors.panelRaised.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AevumRadius.small)
                        .strokeBorder(AevumColors.divider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    controller.deleteScene(scene)
                } label: {
                    Label("Delete Scene", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: — Song row with clip cells + preview

private struct SongRow: View {
    let song: Song
    let loops: [Loop]
    @Binding var selectedSlots: Set<Int>
    @EnvironmentObject var controller: EngineController

    var body: some View {
        HStack(spacing: 0) {
            // Track header
            VStack(alignment: .leading, spacing: 3) {
                Text(song.name)
                    .font(AevumFont.body)
                    .foregroundStyle(AevumColors.text)
                    .lineLimit(1)
                HStack(spacing: AevumSpacing.s) {
                    Label(String(format: "%.0f", song.bpm), systemImage: "metronome")
                        .labelStyle(.titleAndIcon).font(AevumFont.mono).foregroundStyle(AevumColors.amber)
                    Text(String(format: "%.0fs", song.durationSec))
                        .font(AevumFont.mono).foregroundStyle(AevumColors.textFaint)
                }
            }
            .frame(width: 156, height: 70, alignment: .leading)
            .padding(.leading, AevumSpacing.s)

            // Clip cells — single-click = preview, double-click = blend
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AevumSpacing.xs) {
                    ForEach(loops) { loop in
                        ClipCell(loop: loop,
                                 isSelected: selectedSlots.contains(loadedSlot(for: loop)))
                            .onTapGesture(count: 2) { toggleSelect(loop) }
                            .onTapGesture { previewClip(loop) }
                    }
                }
                .padding(.trailing, AevumSpacing.s)
            }
        }
        .padding(.vertical, AevumSpacing.xs)
    }

    /// Slot this loop is currently loaded into, or -1 if not loaded.
    private func loadedSlot(for loop: Loop) -> Int {
        guard let id = loop.id else { return -1 }
        return controller.slot(forLoop: id) ?? -1
    }
    /// Single-click: preview the clip's raw audio. If already previewing
    /// this clip, stop the preview. The "Continue from here" button on
    /// the previewing cell triggers `continueFromLoop`.
    private func previewClip(_ loop: Loop) {
        controller.previewLoop(loop)
    }
    /// Double-click: add/remove the clip as a style prompt in a blend slot.
    private func toggleSelect(_ loop: Loop) {
        controller.toggleLoopInBlend(loop)
        selectedSlots = Set((0..<6).filter { controller.blendWeights[$0] > 0.01 })
    }
}

// MARK: — Clip cell

private struct ClipCell: View {
    let loop: Loop
    let isSelected: Bool
    @EnvironmentObject var controller: EngineController

    /// The slot this loop is currently loaded into, or nil if not loaded.
    private var loadedSlot: Int? {
        guard let id = loop.id else { return nil }
        return controller.slot(forLoop: id)
    }
    private var weight: Float {
        guard let slot = loadedSlot else { return 0 }
        return controller.blendWeights[slot]
    }
    private var isActive: Bool { weight > 0.01 }
    private var isPreviewing: Bool { controller.previewingLoopId == loop.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(loop.bars)b")
                    .font(AevumFont.monoBold)
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                // Slot badge — shows which slot (S0–S5) this clip is loaded into
                if let slot = loadedSlot {
                    Text("S\(slot)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(AevumColors.amber)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(AevumColors.amber.opacity(0.18)))
                        .overlay(Capsule().strokeBorder(AevumColors.amber.opacity(0.4), lineWidth: 0.5))
                }
                // Preview / playing indicator
                if isPreviewing {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(AevumColors.cyan)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(AevumColors.amber.opacity(0.7))
                }
                if isActive {
                    Circle().fill(.white).frame(width: 6, height: 6)
                        .shadow(color: .white.opacity(0.8), radius: 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text(loop.name)
                .font(AevumFont.micro)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            Spacer()
            // Energy bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15)).frame(height: 2)
                    Capsule()
                        .fill(.white.opacity(isActive ? 0.85 : 0.5))
                        .frame(width: geo.size.width * CGFloat(min(1, Float(loop.rating) / 5)), height: 2)
                }
            }.frame(height: 2)
        }
        .padding(AevumSpacing.s - 2)
        .frame(width: 96, height: 60)
        .background(
            RoundedRectangle(cornerRadius: AevumRadius.small)
                .fill(
                    LinearGradient(colors: [
                        Color(hexString: loop.color)?.opacity(0.85) ?? .gray.opacity(0.85),
                        (Color(hexString: loop.color) ?? .gray).opacity(0.65)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AevumRadius.small)
                .strokeBorder(.white.opacity(isActive ? 0.6 : 0.12), lineWidth: isActive ? 1.5 : 1)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: AevumRadius.small)
                .fill(
                    LinearGradient(colors: [.white.opacity(0.22), .clear],
                                   startPoint: .top, endPoint: .center)
                )
                .frame(height: 12)
                .mask(RoundedRectangle(cornerRadius: AevumRadius.small))
        }
        .shadow(color: isActive ? AevumColors.amber.opacity(Double(weight) * 0.6) : .clear,
                radius: isActive ? 10 : 0)
        .scaleEffect(isActive ? 1.0 : 0.98)
        .animation(AevumMotion.snappy, value: isActive)
        .overlay(
            RoundedRectangle(cornerRadius: AevumRadius.small)
                .strokeBorder(AevumColors.amber, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        )
        // Previewing state — cyan border + "Continue from here" button overlay
        .overlay(
            RoundedRectangle(cornerRadius: AevumRadius.small)
                .strokeBorder(AevumColors.cyan, lineWidth: 1.5)
                .opacity(isPreviewing ? 1 : 0)
        )
        .overlay(alignment: .bottom) {
            if isPreviewing {
                Button {
                    controller.continueFromLoop(loop)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 8, weight: .bold))
                        Text("Continue")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(AevumColors.cyan))
                    .shadow(color: AevumColors.cyan.opacity(0.6), radius: 4)
                }
                .buttonStyle(.plain)
                .help("Prefill the engine with this clip — generation continues from where the clip ends")
                .transition(.scale.combined(with: .opacity))
                .padding(.bottom, 3)
            }
        }
        .animation(AevumMotion.snappy, value: isPreviewing)
        .help("Click to preview · double-click to add to blend")
    }
}
