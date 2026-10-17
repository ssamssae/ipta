import AppKit
import ApplicationServices
import Carbon
import Foundation

struct ClipboardSnapshot {
    let changeCount: Int
    let items: [NSPasteboardItem]
}

struct PasteWrite {
    let ourChangeCount: Int
    let ourText: String
    let prior: ClipboardSnapshot
}

final class Paster {
    private var restoreGeneration: UInt64 = 0

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func promptTrust() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    func snapshotPasteboard() -> ClipboardSnapshot {
        let pb = NSPasteboard.general
        let copies: [NSPasteboardItem] = (pb.pasteboardItems ?? []).compactMap { src in
            let item = NSPasteboardItem()
            var wrote = false
            for type in src.types {
                if let data = src.data(forType: type) {
                    item.setData(data, forType: type)
                    wrote = true
                } else if let str = src.string(forType: type) {
                    item.setString(str, forType: type)
                    wrote = true
                }
            }
            return wrote ? item : nil
        }
        return ClipboardSnapshot(changeCount: pb.changeCount, items: copies)
    }

    func writeTemporary(_ text: String) -> PasteWrite {
        let prior = snapshotPasteboard()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return PasteWrite(ourChangeCount: pb.changeCount, ourText: text, prior: prior)
    }

    func restoreIfOurs(_ write: PasteWrite) {
        let pb = NSPasteboard.general
        if pb.changeCount != write.ourChangeCount {
            malgyeolLog("clipboard restore skipped: changeCount \(pb.changeCount) != \(write.ourChangeCount)")
            return
        }
        if pb.string(forType: .string) != write.ourText {
            malgyeolLog("clipboard restore skipped: pasteboard no longer our text")
            return
        }
        pb.clearContents()
        if write.prior.items.isEmpty {
            return
        }
        pb.writeObjects(write.prior.items)
        malgyeolLog("clipboard restored prior items=\(write.prior.items.count)")
    }

    static let keptNote = "결과를 보관했습니다. 복사를 누르세요."

    // MARK: - ⌘V 키 위치(자판별)

    private nonisolated(unsafe) static var cachedVKey: (layoutID: String, code: CGKeyCode)?

