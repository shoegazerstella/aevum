// SimilarityEngine.swift — Cosine similarity over 768-dim MusicCoCa embeddings.
// Uses Accelerate (vDSP) for vectorized dot products. Builds a cached
// similarity matrix over all loops for fast setlist suggestions.

import Foundation
import Accelerate

final class SimilarityEngine {
    static let embeddingDim = 768

    /// Cosine similarity in [-1, 1]. Returns 0 for zero-norm vectors.
    func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, a.count == Self.embeddingDim else { return 0 }
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        a.withUnsafeBufferPointer { ab in
            b.withUnsafeBufferPointer { bb in
                vDSP_svesq(ab.baseAddress!, 1, &na, vDSP_Length(a.count))
                vDSP_svesq(bb.baseAddress!, 1, &nb, vDSP_Length(b.count))
                vDSP_dotpr(ab.baseAddress!, 1, bb.baseAddress!, 1, &dot, vDSP_Length(a.count))
            }
        }
        let denom = na * nb
        return denom > 0 ? dot / denom : 0
    }

    /// Full NxN similarity matrix for a list of loops.
    func similarityMatrix(loops: [Loop]) -> [[Float]] {
        let n = loops.count
        var m = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        for i in 0..<n {
            m[i][i] = 1.0
            for j in (i + 1)..<n {
                let s = cosine(loops[i].embedding, loops[j].embedding)
                m[i][j] = s
                m[j][i] = s
            }
        }
        return m
    }

    /// Mean embedding of a collection (for novelty scoring).
    func mean(_ loops: [Loop]) -> [Float] {
        guard !loops.isEmpty else { return [Float](repeating: 0, count: Self.embeddingDim) }
        var acc = [Double](repeating: 0, count: Self.embeddingDim)
        for l in loops {
            for k in 0..<Self.embeddingDim { acc[k] += Double(l.embedding[k]) }
        }
        let n = Float(loops.count)
        return acc.map { Float($0) / n }
    }

    /// Novelty of a loop = 1 - similarity to the mean of all loops.
    /// High novelty = sounds different from the average → interesting.
    func novelty(_ loop: Loop, against all: [Loop]) -> Float {
        let meanEmb = mean(all)
        return 1.0 - cosine(loop.embedding, meanEmb)
    }
}
