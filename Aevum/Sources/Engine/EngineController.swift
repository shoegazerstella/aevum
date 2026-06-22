// EngineController.swift — Central orchestrator observable object.
// Owns EngineBridge, AudioEngine, MIDIManager, LibraryStore, and the
// import pipeline. Exposes observable state for SwiftUI.

import Foundation
import SwiftUI
import Combine
import AVFAudio

@MainActor
final class EngineController: ObservableObject {

    // Core engine stack
    let bridge = EngineBridge()
    private(set) var audioEngine: AudioEngine!
    private(set) var midiManager: MIDIManager!
    let library: LibraryStore

    // Import pipeline
    private let beatTracker = BeatTracker()
    private let loopExtractor = LoopExtractor()
    private let decoder = AudioDecoder()
    private lazy var embeddingExtractor = EmbeddingExtractor(bridge: bridge)

    // Observable state
    @Published var songs: [Song] = []
    @Published var loops: [Loop] = []
    @Published var isEngineLoaded = false
    @Published var isPlaying = false
    @Published var metrics: XFEngineMetrics = XFEngineMetrics()
    @Published var importProgress: ImportProgress = .idle
    @Published var activeSlot: Int = 0
    @Published var blendWeights: [Float] = Array(repeating: 0, count: 6)
    @Published var paramSnapshot = ParamSnapshot()
    @Published var scenes: [Scene] = []
    // What loop name / loop id each slot currently holds (array avoids Observation crashes with Dictionary)
    @Published var slotLabels: [String?] = Array(repeating: nil, count: 6)
    @Published var slotLoopIds: [Int64?] = Array(repeating: nil, count: 6)
    // Prompt surface state lives on the controller so scenes can capture/restore it.
    @Published var slotPositions: [Int: CGPoint] = [:]
    @Published var cursorPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)

    // Preview + prefill state for the "listen, then generate on top" flow.
    // `previewingLoopId` is the loop currently playing raw audio through
    // the engine graph; nil = no preview. `isPrefilling` gates the play
    // button + shows a progress badge during prefillStateWithSamples.
    @Published var previewingLoopId: Int64?
    @Published var isPrefilling: Bool = false
    @Published var prefillLog: [String] = []

    // Cache decoded audio for the currently-selected song (for waveform + re-extract).
    @Published var decodedAudioCache: [Int64: DecodedAudio] = [:]

    // Performance / buffer tuning (persisted across launches).
    @Published var bufferSize: UInt = 2048 {
        didSet { bridge.setBufferSize(bufferSize); savePerfSettings() }
    }
    @Published var qualityPreset: QualityPreset = .balanced {
        didSet { applyQualityPreset(qualityPreset); savePerfSettings() }
    }

    // Model/resource paths (bundled in app on release; dev uses cache).
    let modelPath: String
    let resourcePath: String
    let spectrostreamPath: String

    private var metricsTimer: Timer?

    init(libraryURL: URL, modelPath: String, resourcePath: String, spectrostreamPath: String) {
        self.modelPath = modelPath
        self.resourcePath = resourcePath
        self.spectrostreamPath = spectrostreamPath
        do {
            self.library = try LibraryStore(at: libraryURL)
        } catch {
            fatalError("LibraryStore init failed: \(error)")
        }
        self.audioEngine = AudioEngine(bridge: bridge)
        self.midiManager = MIDIManager(bridge: bridge)
        loadScenes()
        // Load songs + loops from SQLite immediately so the library
        // appears the moment the window opens — don't wait for the
        // engine to finish loading (Metal shader compilation takes
        // 2–5 s, during which the grid would otherwise look empty
        // and the user would think their imports were lost).
        refreshLibrary()
    }

    // MARK: - Engine lifecycle

    func loadEngine() async {
        guard bridge.initAssets(resourcePath) else {
            print("initAssets failed for \(resourcePath)")
            return
        }
        guard bridge.loadModel(modelPath) else {
            print("loadModel failed for \(modelPath)")
            return
        }
        _ = bridge.loadPrefillModel(spectrostreamPath, prefillPath: nil)
        // Apply persisted performance settings before starting the engine
        // so the inference thread picks up the right buffer size + sampling
        // params from frame 0.
        loadPerfSettings()
        bridge.setBufferSize(bufferSize)
        applyQualityPreset(qualityPreset)
        bridge.start()
        // Defer text prompt to avoid TFLite crash on launch — user can set via UI later.
        isEngineLoaded = true
        midiManager.connectAllSources()
        // Audio engine stays stopped until user presses play — otherwise
        // the engine generates audio from default prompts immediately.
        startMetricsPolling()
        refreshLibrary()
    }

    func stop() {
        audioEngine?.stop()
        bridge.stop()
        metricsTimer?.invalidate()
        isPlaying = false
    }

    private func startMetricsPolling() {
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollMetrics() }
        }
    }

    private func pollMetrics() {
        metrics = bridge.metrics()
    }

    // MARK: - Library refresh

    func refreshLibrary() {
        do {
            songs = try library.allSongs()
            loops = try library.allLoops()
        } catch { print("refreshLibrary: \(error)") }
    }

    // MARK: - Transport

    func togglePlay() {
        isPlaying.toggle()
        if isPlaying {
            // Starting generation — stop any active preview and restore mute.
            stopPreview()
            bridge.setMute(false)
            do { try audioEngine.start() } catch { print("audioEngine start: \(error)") }
            bridge.triggerReset()
        } else {
            audioEngine.stop()
        }
    }

    func play() {
        guard !isPlaying else { return }
        stopPreview()
        bridge.setMute(false)
        isPlaying = true
        do { try audioEngine.start() } catch { print("audioEngine start: \(error)") }
        bridge.triggerReset()
    }

    func stopPlayback() {
        guard isPlaying else { return }
        isPlaying = false
        audioEngine.stop()
    }

    func triggerReset() { bridge.triggerReset() }

    // MARK: - Clip launching / removal

    func launchLoop(_ loop: Loop, intoSlot slot: Int? = nil, solo: Bool = true) {
        let slot = slot ?? nextFreeSlot()
        guard slot >= 0, slot < 6 else { return }
        // If this loop is already loaded in another slot, clear that slot
        // first so the same loop can't occupy two slots.
        if let existing = self.slot(forLoop: loop.id ?? -1), existing != slot {
            clearSlot(existing)
        }
        Task {
            guard let audio = await decodedAudio(for: loop.songId) else { return }
            let sr = audio.sampleRate
            let ch = audio.channels
            let startSample = Int(loop.startSec * sr) * ch
            let endSample = min(Int(loop.endSec * sr) * ch, audio.samples.count)
            guard endSample > startSample else { return }
            let region = Array(audio.samples[startSample..<endSample])
            bridge.setAudioPromptSamplesForIndex(Int32(slot),
                                                  filename: loop.name,
                                                  samples: region,
                                                  count: UInt(region.count))
            // Track the label and id for the prompt-surface UI
            slotLabels[slot] = loop.name
            slotLoopIds[slot] = loop.id
            // Seed a default position for this slot on the prompt surface
            // if the user hasn't dragged it yet.
            if slotPositions[slot] == nil {
                slotPositions[slot] = defaultSlotPosition(slot)
            }
            if solo {
                setActiveSlot(slot)
            } else {
                // Additive: distribute equally across all loaded slots
                var loaded: [Int] = []
                for i in 0..<6 where slotLoopIds[i] != nil { loaded.append(i) }
                let w = 1.0 / Float(loaded.count)
                var weights = Array(repeating: Float(0), count: 6)
                for s in loaded { weights[s] = w }
                blendWeights = weights
                applyBlendWeights(weights)
            }
        }
    }

    /// Default position for a slot on the prompt surface (hex layout).
    func defaultSlotPosition(_ slot: Int) -> CGPoint {
        let angle = Double(slot) * (.pi / 3) - .pi / 2
        return CGPoint(x: 0.5 + 0.32 * cos(angle), y: 0.5 + 0.32 * sin(angle))
    }

    func clearSlot(_ slot: Int) {
        guard slot >= 0, slot < 6 else { return }
        // Clear the audio prompt for this slot by sending silence
        bridge.setAudioPromptSamplesForIndex(Int32(slot),
                                              filename: "",
                                              samples: [],
                                              count: 0)
        slotLabels[slot] = nil
        slotLoopIds[slot] = nil
        slotPositions[slot] = nil
        blendWeights[slot] = 0
        // Renormalize remaining weights so the blend still sums to 1
        // (otherwise the cleared slot's weight is gone but the others
        // stay at their old sub-1 values, leaving a quiet/empty blend).
        let remaining = blendWeights.reduce(0, +)
        if remaining > 0.001 {
            for i in 0..<6 { blendWeights[i] /= remaining }
        }
        applyBlendWeights(blendWeights)
    }

    private func nextFreeSlot() -> Int {
        for i in 0..<6 where slotLoopIds[i] == nil { return i }
        for i in 0..<6 where blendWeights[i] == 0 { return i }
        return 0 // all in use, replace slot 0
    }

    /// Returns the slot a loop is currently loaded into, or nil if not loaded.
    func slot(forLoop loopId: Int64) -> Int? {
        for (slot, id) in slotLoopIds.enumerated() where id == loopId {
            return slot
        }
        return nil
    }

    /// Solo a slot: zero all others, set this one to 1.
    func setActiveSlot(_ slot: Int) {
        activeSlot = slot
        var weights = Array(repeating: Float(0), count: 6)
        weights[slot] = 1.0
        blendWeights = weights
        applyBlendWeights(weights)
    }

    /// Toggle a loop's slot in/out of the active blend (additive).
    /// If the loop isn't loaded, launch it first. If it's the only active
    /// slot, treat as solo (keep at 1.0). Otherwise redistribute equally
    /// across all active slots.
    func toggleLoopInBlend(_ loop: Loop) {
        let slot = self.slot(forLoop: loop.id ?? -1) ?? nextFreeSlot()
        if slotLoopIds[slot] == nil {
            launchLoop(loop, intoSlot: slot, solo: false)
        }
        var active: [Int] = []
        for i in 0..<6 where blendWeights[i] > 0.01 { active.append(i) }
        if active.contains(slot) {
            // Remove from blend
            active.removeAll { $0 == slot }
        } else {
            active.append(slot)
        }
        var weights = Array(repeating: Float(0), count: 6)
        if active.isEmpty {
            weights[slot] = 1.0
        } else {
            let w = 1.0 / Float(active.count)
            for s in active { weights[s] = w }
        }
        blendWeights = weights
        applyBlendWeights(weights)
    }

    func setBlendWeight(_ slot: Int, _ weight: Float) {
        guard slot >= 0, slot < 6 else { return }
        blendWeights[slot] = weight
        applyBlendWeights(blendWeights)
    }

    private func applyBlendWeights(_ weights: [Float]) {
        // Forward to the engine. The inference loop detects the position
        // generation bump from `set_blend_weights` and re-blends MusicCoCa
        // tokens on its next 25 Hz frame (see realtime_runner.cpp). We do
        // NOT call `triggerReset` here — resetting clears the ring buffer
        // and runs 3 synchronous prime frames, which audibly stops the
        // generation every time the user moves the prompt surface or a
        // blend slider. Smooth morphing only requires the token re-blend.
        weights.withUnsafeBufferPointer { buf in
            bridge.setBlendWeights(buf.baseAddress!, count: Int32(weights.count))
        }
    }

    // MARK: - Prompt surface (2D IDW blend)

    /// Given cursor (x,y) in [0,1]² and per-slot positions, compute
    /// inverse-distance-weighted blend weights and apply to engine.
    /// Only slots that actually have a loaded loop contribute to the
    /// blend — empty slots are skipped so the cursor doesn't pull the
    /// blend toward silence.
    func updatePromptSurface(cursor: CGPoint, slotPositions: [Int: CGPoint]) {
        self.cursorPosition = cursor
        var weights = Array(repeating: Float(0), count: 6)
        var totalInvDist: Float = 0
        var raw: [(Int, Float)] = []
        for (slot, pos) in slotPositions {
            // Skip slots with no loop loaded — they contribute nothing.
            guard slotLoopIds[slot] != nil else { continue }
            let dx = Float(cursor.x) - Float(pos.x)
            let dy = Float(cursor.y) - Float(pos.y)
            let dist = sqrtf(dx * dx + dy * dy)
            let invDist = dist < 0.001 ? 1000.0 : 1.0 / dist
            raw.append((slot, invDist))
            totalInvDist += invDist
        }
        if totalInvDist > 0 {
            for (slot, w) in raw {
                weights[slot] = w / totalInvDist
            }
        } else if !slotLoopIds.allSatisfy({ $0 == nil }) {
            // Cursor is on a slot with no loaded loop and there are loaded
            // slots — fall back to equal blend across loaded slots so the
            // audio doesn't drop out entirely.
            var loaded: [Int] = []
            for i in 0..<6 where slotLoopIds[i] != nil { loaded.append(i) }
            let w = 1.0 / Float(loaded.count)
            for s in loaded { weights[s] = w }
        }
        blendWeights = weights
        applyBlendWeights(weights)
    }

    // MARK: - Parameters (live control)

    func applyParam(_ param: XFParam, value: Float) {
        midiManager.applyParam(param, value: value)
        paramSnapshot.update(param, value: value)
    }

    // MARK: - Import pipeline

    enum ImportProgress: Equatable {
        case idle
        case decoding(String, Double)    // filename, 0..1
        case beatTracking(String)
        case slicing(String)
        case extractingEmbeddings(String, Int, Int) // filename, done, total
        case done
        case failed(String)
    }

    func importSong(at url: URL) async {
        let name = url.lastPathComponent
        importProgress = .decoding(name, 0)
        do {
            let audio = try await decoder.decode(at: url)
            importProgress = .beatTracking(name)
            let mono = decoder.monoForAnalysis(audio, targetRate: BeatTracker.sampleRate)
            let grid = beatTracker.track(samples: mono, sampleRate: BeatTracker.sampleRate)

            importProgress = .slicing(name)
            let candidates = loopExtractor.extractCandidates(audio: audio, grid: grid, barOptions: [2, 4], maxCount: 5)

            // Insert song
            let songId = try library.insertSong(Song(
                id: nil, path: url.path, name: name,
                bpm: grid.bpm, durationSec: audio.durationSec,
                importedAt: Date()))

            // Cache decoded audio for later (waveform, re-extract, clip launch)
            decodedAudioCache[songId] = audio

            // Extract embeddings + insert loops
            importProgress = .extractingEmbeddings(name, 0, candidates.count)
            var inserted: [Loop] = []
            for (i, c) in candidates.enumerated() {
                let emb = await embeddingExtractor.extract(
                    from: audio, startSec: c.startSec, endSec: c.endSec)
                let loop = Loop(
                    id: nil, songId: songId, name: c.name,
                    startSec: c.startSec, endSec: c.endSec, bars: c.bars,
                    bpm: c.bpm, embedding: emb ?? [],
                    color: c.color, rating: Int(c.energy * 5))
                let id = try library.insertLoop(loop)
                var l = loop; l.id = id
                inserted.append(l)
                importProgress = .extractingEmbeddings(name, i + 1, candidates.count)
            }
            refreshLibrary()
            importProgress = .done
        } catch {
            importProgress = .failed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    func decodedAudio(for songId: Int64) async -> DecodedAudio? {
        if let cached = decodedAudioCache[songId] { return cached }
        // Re-decode if needed
        guard let song = songs.first(where: { $0.id == songId }) else { return nil }
        let url = URL(fileURLWithPath: song.path)
        guard let result = try? await decoder.decode(at: url) else { return nil }
        decodedAudioCache[songId] = result
        return result
    }

    func loops(forSong songId: Int64) -> [Loop] {
        loops.filter { $0.songId == songId }
    }

    // MARK: - Scene management

    func captureScene(name: String, slotPositions: [Int: CGPoint], cursorPosition: CGPoint) {
        var loopIdsDict: [Int: Int64] = [:]
        for (slot, id) in slotLoopIds.enumerated() {
            if let id { loopIdsDict[slot] = id }
        }
        // Merge in any positions passed by the caller (the UI) over the
        // controller's authoritative state, then persist the controller's
        // own copy so recall can restore it.
        for (slot, pos) in slotPositions {
            self.slotPositions[slot] = pos
        }
        self.cursorPosition = cursorPosition
        let scene = Scene(
            name: name,
            slotLoopIds: loopIdsDict,
            slotPositions: self.slotPositions.mapValues(CodableCGPoint.init),
            cursorPosition: CodableCGPoint(cursorPosition)
        )
        scenes.append(scene)
        saveScenes()
    }

    func deleteScene(_ scene: Scene) {
        scenes.removeAll { $0.id == scene.id }
        saveScenes()
    }

    /// Activate a scene: load every recorded loop into its slot, reset
    /// positions + cursor to the captured state.
    func recallScene(_ scene: Scene) {
        // Clear all current slots first so the scene loads fresh.
        for slot in 0..<6 where slotLoopIds[slot] != nil {
            clearSlot(slot)
        }
        for (slot, loopId) in scene.slotLoopIds {
            guard let loop = loops.first(where: { $0.id == loopId }) else { continue }
            launchLoop(loop, intoSlot: slot, solo: false)
        }
        // Restore prompt surface state from the scene.
        slotPositions = scene.slotPositions.mapValues { $0.cgPoint }
        cursorPosition = scene.cursorPosition.cgPoint
        // Recompute blend weights from the restored cursor + positions.
        updatePromptSurface(cursor: cursorPosition, slotPositions: slotPositions)
    }

    private func saveScenes() {
        // Persist to UserDefaults for now.
        if let data = try? JSONEncoder().encode(scenes) {
            UserDefaults.standard.set(data, forKey: "saved_scenes")
        }
    }

    private func loadScenes() {
        guard let data = UserDefaults.standard.data(forKey: "saved_scenes"),
              let decoded = try? JSONDecoder().decode([Scene].self, from: data) else { return }
        scenes = decoded
    }

    // MARK: - Loop preview + "generate on top"

    /// Preview a loop's raw audio through the engine's audio graph so it
    /// shares the output device with generation. Toggles off if the same
    /// loop is clicked again. The audio engine must be running for the
    /// preview node to be audible — we start it (without triggering a
    /// generation reset) if it's stopped, and mute the generation output
    /// so only the preview is heard.
    func previewLoop(_ loop: Loop) {
        if previewingLoopId == loop.id {
            // Same clip clicked again → stop preview
            stopPreview()
            return
        }
        stopPreview()
        Task { @MainActor in
            guard let audio = await decodedAudio(for: loop.songId) else { return }
            let sr = audio.sampleRate
            let ch = audio.channels
            let startSample = Int(loop.startSec * sr) * ch
            let endSample = min(Int(loop.endSec * sr) * ch, audio.samples.count)
            guard endSample > startSample else { return }
            let region = Array(audio.samples[startSample..<endSample])

            // Start the audio engine if it's not running so the preview
            // node is audible. Mute the bridge output so the user hears
            // only the preview, not any generation. We restore the mute
            // state when the preview stops.
            if !isPlaying {
                do { try audioEngine.start() } catch { print("preview audioEngine start: \(error)") }
                bridge.setMute(true)
            }
            audioEngine.schedulePreview(samples: region,
                                        sampleRate: sr,
                                        channels: AVAudioChannelCount(ch))
            previewingLoopId = loop.id
        }
    }

    func stopPreview() {
        audioEngine?.stopPreview()
        if previewingLoopId != nil && !isPlaying {
            // Only restore mute if we set it (i.e. generation wasn't playing)
            bridge.setMute(false)
            // If we started the audio engine just for the preview, stop it.
            audioEngine?.stop()
        }
        previewingLoopId = nil
    }

    /// "Continue from here" — prefill the engine with the clip's audio so
    /// generation continues from the clip's musical context. This encodes
    /// the clip via SpectroStream → feeds tokens through the transformer
    /// to populate KV cache → checkpoints → restarts the inference loop.
    /// Generation then resumes from where the clip ends.
    ///
    /// Crucially, we also load the clip's MusicCoCa embedding as slot 0's
    /// audio prompt and re-blend BEFORE prefilling. The runner's prefill
    /// uses `mask_musiccoca_during_prefill=false`, so the MusicCoCa
    /// conditioning steers the transformer during prefill. If we don't
    /// set it, the default "piano" tokens are used and the continuation
    /// drifts to a different genre. Setting the clip's embedding first
    /// makes the prefill + continuation match the clip's style.
    ///
    /// The prefill blocks for 2–5 s. We run it on a background thread
    /// wrapped in `autoreleasepool` so Metal/Obj-C temporary objects are
    /// drained and the main actor stays free to update the UI + log.
    func continueFromLoop(_ loop: Loop) {
        guard !isPrefilling else { return }
        stopPreview()
        isPrefilling = true
        prefillLog = ["Setting clip style…"]

        Task { @MainActor in
            guard let audio = await decodedAudio(for: loop.songId) else {
                isPrefilling = false
                prefillLog.append("Failed: no audio")
                return
            }
            let sr = audio.sampleRate
            let ch = audio.channels
            let startSample = Int(loop.startSec * sr) * ch
            let endSample = min(Int(loop.endSec * sr) * ch, audio.samples.count)
            guard endSample > startSample else {
                isPrefilling = false
                prefillLog.append("Failed: empty region")
                return
            }
            let region = Array(audio.samples[startSample..<endSample])

            // The runner hardcodes a 1s trim at each end (kTrimFrames=25
            // @ 25 Hz). If the clip is shorter than ~3s, the trimmed range
            // is too small or empty and the SpectroStream encoder can
            // crash. Refuse clips under 3s to be safe.
            let minSamples = Int(3.0 * sr) * ch  // 3 seconds interleaved
            if region.count < minSamples {
                isPrefilling = false
                prefillLog.append("Clip too short (\(String(format: "%.1f", Double(region.count) / Double(ch) / sr))s) — need ≥3s for prefill")
                return
            }

            // Step 1: Load the clip's stored MusicCoCa embedding as slot 0's
            // audio prompt. Guard against short/empty embeddings to avoid
            // a buffer overread in the bridge (which reads 768 floats).
            if loop.embedding.count >= 768 {
                loop.embedding.withUnsafeBufferPointer { embBuf in
                    bridge.setAudioEmbeddingForIndex(0, embedding: embBuf.baseAddress!)
                }
                // Clear other slots' audio prompts so leftover conditioning
                // from a previous load doesn't bleed into the continuation.
                for i in 1..<6 {
                    bridge.setAudioPromptSamplesForIndex(Int32(i), filename: "",
                                                           samples: [], count: 0)
                }
                // Set blend weight to solo slot 0, then force a re-blend
                // so the clip's MusicCoCa tokens are active before prefill.
                let weights: [Float] = [1, 0, 0, 0, 0, 0]
                weights.withUnsafeBufferPointer { wBuf in
                    bridge.setBlendWeights(wBuf.baseAddress!, count: 6)
                    _ = bridge.reblendMusiccocaTokens(withWeights: wBuf.baseAddress!,
                                                            count: 6,
                                                            pcaCoeffs: nil,
                                                            pcaCount: 0)
                }
                slotLabels[0] = loop.name
                slotLoopIds[0] = loop.id
                for i in 1..<6 {
                    slotLabels[i] = nil
                    slotLoopIds[i] = nil
                    slotPositions[i] = nil
                }
                blendWeights = weights
                activeSlot = 0
            } else {
                prefillLog.append("Warning: no clip embedding — style may drift")
            }

            prefillLog.append("Prefilling engine…")

            // Step 2: Prefill on a background thread wrapped in
            // autoreleasepool. MLX/Metal creates transient Obj-C objects
            // that need an autorelease pool to drain; without one (as on
            // a bare Task.detached thread) they leak and can eventually
            // crash. Capture `bridge` as a local let so we don't access
            // the @MainActor-isolated `self.bridge` from the background.
            let bridgeRef = bridge
            let sampleCount = Int32(region.count)
            let ok = await Task.detached(priority: .userInitiated) { [weak self] () -> Bool in
                autoreleasepool {
                    region.withUnsafeBufferPointer { buf -> Bool in
                        bridgeRef.prefillState(withSamples: buf.baseAddress!,
                                               sampleCount: sampleCount,
                                               logCallback: { line in
                            Task { @MainActor in
                                self?.prefillLog.append(line)
                            }
                        })
                    }
                }
            }.value

            isPrefilling = false
            if ok {
                prefillLog.append("Done — generation continues from clip")
                // The prefill already restarted the inference loop and
                // primed 3 frames into the ring buffer. Do NOT call
                // triggerReset — that would discard the prime frames and
                // cause a dropout. Just unmute, start the audio engine,
                // and let it pull the prefilled audio.
                bridge.setMute(false)
                guard !isPlaying else { return }
                isPlaying = true
                do { try audioEngine.start() } catch { print("post-prefill audioEngine start: \(error)") }
            } else {
                prefillLog.append("Prefill failed")
            }
        }
    }

    // MARK: - Delete

    func deleteSong(_ song: Song) {
        guard let id = song.id else { return }
        do {
            // Remove cached audio if present
            decodedAudioCache.removeValue(forKey: id)
            try library.deleteSong(id: id)
            refreshLibrary()
        } catch {
            print("deleteSong failed: \(error)")
        }
    }

    // MARK: - Performance / quality presets

    enum QualityPreset: String, CaseIterable, Codable, Identifiable {
        case performance  // lower topK/CFG → faster frames, less risk of underrun
        case balanced     // defaults from the model
        case quality      // higher CFG/topK → richer but more compute per frame
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    /// Apply a quality preset by adjusting sampling parameters that most
    /// affect per-frame compute. Higher topK = larger candidate set per
    /// token = more GPU work. Higher CFG = more guidance math. Both push
    /// `total_ms` toward the 40 ms real-time budget and risk underruns
    /// (audible corruption) on slower GPUs or under thermal throttle.
    func applyQualityPreset(_ preset: QualityPreset) {
        switch preset {
        case .performance:
            bridge.setTopK(40)
            bridge.setCfgMusiccoca(2.0)
            bridge.setCfgNotes(3.0)
            bridge.setCfgDrums(1.0)
            paramSnapshot.topK = 40
            paramSnapshot.cfgMusiccoca = 2.0
            paramSnapshot.cfgNotes = 3.0
            paramSnapshot.cfgDrums = 1.0
        case .balanced:
            bridge.setTopK(100)
            bridge.setCfgMusiccoca(3.0)
            bridge.setCfgNotes(5.0)
            bridge.setCfgDrums(1.0)
            paramSnapshot.topK = 100
            paramSnapshot.cfgMusiccoca = 3.0
            paramSnapshot.cfgNotes = 5.0
            paramSnapshot.cfgDrums = 1.0
        case .quality:
            bridge.setTopK(200)
            bridge.setCfgMusiccoca(5.0)
            bridge.setCfgNotes(7.0)
            bridge.setCfgDrums(2.0)
            paramSnapshot.topK = 200
            paramSnapshot.cfgMusiccoca = 5.0
            paramSnapshot.cfgNotes = 7.0
            paramSnapshot.cfgDrums = 2.0
        }
    }

    /// Real-time factor: 1.0 = exactly keeping pace, <1.0 = headroom,
    /// >1.0 = underrun territory (audio will corrupt). 40 ms budget per
    /// frame at 25 Hz.
    var realTimeFactor: Double {
        metrics.totalMs > 0 ? Double(metrics.totalMs) / 40.0 : 0
    }

    private func savePerfSettings() {
        let dict: [String: Any] = [
            "bufferSize": Int(bufferSize),
            "qualityPreset": qualityPreset.rawValue
        ]
        UserDefaults.standard.set(dict, forKey: "aevum_perf")
    }

    private func loadPerfSettings() {
        guard let dict = UserDefaults.standard.dictionary(forKey: "aevum_perf") else { return }
        if let bs = dict["bufferSize"] as? Int {
            bufferSize = UInt(bs)
        } else {
            bufferSize = 2048
        }
        if let qp = dict["qualityPreset"] as? String,
           let preset = QualityPreset(rawValue: qp) {
            qualityPreset = preset
        } else {
            qualityPreset = .balanced
        }
    }
}

// MARK: - Param snapshot (observable UI state)

struct ParamSnapshot: Equatable {
    var temperature: Float = 1.0
    var topK: Float = 100
    var cfgMusiccoca: Float = 3.0
    var cfgNotes: Float = 5.0
    var cfgDrums: Float = 1.0
    var unmaskWidth: Float = 0
    var seedRotation: Float = 0
    var volumeDb: Float = 0
    var drumless: Bool = false
    var onsetMode: XFOnsetMode = .masked
    var midiGate: Bool = false
    var bypass: Bool = false

    mutating func update(_ param: XFParam, value: Float) {
        switch param {
        case .temperature:  temperature = value
        case .topK:          topK = value
        case .cfgMusiccoca:  cfgMusiccoca = value
        case .cfgNotes:      cfgNotes = value
        case .cfgDrums:      cfgDrums = value
        case .unmaskWidth:   unmaskWidth = value
        case .seedRotation:  seedRotation = value
        case .volumeDb:      volumeDb = value
        case .drumless:      drumless = value > 0.5
        case .onsetMode:     onsetMode = value > 0.5 ? .unmasked : .masked
        case .midiGate:      midiGate = value > 0.5
        case .bypass:        bypass = value > 0.5
        default: break
        }
    }
}
