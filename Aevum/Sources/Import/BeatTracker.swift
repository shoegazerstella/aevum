// BeatTracker.swift — Native beat tracking via Accelerate (vDSP).
// Spectral-flux onset envelope + autocorrelation tempo estimation.
// Good for 4/4 electronic; user can manually adjust for tricky material.

import Foundation
import Accelerate

struct BeatGrid {
    var bpm: Double
    var beatTimes: [Double]    // seconds, one entry per beat
    var downbeatIdx: [Int]     // indices into beatTimes marking bar starts (every 4)
}

final class BeatTracker {
    static let sampleRate: Double = 22050.0 // downsample for analysis speed
    static let fftSize: Int = 1024
    static let hopSize: Int = 512
    static let minBPM: Double = 60
    static let maxBPM: Double = 180

    /// Run beat tracking on mono Float32 samples at `sampleRate`.
    /// Returns a beat grid with BPM and per-beat times.
    func track(samples: [Float], sampleRate: Double) -> BeatGrid {
        // 1. Resample to analysis rate for speed.
        let analysisSamples = resample(samples, from: sampleRate, to: Self.sampleRate)
        let sr = Self.sampleRate

        // 2. Spectral flux onset envelope.
        let (onset, hopSec) = spectralFlux(analysisSamples, sr: sr)

        // 3. Tempo via autocorrelation.
        let bpm = estimateBPM(onset: onset, hopSec: hopSec)

        // 4. Beat phase — find the offset that best aligns beats to onsets.
        let beatPeriodSec = 60.0 / bpm
        let beatPeriodHops = beatPeriodSec / hopSec
        let phase = bestPhase(onset: onset, period: beatPeriodHops)

        // 5. Build beat times.
        var beatTimes: [Double] = []
        var t = Double(phase) * hopSec
        let duration = Double(analysisSamples.count) / sr
        while t < duration {
            beatTimes.append(t)
            t += beatPeriodSec
        }

        // 6. Downbeats — pick the phase (0..3) that lands on the strongest onset.
        let downbeatOffset = bestDownbeat(onset: onset, beatTimes: beatTimes,
                                          hopSec: hopSec, beatsPerBar: 4)
        var downbeatIdx: [Int] = []
        for i in stride(from: downbeatOffset, to: beatTimes.count, by: 4) {
            downbeatIdx.append(i)
        }
        return BeatGrid(bpm: bpm, beatTimes: beatTimes, downbeatIdx: downbeatIdx)
    }

    // MARK: - Spectral flux

    private func spectralFlux(_ samples: [Float], sr: Double) -> (onset: [Float], hopSec: Double) {
        let n = samples.count
        let hop = Self.hopSize
        let hopSec = Double(hop) / sr

        var onset: [Float] = []
        var prevEnergy: Float = 0
        var frameStart = 0
        while frameStart + hop <= n {
            var energy: Float = 0
            for i in 0..<hop {
                let s = samples[frameStart + i]
                energy += s * s
            }
            onset.append(max(0, energy - prevEnergy))
            prevEnergy = energy
            frameStart += hop
        }

        let maxVal = onset.max() ?? 1
        if maxVal > 0 {
            for i in 0..<onset.count { onset[i] /= maxVal }
        }
        return (onset, hopSec)
    }

    // MARK: - Tempo

    private func estimateBPM(onset: [Float], hopSec: Double) -> Double {
        guard onset.count > 4 else { return 120 }
        // Autocorrelation — check lag range for 60..180 BPM.
        let minLag = Int(60.0 / Self.maxBPM / hopSec)
        let maxLag = Int(60.0 / Self.minBPM / hopSec)
        var bestLag = minLag
        var bestCorr: Float = -1
        for lag in minLag...min(maxLag, onset.count - 1) {
            var corr: Float = 0
            let n = onset.count - lag
            onset.withUnsafeBufferPointer { buf in
                vDSP_dotpr(buf.baseAddress!, 1,
                           buf.baseAddress!.advanced(by: lag), 1,
                           &corr, vDSP_Length(n))
            }
            // Bias toward mid-range tempos (avoid 60 and 180 extremes).
            let tempoBias = 1.0 - abs(Double(lag) - Double(minLag + maxLag) / 2) / Double(maxLag - minLag) * 0.3
            let biased = corr * Float(tempoBias)
            if biased > bestCorr {
                bestCorr = biased
                bestLag = lag
            }
        }
        let beatPeriodSec = Double(bestLag) * hopSec
        var bpm = 60.0 / beatPeriodSec
        // Fold to 60..180 range via octave
        while bpm < Self.minBPM { bpm *= 2 }
        while bpm > Self.maxBPM { bpm /= 2 }
        return bpm
    }

    // MARK: - Phase

    private func bestPhase(onset: [Float], period: Double) -> Int {
        let p = Int(period.rounded())
        guard p > 0 else { return 0 }
        var bestPhase = 0
        var bestScore: Float = -1
        for phase in 0..<p {
            var score: Float = 0
            var i = phase
            while i < onset.count {
                score += onset[i]
                i += p
            }
            if score > bestScore {
                bestScore = score
                bestPhase = phase
            }
        }
        return bestPhase
    }

    private func bestDownbeat(onset: [Float], beatTimes: [Double],
                              hopSec: Double, beatsPerBar: Int) -> Int {
        guard beatTimes.count > beatsPerBar else { return 0 }
        func scoreFor(offset: Int) -> Float {
            var s: Float = 0
            var i = offset
            while i < beatTimes.count {
                let hopIdx = Int(beatTimes[i] / hopSec)
                if hopIdx < onset.count { s += onset[hopIdx] }
                i += beatsPerBar
            }
            return s
        }
        var best = 0
        var bestScore: Float = -1
        for offset in 0..<beatsPerBar {
            let s = scoreFor(offset: offset)
            if s > bestScore { bestScore = s; best = offset }
        }
        return best
    }

    // MARK: - Resampling (linear, sufficient for onset analysis)

    private func resample(_ input: [Float], from inRate: Double, to outRate: Double) -> [Float] {
        if abs(inRate - outRate) < 1 { return input }
        let ratio = outRate / inRate
        let outCount = Int(Double(input.count) * ratio)
        var output = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let srcPos = Double(i) / ratio
            let idx = Int(srcPos)
            let frac = Float(srcPos - Double(idx))
            if idx + 1 < input.count {
                output[i] = input[idx] * (1 - frac) + input[idx + 1] * frac
            } else if idx < input.count {
                output[i] = input[idx]
            }
        }
        return output
    }
}
