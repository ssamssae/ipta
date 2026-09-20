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

    struct Probe {
        var ready: Bool
        var blocked: Bool
        var note: String
    }

    static func probe(_ provider: PolishProvider) -> Probe {
        guard provider.supportsOAuth else {
            return Probe(ready: false, blocked: true, note: "이 모델은 이 맥 로그인을 쓰지 않습니다")
        }
        guard let bin = binary(for: provider) else {
            return Probe(ready: false, blocked: true, note: provider.missingProgramNote)
        }
        switch provider {
        case .claude:
            let out = run(bin, ["auth", "status", "--json"], timeout: 5).combined
            if keychainLocked(out) {
                return Probe(ready: false, blocked: true, note: keychainNote(for: .claude))
            }
            if out.contains("\"loggedIn\": true") {
                return Probe(ready: true, blocked: false, note: "이 맥 클로드에 이미 붙어 있습니다")
            }
            if out.contains("loggedIn") {
                return Probe(ready: false, blocked: false, note: "아직 클로드에 안 붙어 있습니다. 로그인 버튼을 누르면 브라우저가 열립니다")
            }
            return Probe(ready: false, blocked: false, note: "클로드 로그인을 확인하지 못했습니다")
        case .openai:
            let out = run(bin, ["login", "status"], timeout: 5).combined
            if keychainLocked(out) {
                return Probe(ready: false, blocked: true, note: keychainNote(for: .openai))
            }
            let lower = out.lowercased()
            if lower.contains("not logged in") || lower.contains("logged out") {
                return Probe(ready: false, blocked: false, note: "아직 코덱스에 안 붙어 있습니다. 로그인 버튼을 누르면 브라우저가 열립니다")
            }
            if lower.contains("logged in") {
                return Probe(ready: true, blocked: false, note: "이 맥 코덱스에 이미 붙어 있습니다")
            }
            return Probe(ready: false, blocked: false, note: "아직 코덱스에 안 붙어 있습니다. 로그인 버튼을 누르면 브라우저가 열립니다")
        case .grok:
            let auth = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".grok/auth.json")
            if FileManager.default.fileExists(atPath: auth.path) {
                return Probe(ready: true, blocked: false, note: "이 맥 그록에 이미 붙어 있습니다")
            }
            return Probe(ready: false, blocked: false, note: "아직 그록에 안 붙어 있습니다. 로그인 버튼을 누르면 브라우저가 열립니다")
        case .cursor:
            let out = run(bin, ["status", "--format", "json"], timeout: 6).combined
            return parseCursorStatus(out)
        case .apple, .local:
            return Probe(ready: false, blocked: true, note: "")
        }
    }

    static func parseCursorStatus(_ raw: String) -> Probe {
        if keychainLocked(raw) {
            return Probe(ready: false, blocked: true, note: keychainNote(for: .cursor))
        }
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let auth = obj["isAuthenticated"] as? Bool {
            if auth {
                return Probe(ready: true, blocked: false, note: "이 맥 커서에 이미 붙어 있습니다")
            }
            return Probe(ready: false, blocked: false, note: "아직 커서에 안 붙어 있습니다. 로그인 버튼을 누르면 브라우저가 열립니다")
        }
        let lower = raw.lowercased()
        if lower.contains("not logged in") || lower.contains("logged out") {
            return Probe(ready: false, blocked: false, note: "아직 커서에 안 붙어 있습니다. 로그인 버튼을 누르면 브라우저가 열립니다")
        }
        if lower.contains("logged in") {
            return Probe(ready: true, blocked: false, note: "이 맥 커서에 이미 붙어 있습니다")
        }
        return Probe(ready: false, blocked: false, note: "커서 로그인을 확인하지 못했습니다")
    }

    private static func keychainLocked(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("keychain is locked") || lower.contains("unlock-keychain")
    }

    private static func keychainNote(for provider: PolishProvider) -> String {
        "이 맥 열쇠묶음이 잠겨 \(provider.title) 로그인을 못 봅니다. 입타를 독이나 응용 프로그램에서 다시 열어 주세요"
    }

    static func loginArguments(for provider: PolishProvider) -> [String] {
        switch provider {
        case .grok: return ["login", "--oauth"]
        case .cursor, .claude, .openai: return ["login"]
        case .apple, .local: return []
        }
    }

    /// Opens the official login UI (browser). Does not wait for the person to finish.
    @discardableResult
    static func startLogin(_ provider: PolishProvider) -> String {
        guard provider.supportsOAuth else {
            return "이 모델은 로그인 창이 없습니다"
        }
        guard let bin = binary(for: provider) else {
            return provider.missingProgramNote
        }
        let args = loginArguments(for: provider)
        guard !args.isEmpty else { return "로그인 명령을 모릅니다" }
        let proc = Process()
        proc.executableURL = bin
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "NO_OPEN_BROWSER")
        let extra = searchDirectories().map(\.path).joined(separator: ":")
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        proc.environment = env
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return "\(provider.title) 로그인 창을 열지 못했습니다"
        }
        return "\(provider.title) 로그인 창을 열었습니다"
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
