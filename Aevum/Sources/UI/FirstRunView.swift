// FirstRunView.swift — shown at launch when the model assets are missing.
//
// Big friendly download panel: explains what's being fetched (~1.8 GB
// from HuggingFace), shows per-file + overall progress, and lets the
// user retry on failure. Uses the Aevum design system so it feels like
// part of the app, not a sheet from another decade.

import SwiftUI

struct FirstRunView: View {
    @StateObject private var downloader = ModelDownloader()
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            AevumColors.bgDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 48)

                hero

                Spacer(minLength: 36)

                progressPanel
                    .padding(.horizontal, 40)
                    .frame(maxWidth: 560)

                Spacer(minLength: 28)

                footer
                    .padding(.horizontal, 40)
                    .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            if downloader.isReady { downloader.start() }
        }
        .onChange(of: downloader.status) { _, status in
            if status == .done { onComplete() }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AevumColors.amber.opacity(0.12))
                    .frame(width: 84, height: 84)
                Circle()
                    .fill(AevumColors.cyan.opacity(0.10))
                    .frame(width: 84, height: 84)
                    .blur(radius: 14)
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(colors: [AevumColors.amber, AevumColors.cyan],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            Text("Aevum")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(AevumColors.text)
            Text("Download the generative model")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AevumColors.textDim)
            Text("Aevum drives Magenta RealTime 2 live. The ~1.8 GB model is\nfetched once from HuggingFace — after this you’re set.")
                .font(.system(size: 12))
                .foregroundStyle(AevumColors.textFaint)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }

    private var progressPanel: some View {
        VStack(spacing: 18) {
            overallBar
            fileRow
            if case .failed(let msg) = downloader.status {
                failureBanner(message: msg)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: AevumRadius.large)
                .fill(AevumColors.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AevumRadius.large)
                .strokeBorder(AevumColors.divider, lineWidth: 1)
        )
    }

    private var overallBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("OVERALL")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(AevumColors.textFaint)
                Spacer()
                Text("\(downloader.completedFiles) / \(downloader.totalFiles) files")
                    .font(AevumFont.mono)
                    .foregroundStyle(AevumColors.textDim)
            }
            let totalProgress = downloader.totalBytes > 0
                ? Double(downloader.totalDownloadedBytes) / Double(downloader.totalBytes)
                : 0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AevumColors.panelRaised).frame(height: 6)
                    Capsule()
                        .fill(LinearGradient(colors: [AevumColors.amber, AevumColors.cyan],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * CGFloat(totalProgress)), height: 6)
                }
            }
            .frame(height: 6)
            HStack {
                Text(formatBytes(downloader.totalDownloadedBytes))
                    .font(AevumFont.mono)
                    .foregroundStyle(AevumColors.text)
                Text("of \(formatBytes(downloader.totalBytes))")
                    .font(AevumFont.mono)
                    .foregroundStyle(AevumColors.textFaint)
                Spacer()
                Text(percentString(totalProgress))
                    .font(AevumFont.monoBold)
                    .foregroundStyle(AevumColors.cyan)
            }
        }
    }

    private var fileRow: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.system(size: 12))
                .foregroundStyle(statusColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(currentFileLabel)
                    .font(AevumFont.caption)
                    .foregroundStyle(AevumColors.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if downloader.status == .downloading {
                    Text("\(formatBytes(downloader.currentFileBytes)) / \(formatBytes(downloader.currentFileTotal))")
                        .font(AevumFont.micro)
                        .foregroundStyle(AevumColors.textFaint)
                }
            }
            Spacer()
        }
    }

    private var currentFileLabel: String {
        switch downloader.status {
        case .downloading: return downloader.currentFile
        case .done:        return "All files downloaded — launching Aevum…"
        case .failed:      return "Download failed"
        case .idle:        return "Preparing…"
        }
    }

    private var statusIcon: String {
        switch downloader.status {
        case .downloading: return "arrow.down.circle"
        case .done:        return "checkmark.circle.fill"
        case .failed:      return "exclamationmark.triangle.fill"
        case .idle:        return "clock"
        }
    }

    private var statusColor: Color {
        switch downloader.status {
        case .downloading: return AevumColors.cyan
        case .done:        return AevumColors.good
        case .failed:      return AevumColors.danger
        case .idle:        return AevumColors.textFaint
        }
    }

    private func failureBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(AevumFont.caption)
                .foregroundStyle(AevumColors.danger)
                .lineLimit(3)
            Button(action: { downloader.start() }) {
                HStack {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                    Text("Retry")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(AevumColors.amber.opacity(0.18)))
                .foregroundStyle(AevumColors.amber)
                .overlay(Capsule().strokeBorder(AevumColors.amber.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AevumRadius.small)
                .fill(AevumColors.danger.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AevumRadius.small)
                .strokeBorder(AevumColors.danger.opacity(0.25), lineWidth: 1)
        )
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("Already ran `mrt models init` + `mrt models download mrt2_small`?")
                .font(AevumFont.micro)
                .foregroundStyle(AevumColors.textFaint)
            Text("Aevum reuses those files at ~/.cache/magenta-rt-v2 — no re-download.")
                .font(AevumFont.micro)
                .foregroundStyle(AevumColors.textFaint)
        }
    }

    // MARK: - Formatting

    private func formatBytes(_ b: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: b)
    }

    private func percentString(_ p: Double) -> String {
        String(format: "%.1f%%", p * 100)
    }
}
