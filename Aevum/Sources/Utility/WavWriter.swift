import Foundation

// WavWriter.swift — Writes 32-bit float WAV files (full quality, no
// quantization). Used for performance recordings. IEEE-754 float format
// code (0x0003) is widely supported (Logic, Ableton, Audacity, ffmpeg).
struct WavWriter {
    static func write(_ samples: [Float], sampleRate: Double, channels: Int, to url: URL) throws {
        let frameCount = samples.count / channels
        let bytesPerSample = 4
        let blockAlign = channels * bytesPerSample
        let byteRate = Int(sampleRate) * blockAlign
        let dataSize = samples.count * bytesPerSample
        let headerSize = 44
        let totalSize = headerSize + dataSize

        var data = Data()
        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: withUnsafeBytes(of: Int32(totalSize - 8)) { Data($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        // fmt chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.append(contentsOf: withUnsafeBytes(of: Int32(16)) { Data($0) }) // chunk size
        data.append(contentsOf: withUnsafeBytes(of: Int16(3)) { Data($0) })  // IEEE float
        data.append(contentsOf: withUnsafeBytes(of: Int16(channels)) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(sampleRate)) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(byteRate)) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int16(blockAlign)) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int16(32)) { Data($0) }) // bits per sample
        // data chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: Int32(dataSize)) { Data($0) })
        // Float32 samples — raw bytes, no quantization.
        samples.withUnsafeBufferPointer { buf in
            buf.baseAddress?.withMemoryRebound(to: UInt8.self, capacity: buf.count * 4) { bytes in
                data.append(bytes, count: buf.count * 4)
            }
        }
        try data.write(to: url)
    }
}
