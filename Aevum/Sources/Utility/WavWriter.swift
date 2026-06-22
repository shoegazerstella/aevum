import Foundation

struct WavWriter {
    static func write(_ samples: [Float], sampleRate: Double, channels: Int, to url: URL) throws {
        let frameCount = samples.count / channels
        let byteRate = Int(sampleRate) * channels * 2
        let blockAlign = channels * 2
        let dataSize = samples.count * 2
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
        data.append(contentsOf: withUnsafeBytes(of: Int16(1)) { Data($0) })  // PCM
        data.append(contentsOf: withUnsafeBytes(of: Int16(channels)) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(sampleRate)) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(byteRate)) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int16(blockAlign)) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int16(16)) { Data($0) }) // bits per sample
        // data chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: Int32(dataSize)) { Data($0) })
        // Convert Float32 [-1..1] to Int16
        var int16Samples = [Int16](repeating: 0, count: samples.count)
        for i in samples.indices {
            let clamped = max(-1, min(1, samples[i]))
            int16Samples[i] = Int16(clamped * Float(Int16.max))
        }
        data.append(contentsOf: withUnsafeBytes(of: int16Samples) { Data($0) })
        try data.write(to: url)
    }
}
