// AudioDecoder.swift — Decode any audio file to Float32 stereo at 48 kHz.
// Uses AVAssetReader for format-agnostic decoding (wav/mp3/aac/flac/m4a).

import Foundation
import AVFoundation

enum AudioDecodeError: Error {
    case noAudioTrack
    case readerSetupFailed(String)
    case decodeFailed(String)
}

struct DecodedAudio {
    let samples: [Float]      // interleaved stereo (L,R,L,R,...)
    let sampleRate: Double
    let channels: Int
    let durationSec: Double
}

final class AudioDecoder {
    static let targetSampleRate: Double = 48000.0
    static let targetChannels: Int = 2

    func decode(at url: URL) async throws -> DecodedAudio {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else { throw AudioDecodeError.noAudioTrack }

        let formatDesc = try await track.load(.formatDescriptions)
        var srcChannels = 2
        var srcRate = Self.targetSampleRate
        if let desc = formatDesc.first {
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                srcChannels = Int(asbd.pointee.mChannelsPerFrame)
                srcRate = asbd.pointee.mSampleRate
            }
        }

        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: Self.targetSampleRate,
                                          channels: AVAudioChannelCount(Self.targetChannels),
                                          interleaved: true)!
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.targetSampleRate,
            AVNumberOfChannelsKey: Self.targetChannels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        reader.startReading()

        var samples: [Float] = []
        let capacity = Int(Self.targetSampleRate * 600) // cap at 10 min for safety
        samples.reserveCapacity(min(capacity, 48000 * 60))

        while reader.status == .reading {
            if let buf = output.copyNextSampleBuffer() {
                let block = CMSampleBufferGetDataBuffer(buf)
                if let block {
                    let length = CMBlockBufferGetDataLength(block)
                    let count = length / 4 // Float32
                    var temp = [Float](repeating: 0, count: count)
                    temp.withUnsafeMutableBufferPointer { bp in
                        CMBlockBufferCopyDataBytes(block, atOffset: 0,
                                                   dataLength: length, destination: bp.baseAddress!)
                    }
                    samples.append(contentsOf: temp)
                }
                CMSampleBufferInvalidate(buf)
            }
        }
        if reader.status == .failed {
            throw AudioDecodeError.decodeFailed(reader.error?.localizedDescription ?? "unknown")
        }
        _ = srcChannels; _ = srcRate
        let dur = Double(samples.count / Self.targetChannels) / Self.targetSampleRate
        return DecodedAudio(samples: samples,
                            sampleRate: Self.targetSampleRate,
                            channels: Self.targetChannels,
                            durationSec: dur)
    }

    /// Produce a 16 kHz mono Float32 buffer for a region of a decoded song,
    /// suitable for MusicCoCa's `audio_preprocessor.tflite`.
    ///
    /// MusicCoCa expects 16 kHz mono (config: sample_rate=16000,
    /// clip_length=10.0 → 160000 samples). The C++ engine does a raw `memcpy`
    /// into the preprocessor's fixed input tensor with no resample/downmix,
    /// so feeding the engine's native 48 kHz interleaved stereo produces a
    /// garbage embedding (3×-too-fast, L/R-alternating signal) and morphing
    /// sounds generic/random. This downmixes + resamples to 16k and always
    /// returns exactly 160000 samples (zero-padded if the clip is shorter
    /// than 10 s), matching the collider app's fixed-buffer approach.
    func monoSamples16k(from audio: DecodedAudio, startSec: Double, endSec: Double) -> [Float] {
        let sr = audio.sampleRate
        let ch = audio.channels
        let startSample = Int(startSec * sr) * ch
        let endSample = min(Int(endSec * sr) * ch, audio.samples.count)
        guard endSample > startSample else {
            return [Float](repeating: 0, count: 160000)
        }

        // Downmix interleaved stereo → mono.
        let region = Array(audio.samples[startSample..<endSample])
        var mono: [Float]
        if ch == 2 {
            let n = region.count / 2
            mono = [Float](repeating: 0, count: n)
            for i in 0..<n {
                mono[i] = (region[i * 2] + region[i * 2 + 1]) * 0.5
            }
        } else {
            mono = region
        }

        let target: Double = 16000
        let outFrames = 160000 // 10 s @ 16 kHz — always fill the preprocessor's input
        var out = [Float](repeating: 0, count: outFrames)

        if abs(sr - target) < 1 {
            // Already 16 kHz — copy what we have, zero-pad the rest.
            let n = min(mono.count, outFrames)
            for i in 0..<n { out[i] = mono[i] }
            return out
        }

        // Linear resample 48 kHz → 16 kHz (deterministic; the style
        // embedding is insensitive to anti-alias filter quality). This
        // avoids AVAudioConverter's intermittent failures on some clips.
        let ratio = target / sr
        let nOut = Int(Double(mono.count) * ratio)
        for i in 0..<min(nOut, outFrames) {
            let pos = Double(i) / ratio
            let idx = Int(pos)
            let frac = Float(pos - Double(idx))
            if idx + 1 < mono.count {
                out[i] = mono[idx] * (1 - frac) + mono[idx + 1] * frac
            } else if idx < mono.count {
                out[i] = mono[idx]
            }
        }
        return out
    }

    /// Extract a mono Float32 buffer at a target analysis rate.
    func monoForAnalysis(_ decoded: DecodedAudio, targetRate: Double) -> [Float] {
        // Downmix stereo → mono
        let ch = decoded.channels
        let n = decoded.samples.count / ch
        var mono = [Float](repeating: 0, count: n)
        if ch == 2 {
            for i in 0..<n {
                mono[i] = (decoded.samples[i * 2] + decoded.samples[i * 2 + 1]) * 0.5
            }
        } else {
            for i in 0..<n { mono[i] = decoded.samples[i] }
        }
        // Resample
        if abs(decoded.sampleRate - targetRate) > 1 {
            let ratio = targetRate / decoded.sampleRate
            let outCount = Int(Double(n) * ratio)
            var out = [Float](repeating: 0, count: outCount)
            for i in 0..<outCount {
                let pos = Double(i) / ratio
                let idx = Int(pos)
                let frac = Float(pos - Double(idx))
                if idx + 1 < n { out[i] = mono[idx] * (1 - frac) + mono[idx + 1] * frac }
                else if idx < n { out[i] = mono[idx] }
            }
            return out
        }
        return mono
    }
}
