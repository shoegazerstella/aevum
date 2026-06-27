// ContentView.swift — Main window: sidebar + clip grid + controls.
// Dark "studio instrument" aesthetic per Aevum design system.
//
// Two layouts: standard (sidebar · clip grid · prompt surface + params)
// and focused (in-window performance mode: hides sidebar + param panel,
// enlarges the prompt surface, keeps macros + transport + waveform).
// Toggled with ⌘F or the focus button in the transport bar.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var controller: EngineController
    @State private var selectedSongId: Int64?
    @State private var showingImporter = false
    @State private var selectedTab: SidebarTab = .library

    enum SidebarTab: String, CaseIterable, Identifiable {
        case library = "Library"
        case setlist = "Setlist"
        case sessions = "Sessions"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .library:  return "square.stack.3d.up"
            case .setlist:  return "arrow.right.circle"
            case .sessions: return "tray.full"
            }
        }
    }

    var body: some View {
        ZStack {
            if controller.isFocused {
                FocusedLayout(selectedSongId: $selectedSongId)
            } else {
                StandardLayout(selectedSongId: $selectedSongId,
                               selectedTab: $selectedTab,
                               showingImporter: $showingImporter)
            }

            if !controller.isEngineLoaded {
                LoadingOverlay()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                MetricsView(metrics: controller.metrics)
            }
        }
        .toolbarBackground(AevumColors.panel, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .sheet(isPresented: $showingImporter) { ImportWizard() }
        .onReceive(NotificationCenter.default.publisher(for: .importSongs)) { _ in showingImporter = true }
        .onReceive(NotificationCenter.default.publisher(for: .togglePlay)) { _ in controller.togglePlay() }
        .onReceive(NotificationCenter.default.publisher(for: .triggerReset)) { _ in controller.triggerReset() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFocused)) { _ in controller.toggleFocused() }
        .onAppear { if controller.songs.isEmpty { showingImporter = true } }
        .focusable()
        .onKeyPress(.init("1")) { recallScene(0); return .handled }
        .onKeyPress(.init("2")) { recallScene(1); return .handled }
        .onKeyPress(.init("3")) { recallScene(2); return .handled }
        .onKeyPress(.init("4")) { recallScene(3); return .handled }
        .onKeyPress(.init("5")) { recallScene(4); return .handled }
        .onKeyPress(.init("6")) { recallScene(5); return .handled }
        .onKeyPress(.init("7")) { recallScene(6); return .handled }
        .onKeyPress(.init("8")) { recallScene(7); return .handled }
        .onKeyPress(.init("9")) { recallScene(8); return .handled }
        .onKeyPress(.tab) { controller.cycleSlot(); return .handled }
        .onKeyPress(.upArrow) { controller.nudgeCursor(dx: 0, dy: -0.04); return .handled }
        .onKeyPress(.downArrow) { controller.nudgeCursor(dx: 0, dy: 0.04); return .handled }
        .onKeyPress(.leftArrow) { controller.nudgeCursor(dx: -0.04, dy: 0); return .handled }
        .onKeyPress(.rightArrow) { controller.nudgeCursor(dx: 0.04, dy: 0); return .handled }
    }

    private func recallScene(_ index: Int) {
        guard index < controller.scenes.count else { return }
        controller.recallScene(controller.scenes[index])
    }
}

// MARK: - Standard layout (sidebar · grid · prompt surface + params)

private struct StandardLayout: View {
    @EnvironmentObject var controller: EngineController
    @Binding var selectedSongId: Int64?
    @Binding var selectedTab: ContentView.SidebarTab
    @Binding var showingImporter: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar
            VStack(spacing: 0) {
                SidebarTabs(selected: $selectedTab)
                    .padding(AevumSpacing.s)
                switch selectedTab {
                case .library:
                    LibrarySidebar(selectedSongId: $selectedSongId)
                case .setlist:
                    SetlistView()
                case .sessions:
                    VStack {
                        Spacer()
                        Text("Sessions").font(AevumFont.body).foregroundStyle(AevumColors.textFaint)
                        Spacer()
                    }
                }
            }
            .frame(width: 280)
            .background(AevumColors.panel)
            .overlay(Divider().overlay(AevumColors.divider), alignment: .trailing)

            // Center: clip grid + transport
            VStack(spacing: 0) {
                TransportBar()
                Divider().overlay(AevumColors.divider)
                ClipGridView(selectedSongId: selectedSongId)
            }
            .background(AevumColors.bg)

