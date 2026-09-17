import Foundation

struct TranscribeError: Error {
    let message: String
}

final class Transcriber: @unchecked Sendable {
    private var proc: Process?

    func cancel() {
        proc?.terminate()
        proc = nil
    }

    func transcribe(wav: URL, completion: @escaping (Result<String, TranscribeError>) -> Void) {
        guard let cli = bundledCLI() else {
            completion(.failure(TranscribeError(message: "앱 안의 whisper-cli 를 찾지 못했습니다. 다시 설치하세요.")))
            return
        }
        let model = MalgyeolInfo.modelURLOnDisk
        guard FileManager.default.fileExists(atPath: model.path) else {
            completion(.failure(TranscribeError(message: "모델 파일이 없습니다. 창에서 모델을 받으세요.")))
            return
        }
        let proc = Process()
        proc.executableURL = cli
        proc.arguments = [
            "-m", model.path,
            "-f", wav.path,
            "-l", "ko",
            "-nt",
            "-np",
            "-t", "4",
        ]
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.environment = [
            "PATH": "/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
        ]
        self.proc = proc
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try proc.run()
                proc.waitUntilExit()
                let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                self.proc = nil
                if proc.terminationStatus != 0 {
                    completion(.failure(TranscribeError(message: "whisper-cli 종료 \(proc.terminationStatus): \(stderr.suffix(400))")))
                    return
                }
                let text = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                completion(.success(text))
            } catch {
                completion(.failure(TranscribeError(message: "whisper-cli 실행 실패: \(error.localizedDescription)")))
            }
        }
    }

    private func bundledCLI() -> URL? {
        let bundle = Bundle.main.bundleURL
        let helpers = bundle.appendingPathComponent("Contents/Helpers/whisper-cli")
        if FileManager.default.isExecutableFile(atPath: helpers.path) { return helpers }
        let macos = bundle.appendingPathComponent("Contents/MacOS/whisper-cli")
        if FileManager.default.isExecutableFile(atPath: macos.path) { return macos }
        return nil
    }
}
