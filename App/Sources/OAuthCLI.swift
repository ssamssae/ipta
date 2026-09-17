import Foundation

enum OAuthCLI {
    static func binaryNames(for provider: PolishProvider) -> [String] {
        switch provider {
        case .claude: return ["claude"]
        case .openai: return ["codex"]
        case .grok: return ["grok"]
        case .cursor: return ["agent", "cursor-agent"]
        case .apple, .local: return []
        }
    }

    static func arguments(provider: PolishProvider, prompt: String) -> [String] {
        switch provider {
        case .claude:
            return ["-p", prompt, "--output-format", "text", "--permission-mode", "dontAsk"]
        case .openai:
            return ["exec", "--ephemeral", "--skip-git-repo-check", "-s", "read-only", prompt]
        case .grok:
            return ["-p", prompt, "--disable-web-search"]
        case .cursor:
            return ["-p", "--mode", "ask", "--output-format", "text", prompt]
        case .apple, .local:
            return []
        }
    }

    static func searchDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            home.appendingPathComponent(".local/bin", isDirectory: true),
        ]
    }

    static func binary(for provider: PolishProvider) -> URL? {
        let fm = FileManager.default
        for name in binaryNames(for: provider) {
            for dir in searchDirectories() {
                let url = dir.appendingPathComponent(name)
                if fm.isExecutableFile(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }

    static func probe(_ provider: PolishProvider) -> (ready: Bool, note: String) {
        guard provider.supportsOAuth else {
            return (false, "이 모델은 이 맥 로그인을 쓰지 않습니다")
        }
        guard let bin = binary(for: provider) else {
            return (false, "이 맥에 \(provider.title) 프로그램이 없습니다")
        }
        switch provider {
        case .claude:
            let out = run(bin, ["auth", "status", "--json"], timeout: 5).combined
            if out.contains("\"loggedIn\": true") {
                return (true, "이 맥에 클로드 로그인 있음")
            }
            if out.contains("loggedIn") {
                return (false, "클로드 로그인이 없거나 만료됨. 터미널에서 claude login")
            }
            return (false, "클로드 로그인을 확인하지 못했습니다")
        case .openai:
            let out = run(bin, ["login", "status"], timeout: 5).combined
            if out.localizedCaseInsensitiveContains("logged in") {
                return (true, "이 맥에 코덱스 로그인 있음")
            }
            return (false, "코덱스 로그인이 없습니다. 터미널에서 codex login")
        case .grok:
            let auth = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".grok/auth.json")
            if FileManager.default.fileExists(atPath: auth.path) {
                return (true, "이 맥에 그록 로그인 파일 있음")
            }
            return (false, "그록 로그인이 없습니다. 터미널에서 grok login")
        case .cursor:
            let out = run(bin, ["status"], timeout: 6).combined
            if out.localizedCaseInsensitiveContains("logged in") {
                return (true, "이 맥에 커서 로그인 있음")
            }
            return (false, "커서 로그인이 없습니다. 터미널에서 agent login")
        case .apple, .local:
            return (false, "")
        }
    }

    static func polish(provider: PolishProvider, instructions: String, user: String, key: String = "") -> String? {
        guard let bin = binary(for: provider) else { return nil }
        let prompt = """
        \(instructions)

        글:
        \(user)
        """
        var args = arguments(provider: provider, prompt: prompt)
        if provider == .cursor {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                args.insert(contentsOf: ["--api-key", trimmed], at: 0)
            }
        }
        guard !args.isEmpty else { return nil }
        malgyeolLog("polish oauth provider=\(provider.rawValue) bin=\(bin.lastPathComponent)")
        let result = run(bin, args, timeout: 90)
        malgyeolLog("polish oauth exit=\(result.code) chars=\(result.out.count)")
        let text = cleanOutput(result.out)
        return text.isEmpty ? nil : text
    }

    private struct RunResult {
        let code: Int32
        let out: String
        let err: String
        var combined: String { out + "\n" + err }
    }

    private static func cleanOutput(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            var lines = t.components(separatedBy: "\n")
            if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
            if lines.last?.hasPrefix("```") == true { lines.removeLast() }
            t = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    private static func run(_ bin: URL, _ args: [String], timeout: TimeInterval) -> RunResult {
        let proc = Process()
        proc.executableURL = bin
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        let extra = searchDirectories().map(\.path).joined(separator: ":")
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        proc.environment = env
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("malgyeol-oauth", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        proc.currentDirectoryURL = tmp
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return RunResult(code: 127, out: "", err: "")
        }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            proc.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            proc.terminate()
            return RunResult(code: 124, out: "", err: "")
        }
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return RunResult(code: proc.terminationStatus, out: out, err: err)
    }
}