            // Right: macros + prompt surface + params
            VStack(spacing: 0) {
                MacroKnobs()
                    .padding(AevumSpacing.m)
                PromptSurfacePad()
                    .frame(maxHeight: .infinity)
                Divider().overlay(AevumColors.divider)
                ParamPanel()
            }
            .frame(width: 360)
            .background(AevumColors.panel)
            .overlay(Divider().overlay(AevumColors.divider), alignment: .leading)
        }
        .background(AevumColors.bgDeep)
    }
}

// MARK: - Focused (performance) layout

private struct FocusedLayout: View {
    @EnvironmentObject var controller: EngineController
    @Binding var selectedSongId: Int64?

    var body: some View {
        VStack(spacing: 0) {
            TransportBar()
            Divider().overlay(AevumColors.divider)
            HStack(spacing: 0) {
                // Compact clip grid (no scene strip) — for quick launches
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(controller.songs) { song in
                            SongRowCompact(song: song,
                                           loops: controller.loops.filter { $0.songId == song.id })
                            Divider().overlay(AevumColors.divider)
                        }
                    }
                    .padding(AevumSpacing.s)
                }
                .frame(maxWidth: 360)
                .background(AevumColors.bg)

                // Hero: macros + big prompt surface + waveform
                VStack(spacing: AevumSpacing.m) {
                    MacroKnobs()
                        .padding(.horizontal, AevumSpacing.l)
                        .padding(.top, AevumSpacing.m)
                    PromptSurfacePad()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    LiveWaveformView(height: 60)
                        .padding(.horizontal, AevumSpacing.l)
                        .padding(.bottom, AevumSpacing.m)
                }
                .frame(maxWidth: .infinity)
                .background(AevumColors.panel)
            }
        }
        .background(AevumColors.bgDeep)
    }
}

