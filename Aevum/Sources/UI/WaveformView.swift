// WaveformView.swift — Canvas-rendered waveform with loop region markers.

import SwiftUI

struct WaveformView: View {
    let samples: [Float]      // interleaved stereo
    let channels: Int
    let playhead: Double      // 0..1
    let loopRegions: [(start: Double, end: Double, color: Color)]
    let selectedRegion: Int?

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, sz in
                guard !samples.isEmpty else { return }
                let n = samples.count / channels
                let buckets = max(Int(sz.width), 1)
                let perBucket = max(n / buckets, 1)

                // Compute peaks per bucket
                var peaks = [Float](repeating: 0, count: buckets)
                for b in 0..<buckets {
                    let start = b * perBucket
                    let end = min(start + perBucket, n)
                    var peak: Float = 0
                    for i in start..<end {
                        let s = abs(samples[i * channels])
                        if s > peak { peak = s }
                    }
                    peaks[b] = peak
                }
                let maxPeak = peaks.max() ?? 1

                // Draw loop region backgrounds
                for (idx, region) in loopRegions.enumerated() {
                    let x0 = region.start * sz.width
                    let x1 = region.end * sz.width
                    let isSel = selectedRegion == idx
                    ctx.fill(
                        Path(CGRect(x: x0, y: 0, width: x1 - x0, height: sz.height)),
                        with: .color(region.color.opacity(isSel ? 0.35 : 0.15))
                    )
                }

                // Draw waveform
                var path = Path()
                let midY = sz.height / 2
                for b in 0..<buckets {
                    let x = CGFloat(b)
                    let h = CGFloat(peaks[b] / maxPeak) * (sz.height / 2 - 2)
                    path.move(to: CGPoint(x: x, y: midY - h))
                    path.addLine(to: CGPoint(x: x, y: midY + h))
                }
                ctx.stroke(path, with: .color(.primary.opacity(0.7)), lineWidth: 1)

                // Playhead
                let px = playhead * sz.width
                var playPath = Path()
                playPath.move(to: CGPoint(x: px, y: 0))
                playPath.addLine(to: CGPoint(x: px, y: sz.height))
                ctx.stroke(playPath, with: .color(.red), lineWidth: 1)
            }
        }
    }
}
