#!/usr/bin/env swift
import CoreGraphics
import Foundation

let want = CommandLine.arguments.dropFirst()
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for info in list {
    let owner = info[kCGWindowOwnerName as String] as? String ?? ""
    let name = info[kCGWindowName as String] as? String ?? ""
    let id = info[kCGWindowNumber as String] as? Int ?? 0
    let bounds = info[kCGWindowBounds as String] as? [String: Any]
    let blob = (owner + " " + name).lowercased()
    let matches: Bool
    if want.isEmpty {
        matches = blob.contains("malgyeol") || blob.contains("말결") || owner.contains("SecurityAgent") || name.contains("마이크")
    } else {
        matches = want.contains { blob.contains($0.lowercased()) }
    }
    if matches {
        let w = bounds?["Width"] ?? "?"
        let h = bounds?["Height"] ?? "?"
        let x = bounds?["X"] ?? "?"
        let y = bounds?["Y"] ?? "?"
        print("id=\(id)\towner=\(owner)\tname=\(name)\tsize=\(w)x\(h)\torigin=\(x),\(y)")
    }
}
