import Foundation
import Darwin

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

    static func polish(provider: PolishProvider, instructions: String, user: String, key: String = "", optimizeDictation: Bool = false) -> String? {
        guard let bin = binary(for: provider) else { return nil }
        let prompt = """
        \(instructions)

        글:
        \(user)
        """
        var args = arguments(provider: provider, prompt: prompt)
        var environment: [String: String] = [:]
        var profileDirectory: URL?
        defer {
            if let profileDirectory { try? FileManager.default.removeItem(at: profileDirectory) }
        }
        if provider == .grok {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ipta-polish-" + UUID().uuidString)
            let profile = directory.appendingPathComponent("agent.md")
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                profileDirectory = directory
                let header = "---\nname: ipta-polish\ndescription: Korean dictation cleanup\ntools: []\n---\n"
                try (header + instructions).write(to: profile, atomically: true, encoding: .utf8)
            } catch { return nil }
            args = ["--agent", profile.path, "-p", user, "--tools", "", "--disable-web-search", "--no-subagents", "--max-turns", "1", "--reasoning-effort", "low", "--output-format", "streaming-messages-json"]
            environment = ["GROK_MEMORY": "0", "GROK_WORKFLOWS": "0"]
            for vendor in ["CLAUDE", "CURSOR"] {
                for kind in ["AGENTS", "RULES", "SKILLS", "MCPS", "HOOKS"] {
                    environment["GROK_\(vendor)_\(kind)_ENABLED"] = "0"
                }
            }
        }
        if provider == .cursor {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ipta-cursor-" + UUID().uuidString)
            let workspace = directory.appendingPathComponent("workspace", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                profileDirectory = directory
                try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
            } catch { return nil }
            // Keep CLI preference writes out of the user's configuration and out of the workspace.
            if optimizeDictation, key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let data = try? Data(contentsOf: cursorConfigurationDirectory().appendingPathComponent("cli-config.json")),
               let model = cursorPolishModel(configuration: data) {
                let config = directory.appendingPathComponent("configuration", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: config, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                    let file = config.appendingPathComponent("cli-config.json")
                    try data.write(to: file, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                    environment["CURSOR_CONFIG_DIR"] = config.path
                    args += ["--model", model]
                    malgyeolLog("polish cursor effort=low scope=dictation isolated=true")
                } catch {
                    // Optimization is optional; the original account/model remains usable.
                }
            }
            // Only this app-created empty workspace is trusted; never use --force/--yolo.
            args += ["--workspace", workspace.path, "--trust"]
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                args.insert(contentsOf: ["--api-key", trimmed], at: 0)
            }
        }
        guard !args.isEmpty else { return nil }
        malgyeolLog("polish oauth provider=\(provider.rawValue) bin=\(bin.lastPathComponent)")
        let started = Date()
        let result = provider == .grok
            ? runGrok(bin, args, timeout: 15, environment: environment)
            : run(bin, args, timeout: 90, environment: environment)
        malgyeolLog("polish elapsed=\(String(format: "%.2f", Date().timeIntervalSince(started))) exit=\(result.code)")
        guard result.code == 0 else { return nil }
        if provider == .grok {
            let cleaned = cleanOutput(result.out)
            return cleaned.isEmpty ? nil : cleaned
        }
        malgyeolLog("polish oauth exit=\(result.code) chars=\(result.out.count)")
        let text = cleanOutput(result.out)
        return text.isEmpty ? nil : text
    }

    static func cursorConfigurationDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["CURSOR_CONFIG_DIR"], !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if let path = environment["XDG_CONFIG_HOME"], !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("cursor")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor")
    }

    static func cursorPolishModel(configuration: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: configuration) as? [String: Any],
              let selected = object["selectedModel"] as? [String: Any],
              selected["modelId"] as? String == "grok-4.6",
              let parameters = selected["parameters"] as? [[String: String]],
              parameters.contains(where: { $0["id"] == "effort" && $0["value"] == "high" }),
              parameters.contains(where: { $0["id"] == "fast" && $0["value"] == "true" }) else { return nil }
        // Same Grok 4.6 and Fast tier; lower effort only for the measured dictation path.
        return "cursor-grok-4.6-low-fast"
    }

    struct RunResult {
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

    private final class GrokCompletion: @unchecked Sendable {
        let ready = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var value: RunResult?
        func finish(_ result: RunResult) {
            lock.lock()
            defer { lock.unlock() }
            guard value == nil else { return }
            value = result
            ready.signal()
        }
        func result() -> RunResult {
            lock.lock()
            defer { lock.unlock() }
            return value ?? RunResult(code: 1, out: "", err: "")
        }
    }

    /// Only a terminal success event is usable; text/thinking deltas are never pasted.
    static func grokTerminalResult(_ data: Data) -> RunResult? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "result" else { return nil }
        guard object["subtype"] as? String == "success",
              object["is_error"] as? Bool == false,
              object["stop_reason"] as? String == "end_turn",
              let text = object["result"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return RunResult(code: 1, out: "", err: "")
        }
        return RunResult(code: 0, out: text, err: "")
    }

    static func runGrok(_ bin: URL, _ args: [String], timeout: TimeInterval, environment: [String: String] = [:]) -> RunResult {
        let proc = Process()
        proc.executableURL = bin
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchDirectories().map(\.path).joined(separator: ":") + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env.merge(environment) { _, replacement in replacement }
        proc.environment = env
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("malgyeol-oauth", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        proc.currentDirectoryURL = tmp
        let output = Pipe(), errors = Pipe()
        proc.standardOutput = output
        proc.standardError = errors
        proc.standardInput = FileHandle.nullDevice
        let started = Date()
        let completed = GrokCompletion()
        let readers = DispatchGroup()
        do { try proc.run() }
        catch { return RunResult(code: 127, out: "", err: "") }
        let deadline = DispatchTime.now() + timeout
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { try? output.fileHandleForReading.close(); readers.leave() }
            var pending = Data()
            var oversized = false
            while true {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                if oversized { continue }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    let line = Data(pending[..<newline])
                    pending.removeSubrange(...newline)
                    if line.count > 1_048_576 {
                        oversized = true
                        completed.finish(RunResult(code: 1, out: "", err: ""))
                        break
                    }
                    if let result = grokTerminalResult(line) { completed.finish(result) }
                }
                if pending.count > 1_048_576 {
                    oversized = true
                    pending.removeAll()
                    completed.finish(RunResult(code: 1, out: "", err: ""))
                }
            }
            if !oversized, let result = grokTerminalResult(pending) { completed.finish(result) }
        }
        readers.enter()
        DispatchQueue.global().async {
            defer { try? errors.fileHandleForReading.close(); readers.leave() }
            // Drain concurrently, without retaining potentially sensitive diagnostics.
            while !errors.fileHandleForReading.availableData.isEmpty {}
        }
        DispatchQueue.global().async {
            proc.waitUntilExit()
            malgyeolLog("polish grok process finished elapsed=\(String(format: "%.2f", Date().timeIntervalSince(started)))")
            readers.wait()
            completed.finish(RunResult(code: proc.terminationStatus == 0 ? 1 : proc.terminationStatus, out: "", err: ""))
        }
        // Let successful requests finish housekeeping naturally, but bound hung children.
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            guard proc.isRunning else { return }
            proc.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
            }
        }
        guard completed.ready.wait(timeout: deadline) == .success else {
            return RunResult(code: 124, out: "", err: "")
        }
        return completed.result()
    }

    private static func run(_ bin: URL, _ args: [String], timeout: TimeInterval, environment: [String: String] = [:]) -> RunResult {
        let proc = Process()
        proc.executableURL = bin
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        let extra = searchDirectories().map(\.path).joined(separator: ":")
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env.merge(environment) { _, replacement in replacement }
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
