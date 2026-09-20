import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = AppState()
    private var statusItem: NSStatusItem?
    private var panel: NSWindow?
    private var settingsWindow: NSWindow?
    private var hud: NSPanel?
    private var bags = Set<AnyCancellable>()
    private var hotkeys: HotKeyCenter?
    private var micButtons: MicButtonCenter?
    private var menu: NSMenu?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        state.refreshPermissions()
        setupMainMenu()
        setupStatusItem()
        setupPanel()
        setupSettingsWindow()
        setupHUD()
        state.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncActivityChrome()
            }
            .store(in: &bags)
        state.$recording
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncActivityChrome()
            }
            .store(in: &bags)
        state.$showSettings
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                if show {
                    self?.showSettingsWindow()
                } else {
                    self?.settingsWindow?.orderOut(nil)
                }
            }
            .store(in: &bags)
        state.onHidePanel = { [weak self] in
            self?.hidePanel()
        }
        hotkeys = HotKeyCenter(toggle: state.toggleKey, cancel: state.cancelKey) { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggle:
                self.hidePanel()
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
            self?.hidePanel()
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
            if HotKeySpec.isCommandQ(event) {
                self.quit()
                return nil
            }
            if self.state.capturingMicButton {
                if HotKeySpec.isEscape(event) {
                    self.state.cancelMicButtonCapture()
                    return nil
                }
                return event
            }
            if let which = self.state.capturingHotkey {
                if HotKeySpec.isEscape(event) {
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
            if self.shouldCloseSettings(for: event) {
                self.closeSettingsWindow()
                return nil
            }
            if self.shouldHideMainWindow(for: event) {
                self.hidePanel()
                return nil
            }
            return event
        }
        malgyeolLog("launch \(MalgyeolInfo.label) ax=\(state.axTrusted)")
        if !state.axTrusted {
            _ = Paster.promptTrust()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        showPanel()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupMainMenu() {
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "입타 종료", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let fileMenu = NSMenu(title: "파일")
        let closeItem = NSMenuItem(title: "닫기", action: #selector(closeKeyWindow), keyEquivalent: "w")
        closeItem.target = self
        fileMenu.addItem(closeItem)
        let fileItem = NSMenuItem()
        fileItem.submenu = fileMenu
        let main = NSMenu()
        main.addItem(appItem)
        main.addItem(fileItem)
        NSApp.mainMenu = main
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = item.button {
            btn.image = NSImage(systemSymbolName: RecordingHUD.statusSymbol(phase: .idle), accessibilityDescription: MalgyeolInfo.label)
            btn.toolTip = MalgyeolInfo.label
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: "입타 창 열기", action: #selector(showPanel), keyEquivalent: "")
        let hide = NSMenuItem(title: "입타 창 숨기기", action: #selector(hidePanel), keyEquivalent: "")
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
        for it in [open, hide, rec, cancel, quit] { it.target = self }
        menu.addItem(open)
        menu.addItem(hide)
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
        let panel = NSWindow(
            contentRect: view.frame,
            styleMask: Self.mainStyleMask,
            backing: .buffered,
            defer: false
        )
        panel.title = MalgyeolInfo.label
        panel.contentView = view
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.hidesOnDeactivate = true
        panel.minSize = NSSize(width: 320, height: 280)
        panel.delegate = self
        self.panel = panel
    }

    private func setupHUD() {
        hud = RecordingHUD.makePanel(state: state)
    }

    private func syncActivityChrome() {
        if let btn = statusItem?.button {
            let symbol = RecordingHUD.statusSymbol(phase: state.phase)
            btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: MalgyeolInfo.label)
            btn.contentTintColor = state.recording ? .systemRed : nil
            if RecordingHUD.shouldShow(phase: state.phase) {
                btn.toolTip = "입타 · \(RecordingHUD.title(for: state.phase))"
            } else {
                btn.toolTip = MalgyeolInfo.label
            }
        }
        guard let hud else { return }
        if RecordingHUD.shouldShow(phase: state.phase) {
            RecordingHUD.place(hud)
            hud.orderFrontRegardless()
        } else {
            hud.orderOut(nil)
        }
    }

    private func setupSettingsWindow() {
        let view = NSHostingView(rootView: SettingsView(state: state))
        view.frame = NSRect(x: 0, y: 0, width: 440, height: 640)
        let win = NSWindow(
            contentRect: view.frame,
            styleMask: Self.settingsStyleMask,
            backing: .buffered,
            defer: false
        )
        win.title = "입타 설정"
        win.contentView = view
        win.isReleasedWhenClosed = false
        win.level = .normal
        win.hidesOnDeactivate = false
        win.isMovable = true
        win.isMovableByWindowBackground = true
        win.titleVisibility = .visible
        win.titlebarAppearsTransparent = false
        win.minSize = NSSize(width: 420, height: 360)
        win.delegate = self
        settingsWindow = win
    }

    @objc func showPanel() {
        NSApp.setActivationPolicy(.regular)
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        state.refreshPermissions()
    }

    @objc func hidePanel() {
        state.showSettings = false
        settingsWindow?.orderOut(nil)
        panel?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    private func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        if settingsWindow == nil {
            setupSettingsWindow()
        }
        if let settings = settingsWindow {
            if let main = panel {
                var frame = settings.frame
                frame.origin.x = main.frame.maxX + 20
                frame.origin.y = main.frame.maxY - frame.height
                settings.setFrame(frame, display: false)
            }
            settings.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        state.refreshPermissions()
        state.refreshOAuthStatus()
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSObject === settingsWindow {
            state.showSettings = false
            if panel?.isVisible != true {
                NSApp.setActivationPolicy(.accessory)
            }
            return
        }
        if settingsWindow?.isVisible != true {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    static let settingsStyleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
    static let mainStyleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]

    func shouldCloseSettings(for event: NSEvent) -> Bool {
        guard settingsWindow?.isVisible == true || state.showSettings else { return false }
        let settingsIsTarget = settingsWindow?.isKeyWindow == true
            || event.window === settingsWindow
            || panel?.isKeyWindow != true
        guard settingsIsTarget else { return false }
        return HotKeySpec.closesSettingsWindow(event)
    }

    @objc func closeSettingsWindow() {
        state.showSettings = false
        settingsWindow?.orderOut(nil)
    }

    func shouldHideMainWindow(for event: NSEvent) -> Bool {
        guard panel?.isVisible == true else { return false }
        let mainIsTarget = panel?.isKeyWindow == true || event.window === panel
        guard mainIsTarget else { return false }
        return HotKeySpec.closesSettingsWindow(event)
    }

    @objc func closeKeyWindow() {
        if settingsWindow?.isKeyWindow == true || (state.showSettings && panel?.isKeyWindow != true) {
            closeSettingsWindow()
            return
        }
        hidePanel()
    }

    @objc func toggle() { state.toggle(fromHotkey: false) }
    @objc func cancel() { state.cancel() }
    @objc func quit() {
        state.cancel()
        micButtons?.stop()
        NSApp.terminate(nil)
    }
}