    /// 현재 자판에서 「v」를 내는 키 코드. 드보락·AZERTY 같은 자판에서도 ⌘V 가 맞게 간다. 못 찾으면 ANSI V(9).
    static func keyCodeForV() -> CGKeyCode {
        let fallback = CGKeyCode(kVK_ANSI_V)
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return fallback }
        let layoutID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? ""
        if let cached = cachedVKey, cached.layoutID == layoutID { return cached.code }
        guard let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
        let data = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue() as Data
        let table: [(CGKeyCode, String)] = data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return [] }
            return (0..<128).compactMap { code -> (CGKeyCode, String)? in
                var dead: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    base, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, chars.count, &length, &chars
                )
                guard status == noErr, length > 0 else { return nil }
                return (CGKeyCode(code), String(utf16CodeUnits: chars, count: length))
            }
        }
        let code = keyCode(producing: "v", in: table) ?? fallback
        cachedVKey = (layoutID, code)
        if code != fallback { malgyeolLog("paste key: layout=\(layoutID) v=\(code)") }
        return code
    }

    /// 표에서 그 글자를 내는 첫 키 코드(순수, 검사용). 대소문자 무시.
    nonisolated static func keyCode(producing char: Character, in table: [(CGKeyCode, String)]) -> CGKeyCode? {
        let want = String(char).lowercased()
        return table.first { $0.1.lowercased() == want }?.0
    }

    /// Auto-paste into the input captured at record start.
    /// Classic path: same AX text field. Fallback: same front app (Ghostty/Cursor prompt).
    /// Every refusal path leaves the clipboard untouched; the transcript stays in the window.
    func pasteLocked(_ text: String, expected: LockedTarget) -> String {
        if text.isEmpty { return "붙일 전사가 없습니다" }
        if IsSecureEventInputEnabled() || expected.secure {
            return "암호 입력 중이라 자동으로 넣지 않았습니다. \(Paster.keptNote)"
        }
        if expected.isMalgyeol {
            return "입타 창에는 자동으로 넣지 않습니다. \(Paster.keptNote)"
        }
        if !Paster.isTrusted() {
            return "손쉬운 사용이 꺼져 있어 다른 앱에 넣지 못했습니다. 설정에서 입타를 허용하거나 복사를 쓰세요."
        }

        activateTarget(expected)
        let current = TargetLock.capture()
        if current.secure || IsSecureEventInputEnabled() {
            return "암호 칸이라 자동으로 넣지 않았습니다. \(Paster.keptNote)"
        }
        if current.isMalgyeol {
            return "지금은 입타가 앞창입니다. \(Paster.keptNote)"
        }

        if expected.isEditableTextInput, current.isEditableTextInput, TargetLock.matches(expected, current) {
            return sendCommandV(text, note: "원래 칸에 붙여넣기 (\(expected.appName), Enter 없음)", log: "paste locked \(expected.summary)")
        }
        if sameAppFallback(expected, current) {
            malgyeolLog("paste same-app fallback locked=\(expected.summary) now=\(current.summary)")
            return sendCommandV(text, note: "앞 앱에 붙여넣기 (\(expected.appName), Enter 없음)", log: "paste fallback \(expected.summary)")
        }

        if let why = expected.refusalReason {
            malgyeolLog("paste refuse locked-target \(why) \(expected.summary)")
            return "시작할 때의 대상이 \(why)이라 자동으로 넣지 않았습니다. \(Paster.keptNote)"
        }
        if !expected.isEditableTextInput {
            malgyeolLog("paste refuse not-editable \(expected.summary)")
            return "시작할 때의 대상이 입력칸이 아니라 자동으로 넣지 않았습니다. \(Paster.keptNote)"
        }
        if let why = current.refusalReason {
            malgyeolLog("paste refuse current-target \(why) \(current.summary)")
            return "지금 대상이 \(why)이라 자동으로 넣지 않았습니다. \(Paster.keptNote)"
        }
        if !current.isEditableTextInput {
            malgyeolLog("paste refuse current not-editable \(current.summary)")
            return "지금 대상이 입력칸이 아니라 자동으로 넣지 않았습니다. \(Paster.keptNote)"
        }
        malgyeolLog("paste abort mismatch locked=\(expected.summary) now=\(current.summary)")
        return "입력칸이 바뀌어 자동으로 넣지 않았습니다. \(Paster.keptNote)"
    }

    /// Ghostty/Cursor composer often is not AXTextArea. Same app + same pid is enough.
    /// Sheets/dialogs stay refused so we never paste into a save/open panel.
    static let fallbackBlockedRoles: Set<String> = [
        "AXSheet", "AXDialog", "AXPopover", "AXSecureTextField",
    ]

    func sameAppFallback(_ expected: LockedTarget, _ current: LockedTarget) -> Bool {
        if expected.pid == 0 || current.pid == 0 { return false }
        if expected.bundleId.isEmpty || current.bundleId.isEmpty { return false }
        if expected.isMalgyeol || current.isMalgyeol { return false }
        if expected.secure || current.secure { return false }
        if Paster.fallbackBlockedRoles.contains(expected.role) { return false }
        if Paster.fallbackBlockedRoles.contains(current.role) { return false }
        return expected.pid == current.pid && expected.bundleId == current.bundleId
    }

    private func activateTarget(_ expected: LockedTarget) {
        guard expected.pid != 0 else { return }
        guard let app = NSRunningApplication(processIdentifier: expected.pid) else { return }
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        Thread.sleep(forTimeInterval: 0.08)
    }

    private func sendCommandV(_ text: String, note: String, log: String) -> String {
        let write = writeTemporary(text)
        restoreGeneration += 1
        let gen = restoreGeneration
        let src = CGEventSource(stateID: .hidSystemState)
        let v = Paster.keyCodeForV()
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        else {
            restoreIfOurs(write)
            return "키 이벤트를 만들지 못했습니다"
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.restoreGeneration == gen else { return }
            self.restoreIfOurs(write)
        }
        malgyeolLog(log)
        return note
    }
}
