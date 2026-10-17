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
        bundleId == MalgyeolInfo.bundleId
            || appName == MalgyeolInfo.productKo
            || appName == MalgyeolInfo.productEn
            || appName == "말결"
            || appName == "Malgyeol"
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
        if isMalgyeol { return "입타 창" }
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
    /// AX 호출 하나당 기다리는 상한(초). 느린 앱(브라우저·일렉트론)이 단축키 반응을 잡아먹지 않게 한다.
    static let axTimeout: Float = 0.3

    static func capture() -> LockedTarget {
        let started = Date()
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
            AXUIElementSetMessagingTimeout(appEl, axTimeout)
            var focusedEl = copyAX(appEl, kAXFocusedUIElementAttribute as String)
            if focusedEl == nil, enableEnhancedUserInterface(appEl, bundleId: bundle) {
                focusedEl = copyAX(appEl, kAXFocusedUIElementAttribute as String)
            }
            if let focused = focusedEl {
                AXUIElementSetMessagingTimeout(focused, axTimeout)
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
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        if ms > 200 { malgyeolLog("lock capture slow \(ms)ms app=\(name) role=\(role.isEmpty ? "?" : role)") }
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
        selectedText(of: capture())
    }

    /// 이미 잡아 둔 대상에서 선택 글만 읽는다. 녹음 시작 때 접근성 트리를 두 번 훑지 않으려고 둔다.
    static func selectedText(of target: LockedTarget?) -> String {
        guard let el = target?.element else { return "" }
        return axString(el, kAXSelectedTextAttribute as String)
    }

    /// 앞 글을 읽지 않는 앱(비밀번호 관리자·키체인). 접두사 비교.
    static let contextBlockedBundlePrefixes = [
        "com.1password", "com.agilebits", "com.lastpass", "com.bitwarden", "com.dashlane",
        "com.apple.keychainaccess", "com.apple.Passwords",
    ]

    /// 다듬기 문맥으로 앞 글을 읽어도 되는 대상인지(순수 판정, 검사용).
    nonisolated static func contextAllowed(bundleId: String, secure: Bool, role: String, subrole: String) -> Bool {
        if secure || role == "AXSecureTextField" || subrole == "AXSecureTextField" { return false }
        return !contextBlockedBundlePrefixes.contains { bundleId.hasPrefix($0) }
    }

    /// 잠근 입력칸에서 커서(또는 선택 시작) 앞 글을 최대 maxChars 자 읽는다. 다듬기 문맥용.
    /// 값 전체를 복사하지 않고 범위 문자열(kAXStringForRange)을 먼저 쓰고, 없으면 5만 자 이하일 때만 값에서 자른다.
    static func contextBefore(_ target: LockedTarget?, maxChars: Int = 500) -> String {
        guard let target, let el = target.element else { return "" }
        guard contextAllowed(bundleId: target.bundleId, secure: target.secure, role: target.role, subrole: target.subrole) else { return "" }
        guard let range = selectedRange(el), range.location > 0 else { return "" }
        let end = range.location
        let start = max(0, end - maxChars)
        let want = CFRange(location: start, length: end - start)
        if let s = stringForRange(el, want) { return s }
        let count = axInt(el, kAXNumberOfCharactersAttribute as String) ?? 0
        guard count <= 50_000 else { return "" }
        let value = axString(el, kAXValueAttribute as String) as NSString
        guard end <= value.length else { return "" }
        return value.substring(with: NSRange(location: start, length: end - start))
    }

    static func selectedRange(_ el: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue((value as! AXValue), .cfRange, &range) else { return nil }
        return range
    }

    static func stringForRange(_ el: AXUIElement, _ range: CFRange) -> String? {
        var r = range
        guard let param = AXValueCreate(.cfRange, &r) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXStringForRangeParameterizedAttribute as CFString, param, &value) == .success else {
            return nil
        }
        return value as? String
    }

    static func axInt(_ el: AXUIElement, _ attr: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return (value as? Int) ?? (value as? NSNumber)?.intValue
    }

    /// 크롬·일렉트론 계열은 AXEnhancedUserInterface 를 켜야 입력칸을 접근성 트리에 내놓는다.
    /// 포커스 요소를 못 찾았을 때만 한 번 켜고 잠깐 기다린다. 끄지는 않는다(앱을 다시 켤 때 풀린다).
    static func enableEnhancedUserInterface(_ appEl: AXUIElement, bundleId: String) -> Bool {
        let attr = "AXEnhancedUserInterface" as CFString
        var current: CFTypeRef?
        if AXUIElementCopyAttributeValue(appEl, attr, &current) == .success,
           ((current as? Bool) ?? (current as? NSNumber)?.boolValue) == true {
            return false
        }
        guard AXUIElementSetAttributeValue(appEl, attr, kCFBooleanTrue) == .success else { return false }
        malgyeolLog("lock enhanced-ui on \(bundleId)")
        Thread.sleep(forTimeInterval: 0.08)
        return true
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
