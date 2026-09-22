import Foundation

struct TranscribeError: Error {
    let message: String
}

/// The queue owns the pipe protocol; the lock only protects cancellation/launch.
final class Transcriber: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.ipta.transcriber", qos: .userInitiated)
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var proc: Process?
    private var worker: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var idleToken: UInt64 = 0
    private let cliURL: URL?
    private let workerURL: URL?
    private let modelURL: URL
    private let timeout: TimeInterval
    private let idleTimeout: TimeInterval

    init(cliURL: URL? = nil, workerURL: URL? = nil, modelURL: URL? = nil, timeout: TimeInterval = 180, idleTimeout: TimeInterval = 90) {
        let helpers = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers")
        let cli = helpers.appendingPathComponent("whisper-cli")
        self.cliURL = cliURL ?? (FileManager.default.isExecutableFile(atPath: cli.path)
            ? cli : Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/whisper-cli"))
        self.workerURL = workerURL ?? helpers.appendingPathComponent("ipta-transcriber")
        self.modelURL = modelURL ?? MalgyeolInfo.modelURLOnDisk
        self.timeout = timeout
        self.idleTimeout = idleTimeout
    }

    deinit {
        if let proc, proc.isRunning { proc.terminate() }
        try? input?.close()
    }

    func cancel() {
        lock.lock()
        generation &+= 1
        if let proc, proc.isRunning { proc.terminate() }
        proc = nil
        lock.unlock()
        queue.async { self.releaseWorker() }
    }

    /// Start loading while the user records. No microphone data leaves the app.
    func prepare() {
        let job = currentGeneration()
        queue.async {
            guard self.isCurrent(job) else { return }
            self.idleToken &+= 1
            _ = self.ensureWorker(job: job)
            self.scheduleRelease()
        }
    }

    func transcribe(wav: URL, completion: @escaping (Result<String, TranscribeError>) -> Void) {
        let job = currentGeneration()
        queue.async {
            guard self.isCurrent(job) else { return }
            self.idleToken &+= 1
            guard FileManager.default.fileExists(atPath: self.modelURL.path) else {
                completion(.failure(TranscribeError(message: "모델 파일이 없습니다. 창에서 모델을 받으세요.")))
                return
            }
            if self.ensureWorker(job: job), let worker = self.worker {
                let deadline = self.watchdog(worker)
                defer { deadline.cancel() }
                do {
                    let data = try JSONSerialization.data(withJSONObject: ["wav": wav.path])
                    try self.input?.write(contentsOf: data + Data([10]))
                    if let reply = try self.readReply(), let text = reply["text"] as? String,
                       self.isCurrent(job) {
                        self.scheduleRelease()
                        completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
                        return
                    }
                } catch { /* Broken worker falls back to the existing file-based CLI. */ }
                deadline.cancel()
                self.releaseWorker()
            }
            guard self.isCurrent(job) else { return }
            let result = self.runCLI(wav: wav, job: job)
            if self.isCurrent(job) { completion(result) }
        }
    }

    private func currentGeneration() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    private func isCurrent(_ job: UInt64) -> Bool { currentGeneration() == job }

    private func launch(_ process: Process, job: UInt64) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation == job else { return false }
        try process.run()
        proc = process
        return true
    }

    private func watchdog(_ process: Process) -> DispatchWorkItem {
        let work = DispatchWorkItem { [weak self, weak process] in
            guard let self, let process else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            if self.proc === process, process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: work)
        return work
    }

    private func ensureWorker(job: UInt64) -> Bool {
        guard isCurrent(job) else { return false }
        if let worker, worker.isRunning { return true }
        releaseWorker()
        guard let workerURL, FileManager.default.isExecutableFile(atPath: workerURL.path),
              FileManager.default.fileExists(atPath: modelURL.path) else { return false }
        let process = Process()
        let incoming = Pipe(), outgoing = Pipe()
        process.executableURL = workerURL
        process.arguments = [modelURL.path]
        process.standardInput = incoming
        process.standardOutput = outgoing
        process.standardError = FileHandle.nullDevice
        do {
            guard try launch(process, job: job) else { return false }
            worker = process
            input = incoming.fileHandleForWriting
            output = outgoing.fileHandleForReading
            let deadline = watchdog(process)
            defer { deadline.cancel() }
            if let reply = try readReply(), reply["ready"] as? Bool == true, isCurrent(job) {
                return true
            }
        } catch { /* Old bundles and failed workers use whisper-cli. */ }
        releaseWorker()
        return false
    }

    private func readReply() throws -> [String: Any]? {
        guard let output else { return nil }
        var data = Data()
        while let byte = try output.read(upToCount: 1), !byte.isEmpty {
            if byte[0] == 10 {
                return try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            data.append(byte)
            if data.count > 1_048_576 { return nil }
        }
        return nil
    }

    private func releaseWorker() {
        idleToken &+= 1
        lock.lock()
        if let worker, worker.isRunning { worker.terminate() }
        if proc === worker { proc = nil }
        lock.unlock()
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
        worker = nil
    }

    private func scheduleRelease() {
        idleToken &+= 1
        let token = idleToken
        queue.asyncAfter(deadline: .now() + idleTimeout) { [weak self] in
            guard let self, self.idleToken == token else { return }
            self.releaseWorker()
        }
    }

    private func runCLI(wav: URL, job: UInt64) -> Result<String, TranscribeError> {
        guard let cliURL, FileManager.default.isExecutableFile(atPath: cliURL.path) else {
            return .failure(TranscribeError(message: "앱 안의 whisper-cli 를 찾지 못했습니다. 다시 설치하세요."))
        }
        let process = Process()
        process.executableURL = cliURL
        process.arguments = ["-m", modelURL.path, "-f", wav.path, "-l", "ko", "-nt", "-np", "-t", "4"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            guard try launch(process, job: job) else {
                return .failure(TranscribeError(message: "취소됨"))
            }
            let deadline = watchdog(process)
            defer { deadline.cancel() }
            // Drain while the child runs so long output cannot fill a pipe and deadlock.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            lock.lock()
            if proc === process { proc = nil }
            lock.unlock()
            guard process.terminationStatus == 0 else {
                return .failure(TranscribeError(message: "whisper-cli 종료 \(process.terminationStatus)"))
            }
            return .success((String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .failure(TranscribeError(message: "whisper-cli 실행 실패: \(error.localizedDescription)"))
        }
    }
}
