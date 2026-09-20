import AppKit
import ApplicationServices
import Carbon
import Foundation

enum SelfTest {
    static func run() -> Int32 {
        var failed = 0
        var blocked = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if ok {
                print("PASS \(name)")
            } else {
                failed += 1
                print("FAIL \(name) \(detail)")
            }
        }

        // --- synthetic: URL allowlist ---
        check("synthetic https huggingface.co", MalgyeolInfo.urlAllowed(URL(string: "https://huggingface.co/x")!))
        check("synthetic https Xet us.aws.cdn.hf.co", MalgyeolInfo.urlAllowed(URL(string: "https://us.aws.cdn.hf.co/x")!))
        check("synthetic https xethub", MalgyeolInfo.urlAllowed(URL(string: "https://cas-bridge.xethub.hf.co/x")!))
        check("synthetic reject http cdn", !MalgyeolInfo.urlAllowed(URL(string: "http://us.aws.cdn.hf.co/x")!))
        check("synthetic reject evil.hf.co", !MalgyeolInfo.hostAllowed("evil.hf.co"))
        check("synthetic reject example.com", !MalgyeolInfo.hostAllowed("example.com"))

        // --- synthetic: job generation ---
        var jobs = JobToken()
        let j1 = jobs.bump()
        let j2 = jobs.bump()
        check("synthetic job stale", !jobs.isCurrent(j1))
        check("synthetic job current", jobs.isCurrent(j2))

        // --- synthetic: clipboard guard (real pasteboard, no paste) ---
        let paster = Paster()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("USER-COPY", forType: .string)
        let write = paster.writeTemporary("OURS")
        check("synthetic wrote ours", pb.string(forType: .string) == "OURS")
        pb.clearContents()
        pb.setString("NEW-USER", forType: .string)
        paster.restoreIfOurs(write)
        check("synthetic restore skipped after user copy", pb.string(forType: .string) == "NEW-USER")
        pb.clearContents()
        pb.setString("PRIOR", forType: .string)
        let write2 = paster.writeTemporary("OURS2")
        paster.restoreIfOurs(write2)
        check("synthetic restore when still ours", pb.string(forType: .string) == "PRIOR")

        // --- synthetic: target refusal matrix (no key events are sent on refusal) ---
        let dummy = AXUIElementCreateSystemWide()
        func target(
            pid: pid_t = 4242, bundle: String = "com.example.editor", app: String = "Editor",
            win: Int = 77, role: String = "AXTextArea", subrole: String = "",
            enabled: Bool = true, settable: Bool = true, secure: Bool = false,
            ax: Bool = true, element: AXUIElement? = AXUIElementCreateSystemWide()
        ) -> LockedTarget {
            LockedTarget(
                pid: pid, bundleId: bundle, appName: app, windowNumber: win,
                role: role, subrole: subrole, identifier: "", enabled: enabled,
                valueSettable: settable, secure: secure, axTrusted: ax,
                element: element, windowElement: nil
            )
        }
        func refused(_ t: LockedTarget) -> Bool { !t.isEditableTextInput || t.refusalReason != nil }
        check("synthetic editable AXTextArea allowed", !refused(target()))
        check("synthetic editable AXTextField allowed", !refused(target(role: "AXTextField")))
        check("synthetic refuse AXSheet", refused(target(role: "AXSheet")), target(role: "AXSheet").refusalReason ?? "")
        check("synthetic refuse AXWindow", refused(target(role: "AXWindow")))
        check("synthetic refuse empty role", refused(target(role: "")))
        check("synthetic refuse AXStaticText", refused(target(role: "AXStaticText")))
        check("synthetic refuse AXSecureTextField", refused(target(role: "AXTextField", subrole: "AXSecureTextField")))
        check("synthetic refuse secure input", refused(target(secure: true)))
        check("synthetic refuse disabled", refused(target(enabled: false)))
        check("synthetic refuse read-only", refused(target(settable: false)))
        check("synthetic refuse unknown window (windowNumber=0)", refused(target(win: 0)))
        check("synthetic refuse AX focus query failed (element nil)", refused(target(element: nil)))
        check("synthetic refuse AX permission revoked", refused(target(ax: false)))
        check("synthetic refuse Ipta self", target(bundle: MalgyeolInfo.bundleId, app: MalgyeolInfo.productKo).refusalReason == "입타 창")

