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

    /// 입타는 메뉴바 아이콘과 함께 일반 Dock 앱으로 남는다: Dock 실행 점과 왼쪽 위 앱 메뉴가 항상 보인다.
    static let restingActivationPolicy: NSApplication.ActivationPolicy = .regular

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Self.restingActivationPolicy)
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
        let main = Self.makeMainMenu(target: self)
        NSApp.mainMenu = main
        NSApp.windowsMenu = main.items.first { $0.submenu?.title == "윈도우" }?.submenu
    }

    /// 왼쪽 위 앱 메뉴. target 이 nil 이면 입타 전용 항목도 응답 체인으로 보낸다(자가검사용).
    static func makeMainMenu(target: AnyObject?) -> NSMenu {
        func item(_ title: String, _ action: Selector, _ key: String = "",
                  _ mods: NSEvent.ModifierFlags = .command, own: Bool = false) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
            it.keyEquivalentModifierMask = mods
            if own { it.target = target }
            return it
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            return holder
        }
        let main = NSMenu()
        main.addItem(submenu("입타", [
            item("입타에 관하여", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("설정…", #selector(AppDelegate.openSettings), ",", own: true),
            .separator(),
            item("입타 가리기", #selector(NSApplication.hide(_:)), "h"),
            item("기타 가리기", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("모두 보기", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("입타 종료", #selector(AppDelegate.quit), "q", own: true),
        ]))
        main.addItem(submenu("파일", [
            item("입타 창 열기", #selector(AppDelegate.showPanel), "n", own: true),
            item("닫기", #selector(AppDelegate.closeKeyWindow), "w", own: true),
        ]))
        main.addItem(submenu("편집", [
            item("실행 취소", Selector(("undo:")), "z"),
            item("실행 복귀", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("오려두기", #selector(NSText.cut(_:)), "x"),
            item("복사하기", #selector(NSText.copy(_:)), "c"),
            item("붙여넣기", #selector(NSText.paste(_:)), "v"),
            item("전체 선택", #selector(NSText.selectAll(_:)), "a"),
        ]))
        main.addItem(submenu("윈도우", [
            item("최소화", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("확대/축소", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("모두 앞으로 가져오기", #selector(NSApplication.arrangeInFront(_:))),
        ]))
        return main
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
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        state.refreshPermissions()
    }

    @objc func hidePanel() {
        state.showSettings = false
        settingsWindow?.orderOut(nil)
        panel?.orderOut(nil)
        // 창을 숨기면 원래 쓰던 앱으로 포커스를 돌려준다. Dock 점은 그대로 남는다.
        if NSApp.isActive {
            NSApp.deactivate()
        }
    }

    @objc func openSettings() {
        if state.showSettings {
            showSettingsWindow()
        } else {
            state.showSettings = true
        }
    }

    private func showSettingsWindow() {
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
