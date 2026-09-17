import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var hotkeys: HotKeyCenter?
    private var micButtons: MicButtonCenter?
    private var menu: NSMenu?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        state.refreshPermissions()
        setupStatusItem()
        setupPanel()
        hotkeys = HotKeyCenter(toggle: state.toggleKey, cancel: state.cancelKey) { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggle:
                self.state.toggle(fromHotkey: true)
            case .cancel:
                self.state.cancel()
            }
        }
        state.refreshHotkeyNote(base: hotkeys?.statusText)
        state.onHotKeyChange = { [weak self] in
            guard let self else { return }
            self.hotkeys?.rebind(toggle: self.state.toggleKey, cancel: self.state.cancelKey)
            self.state.refreshHotkeyNote(base: self.hotkeys?.statusText)
            self.rebuildMenu()
        }
        let buttons = MicButtonCenter()
        buttons.onCapture = { [weak self] spec in
            self?.state.applyMicButton(spec)
        }
        buttons.onToggle = { [weak self] in
            self?.state.toggle(fromHotkey: true)
        }
        buttons.start()
        micButtons = buttons
        state.onMicButtonChange = { [weak self] in
            self?.micButtons?.bound = self?.state.micButton
            self?.state.refreshHotkeyNote()
        }
        state.onMicCaptureChange = { [weak self] capturing in
            self?.micButtons?.capturing = capturing
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.state.capturingMicButton {
                if event.keyCode == UInt16(kVK_Escape) {
                    self.state.cancelMicButtonCapture()
                    return nil
                }
                return event
            }
            guard let which = self.state.capturingHotkey else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.state.capturingHotkey = nil
                return nil
            }
            guard let spec = HotKeySpec.from(event: event) else {
                self.state.settingsNotice = "Option 또는 Command를 함께 누르세요"
                return nil
            }
            var toggle = self.state.toggleKey
            var cancel = self.state.cancelKey
            switch which {
            case .toggle: toggle = spec
            case .cancel: cancel = spec
            }
            if toggle.keyCode == cancel.keyCode && toggle.modifiers == cancel.modifiers {
                self.state.settingsNotice = "시작과 취소에 같은 키를 쓸 수 없습니다"
                self.state.capturingHotkey = nil
                return nil
            }
            self.state.applyHotKeys(toggle: toggle, cancel: cancel)
            self.state.settingsNotice = "단축키를 \(spec.label()) 로 바꿨습니다"
            return nil
        }
        malgyeolLog("launch \(MalgyeolInfo.label) ax=\(state.axTrusted)")
        if !state.axTrusted {
            _ = Paster.promptTrust()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = item.button {
            btn.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: MalgyeolInfo.label)
            btn.toolTip = MalgyeolInfo.label
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: "말결 창 열기", action: #selector(showPanel), keyEquivalent: "")
        let rec = NSMenuItem(
            title: "시작/정지 (\(state.toggleKey.label()))",
            action: #selector(toggle),
            keyEquivalent: ""
        )
        let cancel = NSMenuItem(
            title: "취소 (\(state.cancelKey.label()))",
            action: #selector(cancel),
            keyEquivalent: ""
        )
        let quit = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        for it in [open, rec, cancel, quit] { it.target = self }
        menu.addItem(open)
        menu.addItem(rec)
        menu.addItem(cancel)
        menu.addItem(.separator())
        menu.addItem(quit)
        statusItem?.menu = menu
        self.menu = menu
    }

    private func setupPanel() {
        let view = NSHostingView(rootView: ResultView(state: state))
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 520)
        let panel = NSPanel(
            contentRect: view.frame,
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = MalgyeolInfo.label
        panel.contentView = view
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 320, height: 280)
        self.panel = panel
        panel.orderFrontRegardless()
    }

    @objc func showPanel() {
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        state.refreshPermissions()
    }

    @objc func toggle() { state.toggle(fromHotkey: false) }
    @objc func cancel() { state.cancel() }
    @objc func quit() {
        state.cancel()
        micButtons?.stop()
        NSApp.terminate(nil)
    }
}
