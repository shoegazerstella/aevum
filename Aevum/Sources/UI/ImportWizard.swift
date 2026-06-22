// ImportWizard.swift — Drag-and-drop song import, Aevum-styled.

import SwiftUI
import UniformTypeIdentifiers

struct ImportWizard: View {
    @EnvironmentObject var controller: EngineController
    @State private var isImporting = false
    @State private var logLines: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Import Songs").font(AevumFont.title).foregroundStyle(AevumColors.text)
                Text("Beat-track · slice · MusicCoCa-embed")
                    .font(AevumFont.caption).foregroundStyle(AevumColors.textFaint)
            }
            .padding(.top, AevumSpacing.l)
            .padding(.bottom, AevumSpacing.m)

            DropZone { urls in Task { await runImport(urls) } }
                .padding(.horizontal, AevumSpacing.l)

            if !logLines.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(logLines.indices, id: \.self) { i in
                            Text(logLines[i])
                                .font(AevumFont.mono)
                                .foregroundStyle(AevumColors.textDim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(AevumSpacing.s)
                }
                .background(RoundedRectangle(cornerRadius: AevumRadius.small).fill(AevumColors.bgDeep))
                .padding(AevumSpacing.l)
            }

            HStack {
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .font(AevumFont.body)
                    .foregroundStyle(AevumColors.textDim)
                Spacer()
                if isImporting {
                    ProgressView().scaleEffect(0.6).tint(AevumColors.amber)
                    Text("Importing…").font(AevumFont.caption).foregroundStyle(AevumColors.textDim)
                }
            }
            .padding(AevumSpacing.l)
        }
        .background(AevumColors.panel)
        .frame(width: 600, height: 520)
    }

    private func runImport(_ urls: [URL]) async {
        isImporting = true
        logLines.append("→ \(urls.count) song(s)")
        for url in urls {
            logLines.append("· \(url.lastPathComponent)")
            await controller.importSong(at: url)
            switch controller.importProgress {
            case .done:          logLines.append("  ✓ done")
            case .failed(let m): logLines.append("  ✗ \(m)")
            default: break
            }
        }
        isImporting = false
        logLines.append("— complete —")
    }
}

private struct DropZone: View {
    let onDrop: ([URL]) -> Void
    @State private var isHovering = false
    var body: some View {
        VStack(spacing: AevumSpacing.s) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(isHovering ? AevumColors.amber : AevumColors.textFaint)
                .scaleEffect(isHovering ? 1.08 : 1.0)
                .animation(AevumMotion.snappy, value: isHovering)
            Text("Drop audio files here").font(AevumFont.headline).foregroundStyle(AevumColors.text)
            Text("WAV · MP3 · AAC · FLAC · M4A")
                .font(AevumFont.caption).foregroundStyle(AevumColors.textFaint)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: AevumRadius.large)
                .fill(AevumColors.bgDeep)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AevumRadius.large)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                .foregroundStyle(isHovering ? AevumColors.amber.opacity(0.7) : AevumColors.dividerStrong)
        )
        .onDrop(of: [.fileURL], isTargeted: $isHovering) { providers in
            var collected: [URL] = []
            let lock = NSLock()
            let group = DispatchGroup()
            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { lock.lock(); collected.append(url); lock.unlock() }
                    group.leave()
                }
            }
            group.notify(queue: .main) { onDrop(collected) }
            return true
        }
    }
}
