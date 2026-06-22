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
        return noErr
    }
}
