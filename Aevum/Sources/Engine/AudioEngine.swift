// AudioEngine.swift — AVAudioEngine output stage.
// Pulls stereo Float32 frames from EngineBridge on the audio thread.
// Also hosts a preview player node so raw clip audio can play through
// the same graph as generation (shared output device + volume).
// Target: 48 kHz, 2 channels, non-interleaved Float32 (matches MRT2).

import Foundation
import AVFAudio

final class AudioEngine {
    static let sampleRate: Double = 48000.0
    static let channels: AVAudioChannelCount = 2

    private let engine = AVAudioEngine()
    private(set) var sourceNode: AVAudioSourceNode?
    private(set) var previewNode: AVAudioPlayerNode?
    private(set) var format: AVAudioFormat?
    private(set) var isRunning = false

    weak var bridge: EngineBridge?

    // ─── Live output level tap ────────────────────────────────────────────
    // A lock-free SPSC ring buffer of per-column peak amplitudes, written
    // from the audio render thread and read by `LiveWaveformView` on the
    // main thread. Each "column" covers `columnSamples` frames (~10 ms),
    // so the ~360-entry ring holds ~3.6 s of scrolling history. The writer
    // accumulates samples into `tapAccum` until it has a full column, then
    // pushes the peak and resets. All atomics are relaxed — visualization
    // tolerates torn reads, and there's only one producer + one consumer.
    struct LevelTap {
        static let capacity = 360
        static let columnSamples = 480 // 10 ms @ 48 kHz
        var peaks: [Float] = [Float](repeating: 0, count: capacity) // 0..1 per column
        var writeIndex = 0
    }
    private var tap = LevelTap()
    private var tapAccum: Float = 0
    private var tapAccumCount: Int = 0

    /// Snapshot of the current peak ring for the UI. Returns (peaks, writeIndex).
    /// Copies under the assumption that a torn read just produces a briefly
    /// inconsistent frame — fine for a glowing waveform.
    func levelSnapshot() -> (peaks: [Float], writeIndex: Int) {
        (tap.peaks, tap.writeIndex)
    }

    // ─── Swift-side recording ─────────────────────────────────────────────
    // We capture directly in the render callback rather than using the
    // C++ engine's recording buffer. The C++ path's `recorded_samples_`
    // counter was observed returning 0 even after a 3s take (likely a
    // state/visibility issue across the Obj-C++ boundary); capturing in
    // Swift guarantees every rendered frame is recorded as long as the
    // audio engine is pulling. The buffer is a pre-allocated array
    // protected by a mutex; the render thread appends, the UI thread
    // exports + clears. 48 kHz stereo Float32 → 5 min cap = ~115 MB.
    //
    // Performance: the buffer is reserved to its max capacity at
    // startRecording() so the render-callback append never reallocs (a
    // realloc mid-take would spike CPU and could starve the 25 Hz
    // inference loop / Metal GPU work). The mutex is a lightweight
    // semaphore held only for the memcpy-bound append — microseconds.
    private var recBufL: [Float] = []
    private var recBufR: [Float] = []
    private var recWriteIdx: Int = 0
    private let recMutex = DispatchSemaphore(value: 1)
    private(set) var isSwiftRecording = false
    private static let recMaxSamples = 5 * 60 * 48_000 // 5 minutes @ 48 kHz

    func startSwiftRecording() {
        recMutex.wait()
        // Pre-allocate to full capacity once so the hot append in the
        // render callback is a bounds-checked store into existing
        // memory — no growth, no realloc, no CPU spike mid-performance.
        recBufL = [Float](repeating: 0, count: Self.recMaxSamples)
        recBufR = [Float](repeating: 0, count: Self.recMaxSamples)
        recWriteIdx = 0
        isSwiftRecording = true
        recMutex.signal()
    }

    func stopSwiftRecording() {
        recMutex.wait()
        isSwiftRecording = false
        recMutex.signal()
    }

    /// Returns (left, right) arrays of length `recWriteIdx`. The internal
    /// buffer is cleared (re-allocated empty) so a subsequent take starts
    /// fresh.
    func readAndClearRecording() -> (left: [Float], right: [Float]) {
        recMutex.wait()
        let n = recWriteIdx
        let l = Array(recBufL.prefix(n))
        let r = Array(recBufR.prefix(n))
        recBufL.removeAll(keepingCapacity: false)
        recBufR.removeAll(keepingCapacity: false)
        recWriteIdx = 0
        recMutex.signal()
        return (l, r)
    }

    var recordedSampleCount: Int {
        recMutex.wait()
        let n = recWriteIdx
        recMutex.signal()
        return n
    }

    private func tapPushPeak(_ p: Float) {
        tap.peaks[tap.writeIndex] = p
        tap.writeIndex = (tap.writeIndex + 1) % LevelTap.capacity
    }

    init(bridge: EngineBridge) {
        self.bridge = bridge
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: Self.sampleRate,
                                channels: Self.channels,
                                interleaved: false)
        self.format = fmt

        guard let fmt else { return }

        // Generation source node — pulls from the bridge on the audio thread.
        let node = AVAudioSourceNode(format: fmt) { [weak self]
            (_: UnsafeMutablePointer<ObjCBool>,
             _: UnsafePointer<AudioTimeStamp>,
             frameCount: AVAudioFrameCount,
             bufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus in
            self?.render(into: bufferList, frameCount: frameCount) ?? noErr
        }
        self.sourceNode = node

        // Preview player node — schedules raw clip PCM buffers. Routes
        // through the same mainMixerNode so it shares the output device
        // and any downstream processing with the generation path.
        let preview = AVAudioPlayerNode()
        preview.volume = 0.85
        self.previewNode = preview

        engine.attach(node)
        engine.attach(preview)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        engine.connect(preview, to: engine.mainMixerNode, format: fmt)
    }

