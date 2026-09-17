import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

/// Snapshot of the input target taken when a hotkey recording starts.
/// Auto-paste is allowed only when the *same* focused, editable text element
/// (CFEqual identity) in the same app and window is still focused at paste time.
struct LockedTarget {
    var pid: pid_t
    var bundleId: String
    var appName: String
    var windowNumber: Int
    var role: String
    var subrole: String
    var identifier: String
    var enabled: Bool
    var valueSettable: Bool
    var secure: Bool
    var axTrusted: Bool
    var element: AXUIElement?
    var windowElement: AXUIElement?

    static let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

    var isMalgyeol: Bool {
        bundleId == MalgyeolInfo.bundleId || appName == MalgyeolInfo.productKo || appName == MalgyeolInfo.productEn
    }

    /// We actually know what we are looking at.
    var isTrustworthy: Bool {
        axTrusted && pid != 0 && windowNumber != 0 && element != nil && !role.isEmpty
    }

    /// Only real, enabled, writable text inputs. Sheets/windows/unknown roles/secure fields are refused.
    var isEditableTextInput: Bool {
        guard isTrustworthy else { return false }
        if secure || role == "AXSecureTextField" || subrole == "AXSecureTextField" { return false }
        guard LockedTarget.editableRoles.contains(role) else { return false }
        return enabled && valueSettable
    }

    /// Human-readable reason auto-paste is refused, or nil if allowed.
    var refusalReason: String? {
        if isMalgyeol { return "말결 창" }
        if !axTrusted { return "손쉬운 사용 꺼짐" }
        if pid == 0 { return "앞 앱 없음" }
        if windowNumber == 0 { return "창을 확인하지 못함" }
        if element == nil { return "입력칸을 확인하지 못함" }
        if role.isEmpty { return "역할 없음" }
        if secure || role == "AXSecureTextField" || subrole == "AXSecureTextField" { return "암호 칸" }
        if !LockedTarget.editableRoles.contains(role) { return "입력칸이 아님 (\(role))" }
        if !enabled { return "비활성 칸" }
        if !valueSettable { return "읽기 전용 칸" }
        return nil
    }

    var summary: String {
        let win = windowNumber == 0 ? "?" : "\(windowNumber)"
        let r = role.isEmpty ? "?" : role
        return "\(appName) pid=\(pid) win=\(win) \(r)\(subrole.isEmpty ? "" : "/\(subrole)") el=\(element == nil ? "nil" : "ok")"
    }
}

enum TargetLock {
    static func capture() -> LockedTarget {
        let front = NSWorkspace.shared.frontmostApplication
        let pid = front?.processIdentifier ?? 0
        let bundle = front?.bundleIdentifier ?? ""
        let name = front?.localizedName ?? "?"
        let windowNumber = frontWindowNumber(pid: pid)
        var role = ""
        var subrole = ""
        var identifier = ""
        var enabled = false
        var settable = false
        var secure = IsSecureEventInputEnabled()
        var element: AXUIElement?
        var windowEl: AXUIElement?
        let trusted = AXIsProcessTrusted()
        if trusted, pid != 0 {
            let appEl = AXUIElementCreateApplication(pid)
            if let focused = copyAX(appEl, kAXFocusedUIElementAttribute as String) {
                element = focused
                role = axString(focused, kAXRoleAttribute as String)
                subrole = axString(focused, kAXSubroleAttribute as String)
                identifier = axString(focused, kAXIdentifierAttribute as String)
                // AXEnabled is optional on text areas (TextEdit omits it). Present+false → disabled.
                enabled = axBool(focused, kAXEnabledAttribute as String) ?? true
                settable = isSettable(focused, kAXValueAttribute as String)
                windowEl = copyAX(focused, kAXWindowAttribute as String)
            }
        }
        if role == "AXSecureTextField" || subrole == "AXSecureTextField" {
            secure = true
        }
        return LockedTarget(
            pid: pid,
            bundleId: bundle,
            appName: name,
            windowNumber: windowNumber,
            role: role,
            subrole: subrole,
            identifier: identifier,
            enabled: enabled,
            valueSettable: settable,
            secure: secure,
            axTrusted: trusted,
            element: element,
            windowElement: windowEl
        )
    }

    /// Strict identity match. Unknown → false.
    static func matches(_ locked: LockedTarget, _ current: LockedTarget) -> Bool {
        guard locked.isTrustworthy, current.isTrustworthy else { return false }
        guard locked.pid == current.pid else { return false }
        guard locked.bundleId == current.bundleId else { return false }
        guard locked.windowNumber == current.windowNumber else { return false }
        guard locked.role == current.role, locked.subrole == current.subrole else { return false }
        guard let a = locked.element, let b = current.element, CFEqual(a, b) else { return false }
        if let wa = locked.windowElement, let wb = current.windowElement, !CFEqual(wa, wb) {
            return false
        }
        return true
    }

    static func selectedText() -> String {
        let snap = capture()
        guard let el = snap.element else { return "" }
        return axString(el, kAXSelectedTextAttribute as String)
    }

    static func frontWindowNumber(pid: pid_t) -> Int {
        guard pid != 0 else { return 0 }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }
        for info in list {
            let owner = info[kCGWindowOwnerPID as String] as? pid_t
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if owner == pid, layer == 0 {
                return info[kCGWindowNumber as String] as? Int ?? 0
            }
        }
        return 0
    }

    static func copyAX(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, attr as CFString, &value)
        guard err == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func axString(_ el: AXUIElement, _ attr: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return "" }
        return (value as? String) ?? ""
    }

    static func axBool(_ el: AXUIElement, _ attr: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue
    }

    static func isSettable(_ el: AXUIElement, _ attr: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(el, attr as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }
}

enum PrivacySettings {
    static func openAccessibility() {
        open([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ])
    }

    static func openMicrophone() {
        open([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone",
        ])
    }

    private static func open(_ urls: [String]) {
        for s in urls {
            if let u = URL(string: s) {
                NSWorkspace.shared.open(u)
                return
            }
        }
    }
}
