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
    ///
    /// Feeds 16 kHz mono to MusicCoCa synchronously via
    /// `encodeAudioPromptSync` — no worker thread, no status-poll race.
    /// The async `setAudioPromptSamplesForIndex` path had a stale-status
    /// bug (`promptStatus` stayed `success` from the previous encode
    /// until the worker re-entered, so every poll after the first
    /// short-circuited and read the previous loop's embedding).
    ///
    /// Runs the TFLite encode on a detached background task (not the main
    /// actor) so the UI doesn't stall. Retries once — the first TFLite
    /// invoke after init can occasionally fail on some clips; a single
    /// retry clears it.
    func extract(from fullAudio: DecodedAudio, startSec: Double, endSec: Double) async -> [Float]? {
        guard let bridge else { return nil }
        let mono16k = decoder.monoSamples16k(from: fullAudio, startSec: startSec, endSec: endSec)
        guard !mono16k.isEmpty else {
            print("[embed] empty 16k region for \(startSec)–\(endSec)s")
            return nil
        }
        let count = UInt(mono16k.count)
        let bridgeRef = bridge
        for attempt in 0..<2 {
            let embedding: [Float]? = await Task.detached(priority: .userInitiated) { () -> [Float]? in
                var emb = [Float](repeating: 0, count: Self.embeddingDim)
                let ok = emb.withUnsafeMutableBufferPointer { buf -> Bool in
                    bridgeRef.encodeAudioPromptSync(mono16k, count: count, out: buf.baseAddress!)
                }
                return (ok && !emb.allSatisfy({ $0 == 0 })) ? emb : nil
            }.value
            if let embedding { return embedding }
            print("[embed] attempt \(attempt + 1) failed for \(startSec)–\(endSec)s (\(mono16k.count) samples)")
        }
        return nil
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
