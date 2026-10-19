#!/usr/bin/env swift
// TextEdit 이 떠 있는지와 자체검사 시험 문서(r4-malgyeol-r4-*) 창 수를 AX 로 센다(T-261017-030).
// AppleScript 를 쓰지 않으므로 자동화 허용 질문 창을 띄우지 않는다. 화면이 잠겨 있으면 창은 0 으로 보인다.
import AppKit
import ApplicationServices

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit")
var windows = 0
for app in apps {
    var list: CFTypeRef?
    let el = AXUIElementCreateApplication(app.processIdentifier)
    guard AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &list) == .success,
          let wins = list as? [AXUIElement] else { continue }
    for w in wins {
        var role: CFTypeRef?
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(w, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &title)
        if role as? String == "AXWindow", (title as? String)?.hasPrefix("r4-malgyeol-r4-") == true {
            windows += 1
        }
    }
}
print("running=\(apps.isEmpty ? 0 : 1) test_windows=\(windows)")
