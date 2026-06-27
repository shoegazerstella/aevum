// ModelAssets.swift — locations and manifest for the first-run model download.
//
// Aevum ships without the ~1.8 GB of model weights (too big to bundle).
// On first launch the app downloads them from HuggingFace into
// ~/.cache/magenta-rt-v2, mirroring what `mrt models init` +
// `mrt models download mrt2_small` produce. Existing users who already
// ran those commands won't trigger a re-download — `isPresent` checks
// for the key files.
//
// URLs: https://huggingface.co/google/magenta-realtime-2/resolve/main/<path>
// HF responds 302 → signed CDN URL; URLSession follows redirects.

import Foundation

enum ModelAssets {
    static let repoName = "google/magenta-realtime-2"
    static let resolveBase = "https://huggingface.co/\(repoName)/resolve/main"

    static var baseDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/magenta-rt-v2")
    }

    static var modelDir: URL { baseDir.appendingPathComponent("models/mrt2_small") }
    static var resourceDir: URL { baseDir.appendingPathComponent("resources") }

    static var modelPath: String {
        modelDir.appendingPathComponent("mrt2_small.mlxfn").path
    }
    static var resourcePath: String { resourceDir.path }
    static var spectrostreamPath: String {
        resourceDir.appendingPathComponent("spectrostream/spectrostream_encoder.mlxfn").path
    }

    struct File: Hashable {
        let relativePath: String   // e.g. "models/mrt2_small/mrt2_small.mlxfn"
        let expectedSize: Int64    // bytes; used to verify/guard partial files
    }

    // Mirrors the union of `mrt models init` (musiccoca + spectrostream) and
    // `mrt models download mrt2_small`. Sizes captured 2026-06-27 from the HF API.
    static let manifest: [File] = [
        // musiccoca resources
        File(relativePath: "resources/musiccoca/audio_preprocessor.tflite",          expectedSize: 8_729_640),
        File(relativePath: "resources/musiccoca/mapper.tflite",                      expectedSize: 86_166_664),
        File(relativePath: "resources/musiccoca/music_encoder.tflite",               expectedSize: 370_935_584),
        File(relativePath: "resources/musiccoca/pretrained_vector_quantizer.tflite", expectedSize: 72_422_108),
        File(relativePath: "resources/musiccoca/spm.model",                          expectedSize: 517_448),
        File(relativePath: "resources/musiccoca/text_encoder.tflite",                expectedSize: 418_674_324),
        // spectrostream resources
        File(relativePath: "resources/spectrostream/decoder.safetensors",            expectedSize: 209_853_216),
        File(relativePath: "resources/spectrostream/encoder.safetensors",            expectedSize: 37_013_392),
        File(relativePath: "resources/spectrostream/quantizer.safetensors",          expectedSize: 67_108_984),
        File(relativePath: "resources/spectrostream/spectrostream_encoder.mlxfn",    expectedSize: 104_319_983),
        // mrt2_small model
        File(relativePath: "models/mrt2_small/mrt2_small.mlxfn",                     expectedSize: 455_654_550),
        File(relativePath: "models/mrt2_small/mrt2_small_state.safetensors",         expectedSize: 8_676_998),
    ]

    static var totalBytes: Int64 {
        manifest.reduce(0) { $0 + $1.expectedSize }
    }

    // Returns the subset of manifest files missing or wrong-sized on disk.
    static func missingFiles() -> [File] {
        var fm = FileManager.default
        var out: [File] = []
        for f in manifest {
            let url = baseDir.appendingPathComponent(f.relativePath)
            guard fm.fileExists(atPath: url.path) else {
                out.append(f)
                continue
            }
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? -1
            if size != f.expectedSize {
                out.append(f)
            }
        }
        return out
    }

    static var isPresent: Bool { missingFiles().isEmpty }

    static func url(for file: File) -> URL {
        URL(string: "\(resolveBase)/\(file.relativePath)")!
    }
}
