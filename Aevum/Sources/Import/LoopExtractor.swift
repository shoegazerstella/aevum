// LoopExtractor.swift — Slice a song into beat-aligned loop candidates.
// Produces 2/4/8-bar candidates at downbeat boundaries, dedupes by
// overlap, and assigns provisional colors. Embeddings are extracted
// separately via EmbeddingExtractor (which talks to EngineBridge).

import Foundation
import Accelerate

struct LoopCandidate {
    var name: String
    var startSec: Double
    var endSec: Double
    var bars: Int
    var bpm: Double
    var color: String
    var energy: Float // RMS energy, used for ranking
}

final class LoopExtractor {
    /// Slice a decoded song + beat grid into loop candidates.
    /// - Parameter maxCount: if > 0, return at most this many candidates
    ///   (picks the highest-energy subset spread across bar lengths).
    func extractCandidates(audio: DecodedAudio, grid: BeatGrid,
                           barOptions: [Int] = [2, 4, 8],
                           maxCount: Int = 0) -> [LoopCandidate] {
        guard !grid.downbeatIdx.isEmpty else { return [] }
        let beatSec = 60.0 / grid.bpm
        let downbeats = grid.downbeatIdx.compactMap { idx -> Double? in
            idx < grid.beatTimes.count ? grid.beatTimes[idx] : nil
        }
        let duration = audio.durationSec

        var candidates: [LoopCandidate] = []
        let palette = Self.colorPalette()

        for bars in barOptions {
            for (i, start) in downbeats.enumerated() {
                let endIdx = i + bars
                guard endIdx < downbeats.count else { continue }
                let end = downbeats[endIdx]
                if end - start < 0.5 { continue }
                let energy = rmsEnergy(audio: audio, startSec: start, endSec: end)
                let color = palette[i % palette.count]
                candidates.append(LoopCandidate(
                    name: "\(bars)b @ \(formatTime(start))",
                    startSec: start, endSec: end, bars: bars,
                    bpm: grid.bpm, color: color, energy: energy))
            }
        }
        // Dedup overlapping candidates of the same bar length — keep highest energy.
        let grouped = Dictionary(grouping: candidates, by: { $0.bars })
        var deduped: [LoopCandidate] = []
        for (_, group) in grouped.sorted(by: { $0.key < $1.key }) {
            var kept: [LoopCandidate] = []
            for c in group.sorted(by: { $0.energy > $1.energy }) {
                if !kept.contains(where: { overlap(c, $0) > 0.5 }) {
                    kept.append(c)
                }
            }
            deduped.append(contentsOf: kept)
        }
        // Sort by start time
        deduped.sort { $0.startSec < $1.startSec }
        // If maxCount is set, pick the top candidates by energy, spread
        // across bar lengths (round-robin per bar-length group).
        if maxCount > 0, deduped.count > maxCount {
            let grouped = Dictionary(grouping: deduped, by: { $0.bars })
            var sortedGroups = grouped.values.map { $0.sorted { $0.energy > $1.energy } }
            // Sort groups so the bar-length with most candidates goes first
            sortedGroups.sort { $0.count > $1.count }
            var selected: [LoopCandidate] = []
            var indices = [Int](repeating: 0, count: sortedGroups.count)
            while selected.count < maxCount {
                var anyLeft = false
                for (gi, group) in sortedGroups.enumerated() {
                    guard indices[gi] < group.count else { continue }
                    selected.append(group[indices[gi]])
                    indices[gi] += 1
                    anyLeft = true
                    if selected.count >= maxCount { break }
                }
                if !anyLeft { break }
            }
            deduped = selected
        }
        return deduped
    }

    private func overlap(_ a: LoopCandidate, _ b: LoopCandidate) -> Double {
        let lo = max(a.startSec, b.startSec)
        let hi = min(a.endSec, b.endSec)
        guard hi > lo else { return 0 }
        let len = min(a.endSec - a.startSec, b.endSec - b.startSec)
        return (hi - lo) / len
    }

    private func rmsEnergy(audio: DecodedAudio, startSec: Double, endSec: Double) -> Float {
        let sr = audio.sampleRate
        let ch = audio.channels
        let startSample = Int(startSec * sr) * ch
        let endSample = min(Int(endSec * sr) * ch, audio.samples.count)
        guard endSample > startSample else { return 0 }
        let count = endSample - startSample
        var sq: Float = 0
        audio.samples.withUnsafeBufferPointer { buf in
            vDSP_svesq(buf.baseAddress!.advanced(by: startSample), 1, &sq, vDSP_Length(count))
        }
        return sqrtf(sq / Float(count))
    }

    private func formatTime(_ sec: Double) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }

    private static func colorPalette() -> [String] {
        ["#5B8DEF", "#7FB069", "#E8743B", "#B26FD3", "#D4A84B", "#3DB5B5",
         "#E85C7D", "#6C7A89", "#A8D08D", "#F0B6C8"]
    }
}