private struct SongRowCompact: View {
    let song: Song
    let loops: [Loop]
    @EnvironmentObject var controller: EngineController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.name)
                .font(AevumFont.body)
                .foregroundStyle(AevumColors.text)
                .lineLimit(1)
                .padding(.horizontal, AevumSpacing.s)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AevumSpacing.xs) {
                    ForEach(loops) { loop in
                        CompactClipCell(loop: loop)
                            .onTapGesture(count: 2) { controller.toggleLoopInBlend(loop) }
                            .onTapGesture { controller.previewLoop(loop) }
                    }
                }
                .padding(.horizontal, AevumSpacing.s)
                .padding(.bottom, AevumSpacing.s)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CompactClipCell: View {
    let loop: Loop
    @EnvironmentObject var controller: EngineController
    private var loadedSlot: Int? {
        guard let id = loop.id else { return nil }
        return controller.slot(forLoop: id)
    }
    private var isActive: Bool {
        (loadedSlot.map { controller.blendWeights[$0] } ?? 0) > 0.01
    }
    private var isPreviewing: Bool { controller.previewingLoopId == loop.id }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(loop.bars)b")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(isActive ? 0.95 : 0.7))
            if let slot = loadedSlot {
                Text("S\(slot)")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(isActive ? AevumColors.amber : AevumColors.textFaint)
            }
        }
        .frame(width: 52, height: 32)
        .background(
            ZStack {
                // Base — per-clip color so loops stay distinguishable.
                RoundedRectangle(cornerRadius: AevumRadius.small)
                    .fill(Color(hexString: loop.color)?.opacity(0.7) ?? .gray.opacity(0.7))
                // Active overlay — amber→cyan 135° gradient (matches website .clip.on).
                RoundedRectangle(cornerRadius: AevumRadius.small)
                    .fill(
                        LinearGradient(
                            colors: [AevumColors.amber.opacity(0.30), AevumColors.cyan.opacity(0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .opacity(isActive ? 1 : 0)
            }
        )
        .overlay(
            // Border — amber when active, faint divider otherwise.
            RoundedRectangle(cornerRadius: AevumRadius.small)
                .strokeBorder(isActive ? AevumColors.amber.opacity(0.5) : AevumColors.divider,
                              lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            // Top-right amber glowing dot — the canonical "on" marker.
            Circle()
                .fill(AevumColors.amber)
                .frame(width: 4, height: 4)
                .shadow(color: AevumColors.amber.opacity(0.9), radius: 2)
                .opacity(isActive ? 1 : 0)
                .padding(3)
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: AevumRadius.small)
                .strokeBorder(AevumColors.cyan, lineWidth: 1.5)
                .opacity(isPreviewing ? 1 : 0)
        )
        .shadow(color: isActive ? AevumColors.amber.opacity(0.5) : .clear, radius: 8)
        .scaleEffect(isActive ? 1.02 : 0.98)
        .animation(AevumMotion.snappy, value: isActive)
        .help("Click to preview · double-click to add to blend")
    }
}

// MARK: - Sidebar tab switch

private struct SidebarTabs: View {
    @Binding var selected: ContentView.SidebarTab
    var body: some View {
        HStack(spacing: 2) {
            ForEach(ContentView.SidebarTab.allCases) { tab in
                let isOn = selected == tab
                Button(action: { selected = tab }) {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage).font(.system(size: 13, weight: .medium))
                        Text(tab.rawValue).font(AevumFont.micro)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(isOn ? AevumColors.amber : AevumColors.textFaint)
                    .background(
                        RoundedRectangle(cornerRadius: AevumRadius.small)
                            .fill(isOn ? AevumColors.amber.opacity(0.12) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Transport bar

private struct TransportBar: View {
    @EnvironmentObject var controller: EngineController
    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: AevumSpacing.m) {
            // Play / stop — large, glowing when playing. Pulsing ring
            // while active makes the play state unmistakable on stage.
            playButton

            CircleButton(systemImage: "arrow.clockwise") { controller.triggerReset() }
                .help("Reset engine (R)")

            // Record button
            recordButton
                .help("Record live output to ~/Music/Aevum (⌘R disabled — use button)")

            Divider().frame(height: 22).overlay(AevumColors.divider)

            // Live output waveform — the visual heartbeat during a set.
            LiveWaveformView(height: 36, showsLabel: false)
                .frame(maxWidth: 260)

            Divider().frame(height: 22).overlay(AevumColors.divider)

            importStatus
            migrationStatus
            styleStatus

            Spacer()

            // Focused-mode toggle
            Button {
                controller.toggleFocused()
            } label: {
                Label(controller.isFocused ? "Exit Focus" : "Focus",
                      systemImage: controller.isFocused ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    .font(AevumFont.caption)
                    .foregroundStyle(controller.isFocused ? AevumColors.amber : AevumColors.textDim)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        Capsule().fill(controller.isFocused ? AevumColors.amber.opacity(0.15) : AevumColors.panelRaised)
                    )
            }
            .buttonStyle(.plain)
            .help("Focused performance mode (⌘F)")

            statsLabel
        }
        .padding(.horizontal, AevumSpacing.l)
        .frame(height: 56)
        .background(AevumColors.panel)
    }

    private var playButton: some View {
        Button(action: controller.togglePlay) {
            ZStack {
                // Pulsing ring while playing
                if controller.isPlaying {
                    Circle()
                        .strokeBorder(AevumColors.danger.opacity(0.4), lineWidth: 2)
                        .frame(width: 42, height: 42)
                        .scaleEffect(pulse ? 1.15 : 0.9)
                        .opacity(pulse ? 0.0 : 0.7)
                }
                Image(systemName: controller.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(controller.isPlaying ? AevumColors.danger : AevumColors.amber)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(AevumColors.panelRaised)
                            .overlay(Circle().strokeBorder(controller.isPlaying
                                ? AevumColors.danger.opacity(0.5) : AevumColors.amber.opacity(0.4), lineWidth: 1.5))
                    )
                    .shadow(color: controller.isPlaying ? AevumColors.danger.opacity(0.5) : AevumColors.amber.opacity(0.4),
                            radius: 10)
                    .opacity(controller.isPrefilling ? 0.4 : 1)
            }
            .onAppear { withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) { pulse = true } }
        }
        .buttonStyle(.plain)
        .disabled(controller.isPrefilling)
        .help("Play / Stop (Space)")
    }

    private var recordButton: some View {
        Button(action: controller.toggleRecording) {
            HStack(spacing: 5) {
                Circle()
                    .fill(controller.isRecording ? AevumColors.danger : AevumColors.danger.opacity(0.7))
                    .frame(width: 9, height: 9)
                    .shadow(color: AevumColors.danger.opacity(controller.isRecording ? 0.9 : 0.3), radius: 5)
                    .scaleEffect(controller.isRecording ? (pulse ? 1.2 : 0.85) : 1.0)
                Text(controller.isRecording ? "Stop" : "Rec")
                    .font(AevumFont.caption)
                    .foregroundStyle(AevumColors.danger)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                Capsule().fill(AevumColors.danger.opacity(controller.isRecording ? 0.18 : 0.08))
            )
            .overlay(Capsule().strokeBorder(AevumColors.danger.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var importStatus: some View {
        if controller.isPrefilling {
            PrefillBadge(log: controller.prefillLog.last ?? "Prefilling…")
        } else {
            switch controller.importProgress {
            case .decoding(let name, let p):
                ImportBadge(label: "Decoding \(name)", progress: p)
            case .extractingEmbeddings(let name, let done, let total):
                ImportBadge(label: "Embedding \(name)",
                            progress: total > 0 ? Double(done) / Double(total) : 0)
            case .beatTracking(let name):  ImportBadge(label: "Beats \(name)", progress: nil)
            case .slicing(let name):       ImportBadge(label: "Slicing \(name)", progress: nil)
            case .done, .idle, .failed:    EmptyView()
            }
        }
    }

    @ViewBuilder private var migrationStatus: some View {
        if controller.isMigratingEmbeddings {
            let total = controller.embeddingMigrationTotal
            let done = controller.embeddingMigrationDone
            ImportBadge(label: "Re-extracting embeddings",
                        progress: total > 0 ? Double(done) / Double(total) : 0)
                .help("One-time fix: re-computing clip style embeddings with the correct 16 kHz mono format so morphing reflects your clips.")
        }
        if let err = controller.recordingError {
            Badge(systemImage: "exclamationmark.triangle.fill", text: "Rec", color: AevumColors.danger)
                .help(err)
        }
        if let url = controller.lastRecordingURL {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Badge(systemImage: "checkmark.circle.fill", text: "Saved", color: AevumColors.good)
            }
            .buttonStyle(.plain)
            .help("Show recording in Finder: \(url.path)")
        }
    }

    @ViewBuilder private var styleStatus: some View {
        let color: Color = controller.styleSteeringActive ? AevumColors.amber
            : controller.styleStatusLabel.contains("fallback") ? AevumColors.danger
            : AevumColors.textFaint
        Badge(systemImage: controller.styleSteeringActive ? "waveform" : "music.note",
              text: controller.styleStatusLabel,
              color: color)
            .help("Style steering — shows which clip(s) are driving generation. 'fallback' means a slot has no valid embedding; re-extract.")
    }

    private var statsLabel: some View {
        Text("\(controller.songs.count) songs · \(controller.loops.count) loops")
            .font(AevumFont.mono)
            .foregroundStyle(AevumColors.textFaint)
    }
}

private struct CircleButton: View {
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AevumColors.textDim)
                .frame(width: 28, height: 28)
                .background(Circle().fill(AevumColors.panelRaised))
        }
        .buttonStyle(.plain)
    }
}

private struct ImportBadge: View {
    let label: String
    let progress: Double?
    var body: some View {
        HStack(spacing: AevumSpacing.s) {
            if let p = progress {
                ProgressView(value: p).tint(AevumColors.amber).frame(width: 80)
            } else {
                ProgressView().scaleEffect(0.55).frame(width: 20)
            }
            Text(label).font(AevumFont.caption).foregroundStyle(AevumColors.textDim)
        }
    }
}

// MARK: - Metrics (toolbar, top-right)

private struct MetricsView: View {
    let metrics: XFEngineMetrics
    var body: some View {
        HStack(spacing: AevumSpacing.s) {
            Badge(systemImage: "speedometer",
                  text: String(format: "%.1fms", metrics.totalMs),
                  color: metrics.totalMs > 40 ? AevumColors.danger
                       : metrics.totalMs > 30 ? AevumColors.amber : AevumColors.good)
            if metrics.droppedFrames > 0 {
                Badge(systemImage: "exclamationmark.triangle.fill",
                      text: "\(metrics.droppedFrames)", color: AevumColors.danger)
            }
        }
    }
}

private struct Badge: View {
    let systemImage: String
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 9))
            Text(text).font(AevumFont.mono)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
    }
}

private struct PrefillBadge: View {
    let log: String
    var body: some View {
        HStack(spacing: AevumSpacing.s) {
            ProgressView().scaleEffect(0.55).frame(width: 20)
            Text(log).font(AevumFont.caption).foregroundStyle(AevumColors.cyan).lineLimit(1)
        }
        .help("Prefilling engine with clip audio — generation will continue from the clip's end")
    }
}

// MARK: - Loading overlay

private struct LoadingOverlay: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            AevumColors.bgDeep.opacity(0.92)
                .ignoresSafeArea()
            VStack(spacing: AevumSpacing.m) {
                ZStack {
                    Circle()
                        .strokeBorder(AevumColors.amber.opacity(0.2), lineWidth: 2)
                        .frame(width: 48, height: 48)
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(AevumColors.amber, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(pulse ? 360 : 0))
                        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: pulse)
                }
                Text("Loading engine…")
                    .font(AevumFont.headline)
                    .foregroundStyle(AevumColors.text)
                Text("Loading MRT2 model + MusicCoCa + SpectroStream")
                    .font(AevumFont.caption)
                    .foregroundStyle(AevumColors.textFaint)
            }
        }
        .onAppear { pulse = true }
    }
}
