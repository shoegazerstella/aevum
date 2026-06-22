// SetlistSuggester.swift — Suggest ordered setlists from a loop collection.
// Three modes: smooth (greedy NN walk), contrast (max dissimilarity),
// cluster (hierarchical grouping into runs).

import Foundation

final class SetlistSuggester {
    private let sim = SimilarityEngine()

    enum Mode: String, CaseIterable, Codable {
        case smooth, contrast, cluster
    }

    func suggest(loops: [Loop], mode: Mode, matrix: [[Float]]? = nil) -> [Loop] {
        guard loops.count > 1 else { return loops }
        let m = matrix ?? sim.similarityMatrix(loops: loops)
        switch mode {
        case .smooth:  return smoothWalk(loops: loops, matrix: m)
        case .contrast: return contrastWalk(loops: loops, matrix: m)
        case .cluster:  return clusterOrder(loops: loops, matrix: m)
        }
    }

    // MARK: - Smooth: greedy nearest-neighbor walk maximizing adjacent similarity.
    // Start from the loop with highest novelty, repeatedly pick the most similar
    // unvisited loop next.

    private func smoothWalk(loops: [Loop], matrix: [[Float]]) -> [Loop] {
        let n = loops.count
        // Start: highest novelty (most different from mean).
        let meanEmb = sim.mean(loops)
        var novelties: [(Int, Float)] = []
        for (i, l) in loops.enumerated() {
            novelties.append((i, 1 - sim.cosine(l.embedding, meanEmb)))
        }
        let start = novelties.max(by: { $0.1 < $1.1 })?.0 ?? 0

        var visited = Set<Int>([start])
        var order = [start]
        var current = start
        while visited.count < n {
            var best = -1
            var bestSim: Float = -2
            for j in 0..<n where !visited.contains(j) {
                if matrix[current][j] > bestSim {
                    bestSim = matrix[current][j]
                    best = j
                }
            }
            if best < 0 { break }
            order.append(best)
            visited.insert(best)
            current = best
        }
        return order.map { loops[$0] }
    }

    // MARK: - Contrast: alternate between dissimilar loops for dramatic morphs.

    private func contrastWalk(loops: [Loop], matrix: [[Float]]) -> [Loop] {
        let n = loops.count
        // Start from the pair with max dissimilarity.
        var bestPair = (0, 1)
        var bestDist: Float = -1
        for i in 0..<n {
            for j in (i + 1)..<n {
                let d = 1 - matrix[i][j]
                if d > bestDist { bestDist = d; bestPair = (i, j) }
            }
        }
        var visited: Set<Int> = [bestPair.0, bestPair.1]
        var order = [bestPair.0, bestPair.1]
        var current = bestPair.1
        while visited.count < n {
            // Pick the LEAST similar unvisited loop (max contrast).
            var best = -1
            var worstSim: Float = 2
            for j in 0..<n where !visited.contains(j) {
                if matrix[current][j] < worstSim {
                    worstSim = matrix[current][j]
                    best = j
                }
            }
            if best < 0 { break }
            order.append(best)
            visited.insert(best)
            current = best
        }
        return order.map { loops[$0] }
    }

    // MARK: - Cluster: simple hierarchical grouping into 3-5 runs.

    private func clusterOrder(loops: [Loop], matrix: [[Float]]) -> [Loop] {
        let n = loops.count
        let k = min(5, max(3, n / 4))
        // K-means-ish: pick k spread-out seeds, assign by similarity.
        var seeds = pickSeeds(loops: loops, matrix: matrix, k: k)
        var assignments = [Int](repeating: 0, count: n)
        for _ in 0..<10 {
            var changed = false
            for i in 0..<n {
                var best = 0
                var bestSim: Float = -2
                for (sIdx, seed) in seeds.enumerated() {
                    if matrix[i][seed] > bestSim { bestSim = matrix[i][seed]; best = sIdx }
                }
                if assignments[i] != best { changed = true; assignments[i] = best }
            }
            if !changed { break }
            // Recompute seeds = most central loop in each cluster
            for s in 0..<k {
                let members = (0..<n).filter { assignments[$0] == s }
                if members.isEmpty { continue }
                var bestCentroid = members[0]
                var bestAvgSim: Float = -2
                for m in members {
                    let avg = members.reduce(Float(0)) { $0 + matrix[m][$1] } / Float(members.count)
                    if avg > bestAvgSim { bestAvgSim = avg; bestCentroid = m }
                }
                seeds[s] = bestCentroid
            }
        }
        // Order clusters by average tempo, then within cluster by similarity.
        var clusters: [(Int, [Int])] = []
        for s in 0..<k {
            let members = (0..<n).filter { assignments[$0] == s }
            if !members.isEmpty { clusters.append((s, members)) }
        }
        clusters.sort { avgTempo(loops, $0.1) < avgTempo(loops, $1.1) }
        var order: [Int] = []
        for (_, members) in clusters {
            // Within-cluster: smooth walk
            let subLoops = members.map { loops[$0] }
            let subMatrix = members.map { i in members.map { j in matrix[i][j] } }
            let subOrder = smoothWalk(loops: subLoops, matrix: subMatrix)
            for sl in subOrder {
                if let idx = loops.firstIndex(where: { $0.id == sl.id }) {
                    order.append(idx)
                }
            }
        }
        return order.map { loops[$0] }
    }

    private func pickSeeds(loops: [Loop], matrix: [[Float]], k: Int) -> [Int] {
        let n = loops.count
        var seeds = [Int.random(in: 0..<n)]
        while seeds.count < k {
            var best = 0
            var bestMinDist: Float = -1
            for i in 0..<n where !seeds.contains(i) {
                let minSim = seeds.map { matrix[i][$0] }.min() ?? 1
                let dist = 1 - minSim
                if dist > bestMinDist { bestMinDist = dist; best = i }
            }
            seeds.append(best)
        }
        return seeds
    }

    private func avgTempo(_ loops: [Loop], _ indices: [Int]) -> Double {
        indices.reduce(0.0) { $0 + loops[$1].bpm } / Double(indices.count)
    }

    /// Average adjacent similarity of an ordered setlist (quality metric for UI).
    func averageAdjacentSimilarity(_ loops: [Loop]) -> Float {
        guard loops.count > 1 else { return 1 }
        var sum: Float = 0
        for i in 1..<loops.count {
            sum += sim.cosine(loops[i - 1].embedding, loops[i].embedding)
        }
        return sum / Float(loops.count - 1)
    }
}
