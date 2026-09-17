import CryptoKit
import Foundation

final class ModelManager: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var completion: ((String?) -> Void)?
    private var lastBytes: Int64 = 0
    private var hashing = false
    private var generation: UInt64 = 0
    private let io = DispatchQueue(label: "app.malgyeol.model-io", qos: .userInitiated)

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpShouldUsePipelining = false
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 30
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func sizeLooksReady() -> Bool {
        let url = MalgyeolInfo.modelURLOnDisk
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue else {
            return false
        }
        return size == MalgyeolInfo.modelBytes
    }

    func verifyHashOffMain(completion: @escaping (Bool) -> Void) {
        if hashing {
            return
        }
        hashing = true
        let url = MalgyeolInfo.modelURLOnDisk
        io.async { [weak self] in
            let ok = self?.sha256(url) == MalgyeolInfo.modelSHA256
            DispatchQueue.main.async {
                self?.hashing = false
                completion(ok)
            }
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        let cb = completion
        completion = nil
        cb?("cancelled")
    }

    func download(completion: @escaping (String?) -> Void) {
        let gen = generation
        io.async { [weak self] in
            guard let self else { return }
            if self.generation != gen {
                DispatchQueue.main.async { completion("cancelled") }
                return
            }
            if self.sizeLooksReady(), self.sha256(MalgyeolInfo.modelURLOnDisk) == MalgyeolInfo.modelSHA256 {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async {
                guard self.generation == gen else {
                    completion("cancelled")
                    return
                }
                self.startDownload(completion: completion)
            }
        }
    }

    private func startDownload(completion: @escaping (String?) -> Void) {
        self.completion = completion
        let dest = MalgyeolInfo.modelURLOnDisk
        let dir = dest.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var req = URLRequest(url: MalgyeolInfo.modelURL)
        req.httpMethod = "GET"
        req.setValue("Malgyeol/0.1", forHTTPHeaderField: "User-Agent")
        guard MalgyeolInfo.urlAllowed(MalgyeolInfo.modelURL) else {
            finish("모델 주소가 HTTPS 허용 목록이 아닙니다")
            return
        }
        task = session.downloadTask(with: req)
        task?.resume()
        malgyeolLog("model download start \(MalgyeolInfo.modelURL.absoluteString)")
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url else {
            completionHandler(nil)
            return
        }
        if !MalgyeolInfo.urlAllowed(url) {
            malgyeolLog("blocked redirect \(url.absoluteString)")
            completionHandler(nil)
            return
        }
        malgyeolLog("redirect \(response.statusCode) -> \(url.host ?? "") https=\(url.scheme ?? "")")
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lastBytes = totalBytesWritten
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(MalgyeolInfo.modelBytes)
        let frac = min(1, Double(totalBytesWritten) / Double(expected))
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .malgyeolDownload,
                object: nil,
                userInfo: ["frac": frac, "written": totalBytesWritten, "expected": expected]
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard downloadTask === task else {
            malgyeolLog("stale download finish ignored")
            return
        }
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            finish("다운로드 HTTP \(http.statusCode)")
            return
        }
        if let url = downloadTask.currentRequest?.url ?? downloadTask.originalRequest?.url, !MalgyeolInfo.urlAllowed(url) {
            finish("최종 다운로드 주소가 허용 목록이 아닙니다")
            return
        }
        let dest = MalgyeolInfo.modelURLOnDisk
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            let size = (try FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.intValue ?? 0
            if size != MalgyeolInfo.modelBytes {
                try FileManager.default.removeItem(at: dest)
                finish("모델 크기 불일치 (\(size) ≠ \(MalgyeolInfo.modelBytes)). 파일을 버렸습니다.")
                return
            }
            let hash = sha256(dest)
            if hash != MalgyeolInfo.modelSHA256 {
                try FileManager.default.removeItem(at: dest)
                finish("모델 무결성 검사 실패 (sha256 불일치). 파일을 버리고 다시 받으세요.")
                return
            }
            let host = downloadTask.response?.url?.host ?? downloadTask.currentRequest?.url?.host ?? "?"
            malgyeolLog("model ready bytes=\(size) sha256=\(hash) host=\(host)")
            finish(nil)
        } catch {
            finish("모델 저장 실패: \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === self.task || self.task == nil else { return }
        if let error {
            let nse = error as NSError
            if nse.code == NSURLErrorCancelled {
                return
            }
            finish("다운로드 실패: \(error.localizedDescription)")
        }
    }

    private func finish(_ error: String?) {
        task = nil
        let cb = completion
        completion = nil
        cb?(error)
    }

    private func sha256(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try? handle.read(upToCount: 1024 * 1024)
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension Notification.Name {
    static let malgyeolDownload = Notification.Name("malgyeol.download")
}
