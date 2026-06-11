import Foundation

/// Downloads ggml whisper models from Hugging Face into Application Support.
final class ModelManager: NSObject, URLSessionDownloadDelegate {
    private var onProgress: ((Double) -> Void)?
    private var onDone: ((Result<URL, Error>) -> Void)?
    private var destination: URL?
    private var session: URLSession?

    static func localURL(for model: WhisperModel) -> URL {
        Config.modelsDir.appendingPathComponent(model.file)
    }

    static func isDownloaded(_ model: WhisperModel) -> Bool {
        let url = localURL(for: model)
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        else { return false }
        return size > model.sizeMB * 1_000_000 / 2  // guard against truncated downloads
    }

    func download(_ model: WhisperModel,
                  progress: @escaping (Double) -> Void,
                  completion: @escaping (Result<URL, Error>) -> Void) {
        onProgress = progress
        onDone = completion
        destination = ModelManager.localURL(for: model)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        session.downloadTask(with: model.downloadURL).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let destination else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            onDone?(.success(destination))
        } catch {
            onDone?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { onDone?(.failure(error)) }
        session.finishTasksAndInvalidate()
    }
}
