// Models.swift — Core data models for songs, loops, sessions, and setlists.

import Foundation

struct Song: Identifiable, Codable {
    var id: Int64?
    var path: String
    var name: String
    var bpm: Double
    var durationSec: Double
    var importedAt: Date
}

struct Loop: Identifiable, Codable, Hashable {
    var id: Int64?
    var songId: Int64
    var name: String
    var startSec: Double
    var endSec: Double
    var bars: Int            // 2, 4, or 8
    var bpm: Double
    var embedding: [Float]   // 768-dim MusicCoCa embedding
    var color: String        // hex color for clip grid
    var rating: Int          // 0..5, user-adjusted importance
    var promptSlot: Int = -1 // -1 = not loaded, 0..5 = assigned to engine slot

    var durationSec: Double { endSec - startSec }
}

struct Session: Identifiable, Codable {
    var id: Int64?
    var name: String
    var createdAt: Date
    var engineStatePath: String?
    var arrangementJSON: String // serialized clip grid + scene arrangement
}

enum SetlistMode: String, Codable, CaseIterable {
    case smooth    // greedy nearest-neighbor walk (max adjacent similarity)
    case contrast  // maximize dissimilarity for dramatic morphs
    case cluster   // hierarchical grouping into 3-5 runs
}

struct Setlist: Identifiable, Codable {
    var id: Int64?
    var sessionId: Int64
    var loopIdsOrdered: [Int64] // playback order
    var mode: SetlistMode
    var createdAt: Date
}

struct MIDIMap: Identifiable, Codable {
    var id: Int64?
    var sessionId: Int64
    var cc: Int
    var param: XFParam
    var targetMin: Float
    var targetMax: Float
}

struct Scene: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    // For each slot 0..5: which loop (by its id) to load, and where on the
    // prompt surface its dot sits.
    var slotLoopIds: [Int: Int64]   // slot index → loop.id
    var slotPositions: [Int: CodableCGPoint]
    var cursorPosition: CodableCGPoint
}

struct CodableCGPoint: Codable, Equatable {
    var x: Double
    var y: Double
    init(_ p: CGPoint) { x = Double(p.x); y = Double(p.y) }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}
