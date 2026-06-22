// LibraryStore.swift — SQLite-backed persistence for songs, loops, sessions.
// Uses the system SQLite3 C library (no external dependency).
// Embeddings stored as raw Float32 BLOBs (768 * 4 = 3072 bytes per loop).

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class LibraryStore {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "Aevum.librarystore")

    let url: URL

    init(at url: URL) throws {
        self.url = url
        try url.parentDirectory.ensureDirectory()
        var handle: OpaquePointer?
        if sqlite3_open(url.path, &handle) != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw NSError(domain: "LibraryStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "open failed: \(msg)"])
        }
        self.db = handle
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try createSchema()
    }

    deinit { sqlite3_close(db) }

    // MARK: - Schema

    private func createSchema() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS songs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL,
            name TEXT NOT NULL,
            bpm REAL NOT NULL,
            duration_sec REAL NOT NULL,
            imported_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS loops (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            song_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            start_sec REAL NOT NULL,
            end_sec REAL NOT NULL,
            bars INTEGER NOT NULL,
            bpm REAL NOT NULL,
            embedding BLOB,
            color TEXT NOT NULL DEFAULT '#808080',
            rating INTEGER NOT NULL DEFAULT 0,
            prompt_slot INTEGER NOT NULL DEFAULT -1,
            FOREIGN KEY(song_id) REFERENCES songs(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at REAL NOT NULL,
            engine_state_path TEXT,
            arrangement_json TEXT
        );
        CREATE TABLE IF NOT EXISTS setlists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            loop_ids_ordered TEXT NOT NULL,
            mode TEXT NOT NULL,
            created_at REAL NOT NULL,
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS midi_maps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            cc INTEGER NOT NULL,
            param TEXT NOT NULL,
            target_min REAL NOT NULL,
            target_max REAL NOT NULL,
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_loops_song ON loops(song_id);
        """)
    }

    // MARK: - Low-level helpers

    @discardableResult
    private func exec(_ sql: String) throws -> Int {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw NSError(domain: "LibraryStore", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "exec failed: \(msg)"])
        }
        return Int(sqlite3_changes(db))
    }

    // MARK: - Songs

    @discardableResult
    func insertSong(_ song: Song) throws -> Int64 {
        let sql = "INSERT INTO songs(path, name, bpm, duration_sec, imported_at) VALUES(?,?,?,?,?)"
        try withStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, song.path, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, song.name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, song.bpm)
            sqlite3_bind_double(stmt, 4, song.durationSec)
            sqlite3_bind_double(stmt, 5, song.importedAt.timeIntervalSince1970)
            try step(stmt)
        }
        return sqlite3_last_insert_rowid(db)
    }

    func allSongs() throws -> [Song] {
        try query("SELECT id, path, name, bpm, duration_sec, imported_at FROM songs ORDER BY imported_at DESC") { row in
            Song(id: row.int64(0), path: row.text(1), name: row.text(2),
                 bpm: row.double(3), durationSec: row.double(4),
                 importedAt: Date(timeIntervalSince1970: row.double(5)))
        }
    }

    // MARK: - Loops

    @discardableResult
    func insertLoop(_ loop: Loop) throws -> Int64 {
        let sql = """
        INSERT INTO loops(song_id, name, start_sec, end_sec, bars, bpm, embedding, color, rating, prompt_slot)
        VALUES(?,?,?,?,?,?,?,?,?,?)
        """
        try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, loop.songId)
            sqlite3_bind_text(stmt, 2, loop.name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, loop.startSec)
            sqlite3_bind_double(stmt, 4, loop.endSec)
            sqlite3_bind_int(stmt, 5, Int32(loop.bars))
            sqlite3_bind_double(stmt, 6, loop.bpm)
            let blob = Data(bytes: loop.embedding, count: loop.embedding.count * 4)
            blob.withUnsafeBytes { buf in
                _ = sqlite3_bind_blob(stmt, 7, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
            }
            sqlite3_bind_text(stmt, 8, loop.color, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 9, Int32(loop.rating))
            sqlite3_bind_int(stmt, 10, Int32(loop.promptSlot))
            try step(stmt)
        }
        return sqlite3_last_insert_rowid(db)
    }

    func updateLoopEmbedding(_ loopId: Int64, embedding: [Float]) throws {
        let sql = "UPDATE loops SET embedding = ? WHERE id = ?"
        try withStatement(sql) { stmt in
            let blob = Data(bytes: embedding, count: embedding.count * 4)
            blob.withUnsafeBytes { buf in
                _ = sqlite3_bind_blob(stmt, 1, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
            }
            sqlite3_bind_int64(stmt, 2, loopId)
            try step(stmt)
        }
    }

    func loops(forSong songId: Int64) throws -> [Loop] {
        try query("SELECT id, song_id, name, start_sec, end_sec, bars, bpm, embedding, color, rating, prompt_slot FROM loops WHERE song_id = ? ORDER BY start_sec",
                  bind: { sqlite3_bind_int64($0, 1, songId) }) { row in
            row.toLoop()
        }
    }

    func allLoops() throws -> [Loop] {
        try query("SELECT id, song_id, name, start_sec, end_sec, bars, bpm, embedding, color, rating, prompt_slot FROM loops ORDER BY rating DESC, start_sec") { row in
            row.toLoop()
        }
    }

    func deleteSong(id: Int64) throws {
        try exec("DELETE FROM songs WHERE id = \(id)")
    }

    // MARK: - Sessions

    @discardableResult
    func insertSession(_ session: Session) throws -> Int64 {
        let sql = "INSERT INTO sessions(name, created_at, engine_state_path, arrangement_json) VALUES(?,?,?,?)"
        try withStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, session.name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, session.createdAt.timeIntervalSince1970)
            if let p = session.engineStatePath {
                sqlite3_bind_text(stmt, 3, p, -1, SQLITE_TRANSIENT)
            } else { sqlite3_bind_null(stmt, 3) }
            sqlite3_bind_text(stmt, 4, session.arrangementJSON, -1, SQLITE_TRANSIENT)
            try step(stmt)
        }
        return sqlite3_last_insert_rowid(db)
    }

    // MARK: - Statement helpers

    private func withStatement(_ sql: String, _ body: (OpaquePointer?) throws -> Void) throws {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "LibraryStore", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "prepare failed: \(msg)"])
        }
        defer { sqlite3_finalize(stmt) }
        try body(stmt)
    }

    private func step(_ stmt: OpaquePointer?) throws {
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "LibraryStore", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "step failed: \(msg)"])
        }
    }

    private func query<T>(_ sql: String,
                          bind: ((OpaquePointer?) -> Void)? = nil,
                          map: (Row) -> T) throws -> [T] {
        var out: [T] = []
        try withStatement(sql) { stmt in
            bind?(stmt)
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(map(Row(stmt: stmt)))
            }
        }
        return out
    }

    private struct Row {
        let stmt: OpaquePointer?
        func int64(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        func int(_ i: Int32) -> Int { Int(sqlite3_column_int(stmt, i)) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func text(_ i: Int32) -> String {
            guard let cstr = sqlite3_column_text(stmt, i) else { return "" }
            return String(cString: cstr)
        }
        func blob(_ i: Int32) -> Data {
            let n = Int(sqlite3_column_bytes(stmt, i))
            guard n > 0, let ptr = sqlite3_column_blob(stmt, i) else { return Data() }
            return Data(bytes: ptr, count: n)
        }

        func toLoop() -> Loop {
            let embData = blob(7)
            let embedding: [Float] = embData.withUnsafeBytes { buf in
                guard let base = buf.baseAddress else { return [] }
                let ptr = base.assumingMemoryBound(to: Float.self)
                return Array(UnsafeBufferPointer(start: ptr, count: embData.count / 4))
            }
            return Loop(id: int64(0), songId: int64(1), name: text(2),
                        startSec: double(3), endSec: double(4),
                        bars: int(5), bpm: double(6),
                        embedding: embedding, color: text(8),
                        rating: int(9), promptSlot: int(10))
        }
    }
}

extension URL {
    var parentDirectory: URL { deletingLastPathComponent() }
}

extension URL {
    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
    }
}