    func start() throws {
        guard !isRunning else { return }
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        previewNode?.stop()
        engine.stop()
        isRunning = false
    }

    // MARK: - Preview (raw clip playback through the engine graph)

    /// Schedule a loop's raw PCM for preview playback. The buffer loops
    /// indefinitely so the user can hear the clip repeat while deciding
    /// whether to generate on top of it. Call `stopPreview()` to stop.
    /// `samples` is interleaved stereo Float32 at 48 kHz.
    func schedulePreview(samples: [Float], sampleRate: Double, channels: AVAudioChannelCount) {
        guard let previewNode, isRunning else { return }
        previewNode.stop()
        guard !samples.isEmpty else { return }

        // If the source sample rate differs from the engine's, resample
        // via AVAudioConverter. The decoder already targets 48 kHz so
        // this is usually a no-op, but we handle the mismatch case so
        // preview doesn't play at the wrong speed.
        let frameCount = AVAudioFrameCount(samples.count / Int(channels))
        guard frameCount > 0 else { return }

        let srcFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: sampleRate,
                                      channels: channels,
                                      interleaved: true)
        let dstFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: Self.sampleRate,
                                      channels: Self.channels,
                                      interleaved: false)
        guard let srcFormat, let dstFormat else { return }

        // We need a buffer in the destination format for the player node
        // (non-interleaved). If formats match (both 48k stereo), just
        // de-interleave. Otherwise convert.
        let dstBuffer: AVAudioPCMBuffer
        if sampleRate == Self.sampleRate && channels == Self.channels {
            // De-interleave [L,R,L,R,...] → two channel buffers
            dstBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: frameCount)!
            dstBuffer.frameLength = frameCount
            let l = dstBuffer.floatChannelData![0]
            let r = dstBuffer.floatChannelData![1]
            for i in 0..<Int(frameCount) {
                l[i] = samples[i * 2]
                r[i] = samples[i * 2 + 1]
            }
        } else {
            // Convert via AVAudioConverter
            guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else { return }
            srcBuffer.frameLength = frameCount
            srcBuffer.floatChannelData![0].update(from: samples, count: samples.count)
            let converter = AVAudioConverter(from: srcFormat, to: dstFormat)
            guard let converter else { return }
            let outFrameCap = AVAudioFrameCount(Double(frameCount) * Self.sampleRate / sampleRate) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: outFrameCap) else { return }
            var error: NSError?
            var converted = false
            converter.convert(to: out, error: &error) { _, status in
                status.pointee = .endOfStream
                converted = true
                return srcBuffer
            }
            if let _ = error { return }
            dstBuffer = out
        }

        // Schedule the buffer to loop indefinitely. The user clicks
        // "Continue from here" or clicks the clip again to stop it.
        previewNode.scheduleBuffer(dstBuffer, at: nil, options: .loops, completionHandler: nil)
        previewNode.play()
    }

    func stopPreview() {
        previewNode?.stop()
    }

    private func render(into bufferList: UnsafeMutablePointer<AudioBufferList>,
                        frameCount: AVAudioFrameCount) -> OSStatus {
        guard let bridge else { return noErr }
        let blp = UnsafeMutableAudioBufferListPointer(bufferList)
        // Expect 2 non-interleaved buffers (L, R).
        guard blp.count == 2,
              let leftData = blp[0].mData,
              let rightData = blp[1].mData else {
            return noErr
        }
        let left = leftData.assumingMemoryBound(to: Float.self)
        let right = rightData.assumingMemoryBound(to: Float.self)
        _ = bridge.readAudioStereoL(left, r: right, count: UInt(frameCount))

        // Level tap: accumulate the max |sample| across both channels into
        // ~10 ms columns, then push each finished column to the ring.
        let n = Int(frameCount)
        var i = 0
        while i < n {
            let remaining = LevelTap.columnSamples - tapAccumCount
            let take = min(remaining, n - i)
            var localMax = tapAccum
            for j in 0..<take {
                let l = abs(left[i + j])
                let r = abs(right[i + j])
                let m = l > r ? l : r
                if m > localMax { localMax = m }
            }
            tapAccum = localMax
            tapAccumCount += take
            i += take
            if tapAccumCount >= LevelTap.columnSamples {
                tapPushPeak(min(1, tapAccum))
                tapAccum = 0
                tapAccumCount = 0
            }
        }

        // Swift-side recording: store the rendered frame into the
        // pre-allocated rec buffer. Captured here so recording tracks the
        // actual audio output. The buffer was reserved to full capacity
        // at startSwiftRecording(), so this is a memcpy into existing
        // memory — no realloc, no GPU/CPU contention with the inference
        // loop. Indexed store avoids Array's growth bookkeeping.
        if isSwiftRecording {
            recMutex.wait()
            let room = Self.recMaxSamples - recWriteIdx
            if room >= n {
                recBufL.withUnsafeMutableBufferPointer { lb in
                    left.withUnsafeBufferPointer { src in
                        memcpy(lb.baseAddress! + recWriteIdx, src.baseAddress, n * 4)
                    }
                }
                recBufR.withUnsafeMutableBufferPointer { rb in
                    right.withUnsafeBufferPointer { src in
                        memcpy(rb.baseAddress! + recWriteIdx, src.baseAddress, n * 4)
                    }
                }
                recWriteIdx += n
            }
            recMutex.signal()
        }
        return noErr
    }
}
