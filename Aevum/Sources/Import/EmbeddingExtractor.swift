// EmbeddingExtractor.swift — Batch-extract MusicCoCa embeddings for loops.
// Uses EngineBridge slot 0 repeatedly (MusicCoCa encodes one prompt at a time).
// Polls prompt status between each extraction.

import Foundation

final class EmbeddingExtractor {
    static let embeddingDim = 768

    weak var bridge: EngineBridge?
    private let decoder = AudioDecoder()

    init(bridge: EngineBridge) {
        self.bridge = bridge
    }

    /// Extract a 768-dim embedding for a loop region of a song.
    /// `fullAudio` is the decoded song (interleaved stereo @ 48 kHz).
    func extract(from fullAudio: DecodedAudio, startSec: Double, endSec: Double) async -> [Float]? {
        guard let bridge else { return nil }
        let sr = fullAudio.sampleRate
        let ch = fullAudio.channels
        let startSample = Int(startSec * sr) * ch
        let endSample = min(Int(endSec * sr) * ch, fullAudio.samples.count)
        guard endSample > startSample else { return nil }
        let region = Array(fullAudio.samples[startSample..<endSample])

        // Queue on slot 0, poll until encoded, read embedding.
        bridge.setAudioPromptSamplesForIndex(0,
                                             filename: "loop",
                                             samples: region,
                                             count: UInt(region.count))
        // Poll (max ~10s). Encoding a few-second clip is fast.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let status = bridge.promptStatusForIndex(0)
            if status == .success { break }
            if status == .error { return nil }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        if bridge.promptStatusForIndex(0) != .success { return nil }

        var embedding = [Float](repeating: 0, count: Self.embeddingDim)
        let ok = embedding.withUnsafeMutableBufferPointer { buf -> Bool in
            bridge.getAudioEmbeddingForIndex(0, out: buf.baseAddress!)
        }
        return ok ? embedding : nil
    }

    /// Batch extract for all candidates of a song. Calls `onProgress` per loop.
    func extractAll(from fullAudio: DecodedAudio,
                    candidates: [LoopCandidate],
                    onProgress: @escaping (Int, Int, [Float]?) -> Void) async {
        for (i, c) in candidates.enumerated() {
            let emb = await extract(from: fullAudio, startSec: c.startSec, endSec: c.endSec)
            onProgress(i, candidates.count, emb)
        }
    }
}
