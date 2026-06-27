// ModelDownloader.swift — first-run model fetcher.
//
// Downloads the manifest from HuggingFace sequentially with live progress,
// verifies each file's byte size, and moves it into ~/.cache/magenta-rt-v2.
// Sequential (not parallel) keeps bandwidth sane and lets one failure
// abort cleanly. URLSession follows the HF 302→CDN redirect automatically.
//
// The delegate queue is the main queue, so delegate callbacks run on the
// main actor and can update @Published state directly.

import Foundation
import Combine

@MainActor
final class ModelDownloader: ObservableObject {

    enum Status: Equatable {
        case idle
        case downloading
        case done
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var currentFile: String = ""
    @Published private(set) var completedFiles: Int = 0
    @Published private(set) var currentFileBytes: Int64 = 0
    @Published private(set) var currentFileTotal: Int64 = 0
    @Published private(set) var totalDownloadedBytes: Int64 = 0

    let totalFiles: Int
    let totalBytes: Int64

    private var queue: [ModelAssets.File] = []
    private var queueIndex: Int = 0
    private var session: URLSession!
    private let delegate = DownloaderDelegate()
    private var currentTask: URLSessionDownloadTask?
    private var currentDest: URL?
    private var fileStartBytes: Int64 = 0   // totalDownloadedBytes at file start

    init() {
        totalFiles = ModelAssets.manifest.count
        totalBytes = ModelAssets.totalBytes
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        // Delegate callbacks fire on main → safe to touch @Published directly.
        let dq = OperationQueue()
        dq.underlyingQueue = .main
        dq.maxConcurrentOperationCount = 1
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: dq)
        delegate.onWrite = { [weak self] written, total in
            self?.handleWrite(totalWritten: written, totalExpected: total)
        }
        delegate.onComplete = { [weak self] location in
            self?.handleFinish(at: location)
        }
        delegate.onError = { [weak self] err in
            self?.handleError(err)
        }
    }

    var isReady: Bool {
        if case .idle = status { return true }
        if case .failed = status { return true }
        return false
    }

    func start() {
        guard status != .downloading else { return }
        queue = ModelAssets.missingFiles()
        if queue.isEmpty {
            status = .done
            return
        }
        queueIndex = 0
        completedFiles = ModelAssets.manifest.count - queue.count
        totalDownloadedBytes = ModelAssets.totalBytes - queue.reduce(0) { $0 + $1.expectedSize }
        status = .downloading
        startCurrent()
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        status = .idle
    }

    // Bytes already on disk before this run — so the progress bar reflects
    // the whole 1.8 GB, not just what's left.
    private func startCurrent() {
        guard queueIndex < queue.count else {
            status = .done
            return
        }
        let file = queue[queueIndex]
        currentFile = file.relativePath
        currentFileTotal = file.expectedSize
        currentFileBytes = 0
        fileStartBytes = totalDownloadedBytes

        let dest = ModelAssets.baseDir.appendingPathComponent(file.relativePath)
        currentDest = dest
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        // Remove any partial/wrong-sized file first.
        try? FileManager.default.removeItem(at: dest)

        let task = session.downloadTask(with: ModelAssets.url(for: file))
        currentTask = task
        task.resume()
    }

    private func handleWrite(totalWritten: Int64, totalExpected: Int64) {
        currentFileBytes = totalWritten
        if totalExpected > 0 { currentFileTotal = totalExpected }
        totalDownloadedBytes = fileStartBytes + totalWritten
    }

    private func handleFinish(at location: URL) {
        guard let dest = currentDest else { return }
        do {
            // Verify size against the manifest.
            let attrs = try FileManager.default.attributesOfItem(atPath: location.path)
            let actual = (attrs[.size] as? NSNumber)?.int64Value ?? -1
            let expected = queue[queueIndex].expectedSize
            if actual != expected {
                throw NSError(domain: "Aevum.ModelDownloader", code: 2,
                              userInfo: [NSLocalizedDescriptionKey:
                                "Size mismatch for \(currentFile): got \(actual) bytes, expected \(expected)"])
            }
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            completedFiles += 1
            queueIndex += 1
            currentTask = nil
            startCurrent()
        } catch {
            try? FileManager.default.removeItem(at: location)
            handleError(error)
        }
    }

    private func handleError(_ error: Error) {
        currentTask?.cancel()
        currentTask = nil
        status = .failed(error.localizedDescription)
    }
}

// Thin delegate that forwards to closures. Runs on the main queue
// (see OperationQueue setup above), so the closures are main-actor safe.
private final class DownloaderDelegate: NSObject, URLSessionDownloadDelegate {
    var onWrite: ((Int64, Int64) -> Void)?
    var onComplete: ((URL) -> Void)?
    var onError: ((Error) -> Void)?

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onWrite?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Move the file ourselves (don't return it — URLSession would delete it).
        onComplete?(location)
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // `didFinishDownloadingTo` is the success path; this fires on failure
        // (or after success with error == nil, which we ignore).
        if let error = error {
            onError?(error)
        }
    }
}
