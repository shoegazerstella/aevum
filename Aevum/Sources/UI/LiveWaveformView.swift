// LiveWaveformView.swift — Scrolling glowing waveform of the live engine
// output. Reads the level tap (per-column peaks) from AudioEngine and
// renders a centered, mirrored bar waveform that scrolls left as new
// columns arrive. Color follows the blend axis (amber→cyan) so the viz
// visually ties to the current morph position.
//
// The view polls the tap via TimelineView at ~60 fps; the audio thread
// writes peaks lock-free. Torn reads just produce a briefly jittery
// frame, which is fine for a performance visualization.

import SwiftUI

struct LiveWaveformView: View {
    @EnvironmentObject var controller: EngineController
    var height: CGFloat = 44
    var showsLabel: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { _ in
            Canvas { ctx, size in
                let tap = controller.audioEngine.levelSnapshot()
                let peaks = tap.peaks
                let widx = tap.writeIndex
                let count = peaks.count
                guard count > 0 else { return }
                let mid = size.height / 2
                // Number of bars that fit — one bar per ~3px column.
                let barWidth: CGFloat = 3
                let gap: CGFloat = 1
                let stride = barWidth + gap
                let visible = Int(size.width / stride)
                // Read backwards from the write index so the newest column
                // is on the right and older columns scroll left.
                let glowColor = AevumColors.blendAxis(at: 0.5)
                for i in 0..<visible {
                    let idx = ((widx - 1 - i) % count + count) % count
                    let p = CGFloat(peaks[idx])
                    guard p > 0.001 else { continue }
                    let h = max(2, p * (size.height - 4))
                    let x = size.width - CGFloat(i + 1) * stride
                    // Color shifts amber→cyan along the history (older =
                    // cooler), and brightens with amplitude.
                    let t = Double(i) / Double(max(1, visible))
                    let col = AevumColors.blendAxis(at: 1.0 - t * 0.7)
                    let rect = CGRect(x: x, y: mid - h / 2, width: barWidth, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                             with: .color(col.opacity(0.85)))
                    // Faint glow underlay for the loudest bars.
                    if p > 0.4 {
                        let glow = CGRect(x: x - 1, y: mid - h / 2 - 1,
                                          width: barWidth + 2, height: h + 2)
                        ctx.fill(Path(roundedRect: glow, cornerRadius: 2),
                                 with: .color(glowColor.opacity(0.18)))
                    }
                }
                // Center reference line — barely visible.
                var line = Path()
                line.move(to: CGPoint(x: 0, y: mid))
                line.addLine(to: CGPoint(x: size.width, y: mid))
                ctx.stroke(line, with: .color(.white.opacity(0.05)), lineWidth: 1)
            }
            .frame(height: height)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AevumRadius.small)
                .fill(AevumColors.bgDeep.opacity(0.6))
        )
        .overlay(alignment: .topLeading) {
            if showsLabel {
                Text("LIVE OUTPUT")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AevumColors.textFaint.opacity(0.7))
                    .padding(.horizontal, 6).padding(.vertical, 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AevumRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: AevumRadius.small)
                .strokeBorder(AevumColors.divider, lineWidth: 1)
        )
    }
}
