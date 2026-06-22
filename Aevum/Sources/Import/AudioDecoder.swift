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
