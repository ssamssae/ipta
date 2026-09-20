import AppKit
import SwiftUI

enum MalgyeolInfo {
    static let productKo = "입타"
    static let productEn = "Ipta"
    static let label = "입타"
    static let bundleId = "app.ipta.Ipta"
    static let maxSeconds: Double = 60
    static let modelName = "ggml-small.bin"
    static let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!
    static let modelSHA256 = "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
    static let modelBytes = 487_601_967
    /// Probe 2026-09-12: huggingface.co 302 HTTPS → us.aws.cdn.hf.co 200 (Xet).
    static let probedXetHost = "us.aws.cdn.hf.co"

    static func hostAllowed(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "huggingface.co" || h.hasSuffix(".huggingface.co") { return true }
        if h.hasSuffix(".cdn.hf.co") { return true }
        if h.hasSuffix(".xethub.hf.co") { return true }
        return false
    }

    static func urlAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard let host = url.host else { return false }
        return hostAllowed(host)
    }

    static var supportDir: URL {
        if let p = ProcessInfo.processInfo.environment["MALGYEOL_SUPPORT_DIR"], !p.isEmpty {
            let u = URL(fileURLWithPath: p, isDirectory: true)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Malgyeol", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var modelURLOnDisk: URL {
        supportDir.appendingPathComponent("Models", isDirectory: true).appendingPathComponent(modelName)
    }

    static var logURL: URL { supportDir.appendingPathComponent("malgyeol.log") }
}

func malgyeolLog(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = MalgyeolInfo.logURL
    if FileManager.default.fileExists(atPath: url.path) {
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        }
    } else {
        try? data.write(to: url)
    }
}

@main
enum MalgyeolMain {
    nonisolated(unsafe) static var retainedDelegate: AppDelegate?

    static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            _ = NSApplication.shared
            let code = SelfTest.run()
            exit(code)
        }
        if args.contains("--download-model") {
            _ = NSApplication.shared
            let cancelMs = intArg(args, flag: "--cancel-ms")
            let code = HeadlessDownload.run(cancelAfterMs: cancelMs)
            exit(code)
        }
        if args.contains("--check-model") {
            let mgr = ModelManager()
            if mgr.sizeLooksReady() {
                fputs("size-ok\n", stdout)
                exit(0)
            }
            fputs("model-missing\n", stdout)
            exit(1)
        }
        if args.contains("--polish-probe") {
            _ = NSApplication.shared
            let raw = stringArg(args, flag: "--polish-probe") ?? ""
            let code = PolishProbe.run(raw)
            exit(code)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private static func intArg(_ args: [String], flag: String) -> Int? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return Int(args[i + 1])
    }

    private static func stringArg(_ args: [String], flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        return v.hasPrefix("--") ? nil : v
    }
}

enum PolishProbe {
    static func run(_ raw: String) -> Int32 {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let provider: PolishProvider
        switch name {
        case "codex", "openai": provider = .openai
        case "grok": provider = .grok
        case "cursor": provider = .cursor
        case "claude": provider = .claude
        default:
            fputs("polish-probe-unknown=\(name)\n", stderr)
            return 2
        }
        let probe = OAuthCLI.probe(provider)
        fputs("polish-probe provider=\(provider.rawValue) ready=\(probe.ready) note=\(probe.note)\n", stdout)
        fflush(stdout)
        guard probe.ready else { return 3 }
        let text = OAuthCLI.polish(
            provider: provider,
            instructions: "설명 없이 다듬은 한 문장만 출력한다. 새 사실을 만들지 않는다.",
            user: "어 아테나에서 다듬기 확인만 해볼게"
        )
        guard let text, !text.isEmpty else {
            fputs("polish-probe-empty\n", stdout)
            return 4
        }
        let preview = String(text.prefix(40)).replacingOccurrences(of: "\n", with: " ")
        fputs("polish-probe-ok chars=\(text.count) preview=\(preview)\n", stdout)
        return 0
    }
}

enum HeadlessDownload {
    static func run(cancelAfterMs: Int?) -> Int32 {
        // ModelManager hops through the main queue; keep the main run loop alive
        // instead of blocking it with a semaphore (r2: earlier version deadlocked).
        final class Box { var result: String?; var sawProgress = false; var lastPrint = Date.distantPast }
        let box = Box()
        let mgr = ModelManager()
        let obs = NotificationCenter.default.addObserver(forName: .malgyeolDownload, object: nil, queue: .main) { note in
            let written = note.userInfo?["written"] as? Int64 ?? 0
            let frac = note.userInfo?["frac"] as? Double ?? 0
            box.sawProgress = true
            if Date().timeIntervalSince(box.lastPrint) > 1.0 || frac >= 1 {
                box.lastPrint = Date()
                fputs(String(format: "progress frac=%.3f written=%lld\n", frac, written), stdout)
                fflush(stdout)
            }
        }
        defer { NotificationCenter.default.removeObserver(obs) }
        mgr.download { err in
            box.result = err ?? "ok"
        }
        if let ms = cancelAfterMs, ms > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
                fputs("cancel-after-ms=\(ms)\n", stdout)
                mgr.cancel()
            }
        }
        let timeout = cancelAfterMs != nil ? 30.0 : 1800.0
        let deadline = Date().addingTimeInterval(timeout)
        while box.result == nil, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        if box.result == nil {
            fputs("download-timeout\n", stderr)
            return 2
        }
        let result = box.result
        let sawProgress = box.sawProgress
        fputs("download-result=\(result ?? "?") progress=\(sawProgress)\n", stdout)
        if result == "ok" { return 0 }
        if result == "cancelled" { return 3 }
        return 1
    }
}