        // identity match: same element → match; different element / window / doc → no match
        let elA = AXUIElementCreateApplication(4242)
        let elB = AXUIElementCreateApplication(4243)
        let a = target(element: elA)
        check("synthetic match same element", TargetLock.matches(a, a))
        check("synthetic mismatch different element", !TargetLock.matches(a, target(element: elB)))
        check("synthetic mismatch different window (document changed)", !TargetLock.matches(a, target(win: 78, element: elA)))
        check("synthetic mismatch different app", !TargetLock.matches(a, target(pid: 4243, element: elA)))
        check("synthetic mismatch role changed", !TargetLock.matches(a, target(role: "AXTextField", element: elA)))
        check("synthetic mismatch when current untrusted", !TargetLock.matches(a, target(win: 0, element: elA)))
        check("synthetic mismatch when current lost focus element", !TargetLock.matches(a, target(element: nil)))
        _ = dummy

        // pasteLocked refusal paths must not touch the clipboard
        pb.clearContents()
        pb.setString("KEEP-ME", forType: .string)
        let sheetNote = paster.pasteLocked("nope", expected: target(role: "AXSheet"))
        check("synthetic pasteLocked refuses AXSheet", sheetNote.contains("자동으로 넣지 않았습니다") || sheetNote.contains("손쉬운 사용"), sheetNote)
        check("synthetic pasteLocked refusal keeps clipboard", pb.string(forType: .string) == "KEEP-ME")
        check("synthetic refusal message is truthful (no '복사해 두었습니다')", !sheetNote.contains("복사해 두었습니다"), sheetNote)
        let selfNote = paster.pasteLocked("nope", expected: target(bundle: MalgyeolInfo.bundleId, app: MalgyeolInfo.productEn))
        check("synthetic pasteLocked refuses Ipta", selfNote.contains("입타"), selfNote)
        let other = target(role: "AXGroup")
        let ghost = target(pid: 59521, bundle: "com.mitchellh.ghostty", app: "Ghostty", role: "AXGroup")
        check("synthetic same-app fallback allows Ghostty-like group", paster.sameAppFallback(ghost, ghost))
        check("synthetic same-app fallback refuses other app", !paster.sameAppFallback(other, ghost))
        check("synthetic same-app fallback refuses AXSheet", !paster.sameAppFallback(target(role: "AXSheet"), target(role: "AXSheet")))
        check("synthetic cleaner drops leading filler", SpeechCleaner.clean("어 입타 붙여넣기") == "입타 붙여넣기", SpeechCleaner.clean("어 입타 붙여넣기"))
        check("synthetic cleaner keeps last intent", SpeechCleaner.clean("빨간색 아니 파란색으로") == "파란색으로", SpeechCleaner.clean("빨간색 아니 파란색으로"))
        check("synthetic cleaner keeps last intent after 아냐", SpeechCleaner.clean("오늘 저녁은 뭐 먹지 아냐 김치찌개로 하자") == "김치찌개로 하자", SpeechCleaner.clean("오늘 저녁은 뭐 먹지 아냐 김치찌개로 하자"))
        let spoken = "음 어 그니까 오늘 저녁은 뭐 먹지 아냐 김치찌개로 하자"
        check(
            "synthetic invented side dishes are dropped",
            !SpeechCleaner.keepsSpokenFacts("김치찌개와 함께 김치전과 김치찌개국수를 먹으면 어떨까?", source: spoken)
        )
        check(
            "synthetic last-intent dinner is kept",
            SpeechCleaner.keepsSpokenFacts("김치찌개로 하자", source: spoken)
        )
        check("synthetic command 요약해 is selection", SpeechCleaner.command(from: "요약해") == .editSelection)
        check("synthetic long mention of 요약 is spoken polish", SpeechCleaner.command(from: "타입리스는 요약도 해준다던데") == .polishSpoken)
        check("synthetic claude url is anthropic", PolishProvider.claude.chatURL?.host == "api.anthropic.com")
        check("synthetic grok url is xai", PolishProvider.grok.chatURL?.host == "api.x.ai")
        check("synthetic openai url is openai", PolishProvider.openai.chatURL?.host == "api.openai.com")
        check("synthetic local stays on this mac", PolishProvider.local.chatURL?.host == "127.0.0.1")
        check("synthetic local default is 20b", PolishProvider.local.defaultModel == "gpt-oss-20b")
        check("synthetic local picker has 20b and 27b", LocalPolishModel.allCases.map(\.rawValue) == ["gpt-oss-20b", "qwen3.8-27b"])
        check("synthetic unknown local model falls back to 20b", LocalPolishModel.resolve("nope") == .twenty)
        let local27 = PolishAPI.makeRequest(provider: .local, key: "", model: LocalPolishModel.twentySeven.rawValue, system: "s", user: "u")
        check("synthetic local 27b request needs no key", local27 != nil)
        if let body = local27?.httpBody, let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            check("synthetic local 27b request uses qwen id", obj["model"] as? String == "qwen3.8-27b")
        } else {
            check("synthetic local 27b request body", false)
        }
        check("synthetic local wait is longer than cloud", PolishProvider.local.requestTimeout > PolishProvider.claude.requestTimeout)
        check("synthetic free plan cannot use claude", PolishPlan(tier: .free, provider: .claude, model: "x", authMode: .key).canAttemptModel == false)
        check("synthetic free apple can use on-device model", PolishPlan(tier: .free, provider: .apple, model: "apple-intelligence", authMode: .key).canAttemptModel == true)
        check("synthetic default provider title is apple", PolishProvider.apple.title == "애플 지능")
        check("synthetic apple hint mentions this mac", PolishProvider.apple.hint.contains("이 맥"))
        check("synthetic claude hint mentions claude", PolishProvider.claude.hint.contains("클로드"))
        check("synthetic outside guide mentions own login", PolishProvider.outsideBrainGuide.contains("본인"))
        check("synthetic grok missing program has title", PolishProvider.grok.missingProgramNote.contains("그록"))
        check("synthetic claude install url", PolishProvider.claude.installURL != nil)
        check("synthetic grok install url", PolishProvider.grok.installURL != nil)
        check("synthetic cursor install url", PolishProvider.cursor.installURL != nil)
        check("synthetic codex install url", PolishProvider.openai.installURL != nil)
        check("synthetic free picker hides cloud", PolishProvider.visible(for: .free, localAvailable: true) == [.apple, .local])
        check("synthetic free picker hides local when missing", PolishProvider.visible(for: .free, localAvailable: false) == [.apple])
        check("synthetic connected picker keeps claude", PolishProvider.visible(for: .connected, localAvailable: true).contains(.claude))
        check("synthetic connected picker hides local when missing", !PolishProvider.visible(for: .connected, localAvailable: false).contains(.local))
        check("synthetic twenty id is gpt-oss-20b", LocalPolishModel.twenty.rawValue == "gpt-oss-20b")
        check("synthetic twentyseven id is qwen", LocalPolishModel.twentySeven.rawValue == "qwen3.8-27b")
        let localPlan = PolishPlan(tier: .connected, provider: .local, model: "gpt-oss-20b", authMode: .key)
        check("synthetic other mac cannot run hermes local", localPlan.canAttemptModel(localAvailable: false) == false)
        check("synthetic this mac can run local when files exist", localPlan.canAttemptModel(localAvailable: true) == true)
        if let cmdQ = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "q",
            charactersIgnoringModifiers: "q",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_Q)
        ) {
            check("synthetic command-q is quit", HotKeySpec.isCommandQ(cmdQ))
        } else {
            check("synthetic command-q is quit", false)
        }
        if let optQ = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .option,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "q",
            charactersIgnoringModifiers: "q",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_Q)
        ) {
            check("synthetic option-q is not quit", !HotKeySpec.isCommandQ(optQ))
        } else {
            check("synthetic option-q is not quit", false)
        }
        if let cmdW = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_W)
        ) {
            check("synthetic command-w closes settings", HotKeySpec.isCommandW(cmdW) && HotKeySpec.closesSettingsWindow(cmdW))
        } else {
            check("synthetic command-w closes settings", false)
        }
        if let esc = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: UInt16(kVK_Escape)
        ) {
            check("synthetic escape closes settings", HotKeySpec.isEscape(esc) && HotKeySpec.closesSettingsWindow(esc))
        } else {
            check("synthetic escape closes settings", false)
        }
        if let optW = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .option,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_W)
        ) {
            check("synthetic option-w does not close settings", !HotKeySpec.isCommandW(optW))
        } else {
            check("synthetic option-w does not close settings", false)
        }
        check("synthetic settings window has title bar", AppDelegate.settingsStyleMask.contains(.titled))
        check("synthetic settings window can close", AppDelegate.settingsStyleMask.contains(.closable))
        check("synthetic main window can hide", AppDelegate.mainStyleMask.contains(.miniaturizable) && AppDelegate.mainStyleMask.contains(.closable))
        check(
            "synthetic hide panel is wired",
            AppDelegate.instancesRespond(to: #selector(AppDelegate.hidePanel))
        )
        check("synthetic hud title while recording", RecordingHUD.title(for: .recording) == "듣는 중")
        check("synthetic hud title while transcribing", RecordingHUD.title(for: .transcribing) == "받아적는 중")
        check("synthetic hud shows while recording", RecordingHUD.shouldShow(phase: .recording))
        check("synthetic hud hides while idle", !RecordingHUD.shouldShow(phase: .idle))
        check("synthetic menubar recording symbol", RecordingHUD.statusSymbol(phase: .recording) == "waveform.circle.fill")
        check(
            "synthetic icon reopen opens window",
            AppDelegate.instancesRespond(to: #selector(AppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)))
        )
        check("synthetic connected plan can use model", PolishPlan(tier: .connected, provider: .claude, model: "x", authMode: .key).canAttemptModel == true)
        check("synthetic cursor is a live provider", PolishProvider.allCases.contains(.cursor))
        check("synthetic cursor supports oauth", PolishProvider.cursor.supportsOAuth)
        check("synthetic oauth plan needs no pasted key", PolishPlan(tier: .connected, provider: .claude, model: "x", authMode: .oauth).needsPastedKey == false)
        check("synthetic oauth plan uses oauth", PolishPlan(tier: .connected, provider: .claude, model: "x", authMode: .oauth).usesOAuth)
        let claudeArgs = OAuthCLI.arguments(provider: .claude, prompt: "hi")
        check("synthetic claude oauth starts with -p", claudeArgs.first == "-p", claudeArgs.joined(separator: " "))
        check("synthetic codex oauth starts with exec", OAuthCLI.arguments(provider: .openai, prompt: "hi").first == "exec")
        check("synthetic grok oauth starts with -p", OAuthCLI.arguments(provider: .grok, prompt: "hi").first == "-p")
        check("synthetic cursor oauth uses ask", OAuthCLI.arguments(provider: .cursor, prompt: "hi").contains("ask"))
        check("synthetic cursor login opens official login", OAuthCLI.loginArguments(for: .cursor) == ["login"])
        check("synthetic grok login opens browser oauth", OAuthCLI.loginArguments(for: .grok) == ["login", "--oauth"])
        let cursorAuthed = OAuthCLI.parseCursorStatus(#"{"isAuthenticated":true,"status":"ok"}"#)
        check("synthetic cursor json ready", cursorAuthed.ready && !cursorAuthed.blocked)
        let cursorOut = OAuthCLI.parseCursorStatus(#"{"isAuthenticated":false,"status":"ok"}"#)
        check("synthetic cursor json not ready", !cursorOut.ready && !cursorOut.blocked)
        let cursorLocked = OAuthCLI.parseCursorStatus("Error: Your macOS login keychain is locked.\nRun security unlock-keychain and try again.")
        check("synthetic cursor keychain lock is blocked", !cursorLocked.ready && cursorLocked.blocked)
        let cursorNot = OAuthCLI.parseCursorStatus("✗ Not logged in")
        check("synthetic cursor not-logged-in is waiting", !cursorNot.ready && !cursorNot.blocked)
        check("synthetic oauth bins named", OAuthCLI.binaryNames(for: .openai) == ["codex"] && OAuthCLI.binaryNames(for: .cursor).contains("agent"))
        check("synthetic claude request needs key", PolishAPI.makeRequest(provider: .claude, key: "", model: "m", system: "s", user: "u") == nil)
        let claudeReq = PolishAPI.makeRequest(provider: .claude, key: "sk-test", model: "m", system: "s", user: "u")
        check("synthetic claude request uses x-api-key", claudeReq?.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        let parsed = PolishAPI.parseText(
            provider: .openai,
            data: Data(#"{"choices":[{"message":{"content":"다듬은 글"}}]}"#.utf8)
        )
        check("synthetic openai parse", parsed == "다듬은 글", parsed ?? "nil")
        check("synthetic cursor has no public chat url", PolishProvider.cursor.chatURL == nil)
        check("synthetic keys stay in app keychain service", KeychainBox.service == "app.malgyeol.Malgyeol.keys")
        check("synthetic keyboard hid ignored", MicButtonSpec.isIgnorable(name: "Apple Internal Keyboard", usagePage: 0x07))
        check("synthetic trackpad ignored", MicButtonSpec.isIgnorable(name: "Apple Internal Trackpad", usagePage: 0x0C))
        check("synthetic consumer dji accepted", !MicButtonSpec.isIgnorable(name: "DJI Mic", usagePage: 0x0C))
        check("synthetic wireless name", WirelessMicHint.looksWireless("DJI Mic Mini"))
        check("synthetic built-in not wireless", !WirelessMicHint.looksWireless("MacBook Pro Microphone"))
        let priorMic = MicButtonSpec.load()
        let spec = MicButtonSpec(vendorId: 1, productId: 2, usagePage: 12, usage: 205, productName: "DJI Mic")
        spec.save()
        check("synthetic mic button persist", MicButtonSpec.load() == spec)
        check("synthetic mic button match", spec.matches(vendorId: 1, productId: 2, usagePage: 12, usage: 205))
        check("synthetic mic button vendor mismatch", !spec.matches(vendorId: 99, productId: 2, usagePage: 12, usage: 205))
        let media = MicButtonSpec(vendorId: 0, productId: 0, usagePage: MicButtonSpec.mediaPage, usage: 16, productName: "무선 마이크 버튼")
        check("synthetic media match", media.matches(vendorId: 0, productId: 0, usagePage: MicButtonSpec.mediaPage, usage: 16))
        if let priorMic {
            priorMic.save()
        } else {
            MicButtonSpec.clearSaved()
        }
        check("synthetic mic button restore after test", MicButtonSpec.load() == priorMic)

        // --- real: dedicated TextEdit document body ---
        let real = textEditRealPaste(paster: paster)
        print("REAL textedit \(real.detail)")
        switch real.status {
        case .pass: print("PASS real textedit body contains token")
        case .fail:
            failed += 1
            print("FAIL real textedit body \(real.detail)")
        case .blocked:
            blocked += 1
            print("BLOCKED real textedit \(real.detail)")
        }

        print("selftest failed=\(failed) blocked=\(blocked)")
        return failed == 0 ? 0 : 1
    }

    enum RealStatus { case pass, fail, blocked }
    struct RealResult { let status: RealStatus; let detail: String }

    /// Opens a NEW dedicated TextEdit document, locks the focused element, pastes,
    /// then reads the document body back via TextEdit's scripting interface.
    /// PASS only if the body contains the token. Never targets any other app.
    private static func textEditRealPaste(paster: Paster) -> RealResult {
        guard Paster.isTrusted() else {
            return RealResult(status: .blocked, detail: "accessibility not granted to this process; real paste not attempted")
        }
        let token = "malgyeol-r4-\(Int(Date().timeIntervalSince1970))"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("malgyeol-r4-textedit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "r4-\(token).txt"
        let file = dir.appendingPathComponent(name)
        try? "R4DOC\n".write(to: file, atomically: true, encoding: .utf8)

        final class Box { var opened = false }
        let box = Box()
        guard let te = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
            return RealResult(status: .blocked, detail: "TextEdit not found")
        }
        let conf = NSWorkspace.OpenConfiguration()
        conf.activates = true
        let sem = DispatchSemaphore(value: 0)
        NSWorkspace.shared.open([file], withApplicationAt: te, configuration: conf) { _, err in
            box.opened = err == nil
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 5)
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))

        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != "com.apple.TextEdit" {
            return RealResult(status: .blocked, detail: "TextEdit not frontmost (front=\(front?.localizedName ?? "?")); refusing to paste anywhere else")
        }
        let locked = TargetLock.capture()
        if locked.role != "AXTextArea" || !locked.isEditableTextInput {
            return RealResult(status: .blocked, detail: "focused element is not the document text area: \(locked.summary) reason=\(locked.refusalReason ?? "-")")
        }
        // Sanity: a fake AXSheet target for the same app must be refused before any key event.
        var sheetLike = locked
        sheetLike.role = "AXSheet"
        let sheetNote = paster.pasteLocked(token, expected: sheetLike)
        if !sheetNote.contains("자동으로 넣지 않았습니다") {
            return RealResult(status: .fail, detail: "AXSheet-like target was not refused: \(sheetNote)")
        }

        let note = paster.pasteLocked(token, expected: locked)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let body = textEditBody(documentName: name)
        let ok = body.contains(token)
        let detail = "doc=\(name) lock=\(locked.summary) paste=\(note) bodyHasToken=\(ok) bodyLen=\(body.count)"
        return RealResult(status: ok ? .pass : .fail, detail: detail)
    }

    private static func textEditBody(documentName: String) -> String {
        let script = "tell application \"TextEdit\" to get text of document \"\(documentName)\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return ""
        }
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
