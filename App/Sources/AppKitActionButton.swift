import AppKit
import SwiftUI

/// AppKit `NSButton` hosted in SwiftUI.
/// Hermes crash-r2-115945.ips died inside SwiftUI `_ButtonGesture` → `MainActor.assumeIsolated`
/// during `NSWindow _handleMouseDownEvent` (no app action frame). This control does not use
/// `_ButtonGesture`. Layout stays SwiftUI. Not a claim that Vulkan reproduced the SIGSEGV.
struct AppKitActionButton: NSViewRepresentable {
    var title: String
    var identifier: String = ""
    var prominent: Bool = false
    var danger: Bool = false
    var enabled: Bool = true
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let b = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.tap))
        b.bezelStyle = .rounded
        b.controlSize = .large
        b.setButtonType(.momentaryPushIn)
        b.setContentHuggingPriority(.defaultLow, for: .horizontal)
        b.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if !identifier.isEmpty {
            b.setAccessibilityIdentifier(identifier)
        }
        b.setAccessibilityLabel(title)
        apply(b)
        return b
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.action = action
        if nsView.title != title {
            nsView.title = title
            nsView.setAccessibilityLabel(title)
        }
        nsView.isEnabled = enabled
        apply(nsView)
    }

    private func apply(_ b: NSButton) {
        b.bezelColor = prominent ? (danger ? .systemRed : .controlAccentColor) : nil
        b.keyEquivalent = ""
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}
