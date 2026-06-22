// ContentView.swift — Main window: sidebar + clip grid + controls.
// Dark "studio instrument" aesthetic per Aevum design system.

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

                // Right: prompt surface + params
                VStack(spacing: 0) {
                    PromptSurfacePad()
                        .frame(height: 300)
                    Divider().overlay(AevumColors.divider)
                    ParamPanel()
                }
                .frame(width: 340)
                .background(AevumColors.panel)
                .overlay(Divider().overlay(AevumColors.divider), alignment: .leading)
            }
            .background(AevumColors.bgDeep)

            // Loading overlay — shown until the engine finishes loading models
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
        .onAppear { if controller.songs.isEmpty { showingImporter = true } }
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
    var body: some View {
        HStack(spacing: AevumSpacing.m) {
            // Play / stop — large, glowing when playing. Disabled while
            // prefilling (the engine is being reseeded; starting playback
            // mid-prefill would corrupt generation).
            Button(action: controller.togglePlay) {
                Image(systemName: controller.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(controller.isPlaying ? AevumColors.danger : AevumColors.amber)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(AevumColors.panelRaised)
                            .overlay(Circle().strokeBorder(controller.isPlaying
                                ? AevumColors.danger.opacity(0.5) : AevumColors.amber.opacity(0.4), lineWidth: 1.5))
                    )
                    .shadow(color: controller.isPlaying ? AevumColors.danger.opacity(0.4) : AevumColors.amber.opacity(0.3),
                            radius: 8)
                    .opacity(controller.isPrefilling ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(controller.isPrefilling)
            .help("Play / Stop (Space)")

            CircleButton(systemImage: "arrow.clockwise") { controller.triggerReset() }
                .help("Reset engine (R)")

            Divider().frame(height: 22).overlay(AevumColors.divider)

            importStatus

            Spacer()

            statsLabel
        }
        .padding(.horizontal, AevumSpacing.l)
        .frame(height: 52)
        .background(AevumColors.panel)
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
            // Timing / RTF — the primary health indicator. Turns red when
            // a frame exceeds the 40ms real-time budget (underrun territory).
            Badge(systemImage: "speedometer",
                  text: String(format: "%.1fms", metrics.totalMs),
                  color: metrics.totalMs > 40 ? AevumColors.danger
                       : metrics.totalMs > 30 ? AevumColors.amber : AevumColors.good)
            // Dropped frames (underruns that already happened)
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
