import AppKit
import Carbon
import Foundation

enum HotKeyAction { case toggle, cancel }

struct HotKeySpec: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultToggle = HotKeySpec(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(optionKey))
    static let defaultCancel = HotKeySpec(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey | shiftKey))

    func label() -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += HotKeySpec.keyName(keyCode)
        return s
    }

    static func from(event: NSEvent) -> HotKeySpec? {
        if event.keyCode == UInt16(kVK_Escape) { return nil }
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
        if mods == 0 { return nil }
        return HotKeySpec(keyCode: UInt32(event.keyCode), modifiers: mods)
    }

    static func load(prefix: String, fallback: HotKeySpec) -> HotKeySpec {
        let d = UserDefaults.standard
        let key = d.object(forKey: "malgyeol.\(prefix).keyCode") as? Int
        let mods = d.object(forKey: "malgyeol.\(prefix).modifiers") as? Int
        guard let key, let mods else { return fallback }
        return HotKeySpec(keyCode: UInt32(key), modifiers: UInt32(mods))
    }

    func save(prefix: String) {
        UserDefaults.standard.set(Int(keyCode), forKey: "malgyeol.\(prefix).keyCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "malgyeol.\(prefix).modifiers")
    }

    static func keyName(_ code: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab", UInt32(kVK_Delete): "Delete",
        ]
        return map[code] ?? "(\(code))"
    }
}

final class HotKeyCenter {
    private var toggleRef: EventHotKeyRef?
    private var cancelRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var statusText = ""
    private let callback: (HotKeyAction) -> Void
    private nonisolated(unsafe) static var instance: HotKeyCenter?

    init(toggle: HotKeySpec, cancel: HotKeySpec, callback: @escaping (HotKeyAction) -> Void) {
        self.callback = callback
        HotKeyCenter.instance = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hk
            )
            if hk.id == 1 { HotKeyCenter.instance?.callback(.toggle) }
            if hk.id == 2 { HotKeyCenter.instance?.callback(.cancel) }
            return noErr
        }, 1, &spec, nil, &handler)
        rebind(toggle: toggle, cancel: cancel)
    }

    func rebind(toggle: HotKeySpec, cancel: HotKeySpec) {
        if let toggleRef { UnregisterEventHotKey(toggleRef) }
        if let cancelRef { UnregisterEventHotKey(cancelRef) }
        toggleRef = nil
        cancelRef = nil
        var notes: [String] = []
        let toggleID = EventHotKeyID(signature: OSType(0x4D4C474C), id: 1)
        let cancelID = EventHotKeyID(signature: OSType(0x4D4C474C), id: 2)
        let tStat = RegisterEventHotKey(toggle.keyCode, toggle.modifiers, toggleID, GetApplicationEventTarget(), 0, &toggleRef)
        if tStat == noErr {
            notes.append("\(toggle.label()) 시작/정지")
        } else {
            notes.append("\(toggle.label()) 등록 실패 — 다른 앱과 겹칩니다 (code=\(tStat)). 설정에서 바꾸세요.")
        }
        let cStat = RegisterEventHotKey(cancel.keyCode, cancel.modifiers, cancelID, GetApplicationEventTarget(), 0, &cancelRef)
        if cStat == noErr {
            notes.append("\(cancel.label()) 취소")
        } else {
            notes.append("\(cancel.label()) 등록 실패 — 다른 앱과 겹칩니다 (code=\(cStat)). 설정에서 바꾸세요.")
        }
        statusText = notes.joined(separator: " · ")
        malgyeolLog("hotkeys \(statusText)")
    }

    deinit {
        if let toggleRef { UnregisterEventHotKey(toggleRef) }
        if let cancelRef { UnregisterEventHotKey(cancelRef) }
    }
}
