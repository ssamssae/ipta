import AppKit
import Combine
import SwiftUI

enum AppPhase: String {
    case idle = "대기"
    case requestingMic = "마이크 권한"
    case recording = "녹음 중"
    case transcribing = "받아적는 중"
    case polishing = "다듬는 중"
    case downloading = "준비 파일 받는 중"
    case error = "오류"
}

@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .idle
    @Published var statusLine = "버튼을 누르면 받아 적습니다"
    @Published var transcript = ""
    @Published var rawTranscript = ""
    @Published var polishEnabled = true
    @Published var polishPlan = PolishPlan.load()
    @Published var polishKeyDraft = ""
    @Published var lastError = ""
    @Published var level: Double = 0
    @Published var elapsed: Double = 0
    @Published var maxSeconds: Double = MalgyeolInfo.maxSeconds
    @Published var micStatus = "확인 전"
    @Published var devices: [(id: String, name: String)] = []
    @Published var selectedDeviceId = ""
    @Published var downloadProgress: Double = 0
    @Published var downloadNote = ""
    @Published var modelReady = false
    @Published var axTrusted = false
    @Published var hotkeyNote = ""
    @Published var recording = false
    @Published var lastPasteNote = ""
    @Published var lockedSummary = ""
    @Published var showSettings = false
    @Published var toggleKey = HotKeySpec.defaultToggle
    @Published var cancelKey = HotKeySpec.defaultCancel
    @Published var capturingHotkey: HotKeyAction?
    @Published var micButton: MicButtonSpec?
    @Published var capturingMicButton = false
    @Published var settingsNotice = ""
    @Published var oauthNote = ""
    @Published var oauthReady = false
    @Published var oauthBlocked = false
    @Published var oauthWatching = false

    let recorder = Recorder()
    let models = ModelManager()
    let transcriber = Transcriber()
    let polisher = Polisher()
    let paster = Paster()

    private var jobs = JobToken()
    private var pendingWav: URL?
    private var lockedTarget: LockedTarget?
    private var lockedSelectedText = ""
    private var wantsAutoPaste = false
    private var hashChecked = false
    var onHotKeyChange: (() -> Void)?
    var onMicButtonChange: (() -> Void)?
    var onMicCaptureChange: ((Bool) -> Void)?
    private var micCaptureToken = 0
    private var oauthWatch: Task<Void, Never>?
    private let deviceKey = "malgyeol.selectedDeviceId"

    init() {
        toggleKey = HotKeySpec.load(prefix: "toggle", fallback: .defaultToggle)
        cancelKey = HotKeySpec.load(prefix: "cancel", fallback: .defaultCancel)
        selectedDeviceId = UserDefaults.standard.string(forKey: deviceKey) ?? ""
        micButton = MicButtonSpec.load()
        if UserDefaults.standard.object(forKey: "malgyeol.polish") != nil {
            polishEnabled = UserDefaults.standard.bool(forKey: "malgyeol.polish")
        }
        polishPlan = PolishPlan.load()
        polishPlan.save()
        polishKeyDraft = ""
        refreshOAuthStatus()
        NotificationCenter.default.addObserver(forName: .malgyeolDownload, object: nil, queue: .main) { [weak self] note in
            let frac = note.userInfo?["frac"] as? Double ?? 0
            let written = note.userInfo?["written"] as? Int64 ?? 0
            let expected = note.userInfo?["expected"] as? Int64 ?? Int64(MalgyeolInfo.modelBytes)
            Task { @MainActor in
                guard let self else { return }
                self.downloadProgress = frac
                let mb = Double(written) / 1_000_000
                let tot = Double(expected) / 1_000_000
                self.downloadNote = String(format: "받는 중 %.0f / %.0f MB", mb, tot)
            }
        }
    }

    func refreshPermissions() {
        micStatus = recorder.permissionLabel()
        axTrusted = Paster.isTrusted()
        devices = recorder.listDevices()
        let saved = UserDefaults.standard.string(forKey: deviceKey) ?? selectedDeviceId
        if devices.contains(where: { $0.id == saved }) {
            selectedDeviceId = saved
        } else if devices.contains(where: { $0.id == selectedDeviceId }) {
            // keep current
        } else if let first = devices.first {
            selectedDeviceId = first.id
        }
        let sizeOK = models.sizeLooksReady()
        modelReady = sizeOK
        if sizeOK {
            downloadNote = "준비됐어요. 말해도 됩니다."
            if !hashChecked {
                hashChecked = true
                models.verifyHashOffMain { [weak self] ok in
                    Task { @MainActor in
                        guard let self else { return }
                        if !ok {
                            self.modelReady = false
                            self.downloadNote = "준비 파일이 손상되어 다시 받아야 합니다"
                            self.hashChecked = false
                        }
                    }
                }
            }
        } else {
            hashChecked = false
            if phase != .downloading {
                downloadNote = "아직 준비 안 됐어요. 받기 버튼을 누르세요."
            }
        }
        refreshHotkeyNote()
    }

    func refreshHotkeyNote(base: String? = nil) {
        var line = base ?? "\(toggleKey.label()) 시작/정지 · \(cancelKey.label()) 취소"
        if let bound = micButton, !line.contains(bound.label) {
            line += " · \(bound.label)"
        }
        hotkeyNote = line
    }

    func setSelectedDevice(_ id: String) {
        selectedDeviceId = id
        UserDefaults.standard.set(id, forKey: deviceKey)
    }

    func beginMicButtonCapture() {
        capturingHotkey = nil
        capturingMicButton = true
        settingsNotice = "무선 마이크 버튼을 한 번 누르세요"
        micCaptureToken += 1
        let token = micCaptureToken
        onMicCaptureChange?(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.capturingMicButton, self.micCaptureToken == token else { return }
            self.cancelMicButtonCapture(timedOut: true)
        }
    }

    func cancelMicButtonCapture(timedOut: Bool = false) {
        capturingMicButton = false
        onMicCaptureChange?(false)
        settingsNotice = timedOut
            ? "시간이 지나 연결을 멈췄습니다. 다시 눌러 연결하세요."
            : "버튼 연결을 취소했습니다"
    }

    func applyMicButton(_ spec: MicButtonSpec) {
        spec.save()
        micButton = spec
        capturingMicButton = false
        onMicCaptureChange?(false)
        onMicButtonChange?()
        refreshHotkeyNote()
        settingsNotice = "\(spec.label) 으로 시작/정지를 연결했습니다"
    }

    func clearMicButton() {
        MicButtonSpec.clearSaved()
        micButton = nil
        capturingMicButton = false
        onMicCaptureChange?(false)
        onMicButtonChange?()
        refreshHotkeyNote()
        settingsNotice = "마이크 버튼 연결을 지웠습니다"
    }

    func toggle(fromHotkey: Bool) {
        switch phase {
        case .recording:
            stopAndTranscribe()
        case .downloading, .transcribing, .polishing, .requestingMic:
            cancel()
            start(fromHotkey: fromHotkey)
        default:
            start(fromHotkey: fromHotkey)
        }
    }

    func start(fromHotkey: Bool) {
        lastError = ""
        let job = jobs.bump()
        transcriber.cancel()
        cleanupWav()
        if fromHotkey {
            lockedTarget = TargetLock.capture()
            lockedSelectedText = TargetLock.selectedText()
            wantsAutoPaste = true
            lockedSummary = lockedTarget?.summary ?? ""
            if let why = lockedTarget?.refusalReason {
                lastPasteNote = "시작한 곳이 \(why)이라 끝나면 자동으로 넣지 않고 결과만 보관합니다."
            } else {
                lastPasteNote = ""
            }
            malgyeolLog("lock \(lockedSummary) refuse=\(lockedTarget?.refusalReason ?? "-") job=\(job)")
        } else {
            lockedTarget = nil
            lockedSelectedText = ""
            wantsAutoPaste = false
            lockedSummary = "창에서 시작 — 자동 붙여넣기 없음"
        }
        refreshPermissions()
        if !recorder.hasPermission() {
            phase = .requestingMic
            statusLine = "마이크 허용이 필요합니다"
            recorder.requestPermission { [weak self] ok in
                Task { @MainActor in
                    guard let self, self.jobs.isCurrent(job) else { return }
                    self.refreshPermissions()
                    if ok {
                        self.actuallyRecord(job: job)
                    } else {
                        self.phase = .error
                        self.lastError = "마이크가 거부되었습니다. 시스템 설정에서 입타를 허용하세요."
                        self.statusLine = "마이크 거부"
                    }
                }
            }
            return
        }
        actuallyRecord(job: job)
    }

    private func actuallyRecord(job: UInt64) {
        guard jobs.isCurrent(job) else { return }
        do {
            try recorder.start(deviceId: selectedDeviceId) { [weak self] level, elapsed in
                Task { @MainActor in
                    guard let self, self.jobs.isCurrent(job) else { return }
                    self.level = level
                    self.elapsed = elapsed
                    self.statusLine = String(format: "듣는 중 %.0f초 / %.0f초", elapsed, MalgyeolInfo.maxSeconds)
                    if elapsed >= MalgyeolInfo.maxSeconds {
                        self.stopAndTranscribe()
                    }
                }
            }
            recording = true
            phase = .recording
            statusLine = "듣는 중 — 같은 키로 멈춥니다"
            malgyeolLog("record start device=\(selectedDeviceId) job=\(job)")
        } catch {
            phase = .error
            lastError = "녹음을 시작하지 못했습니다: \(error.localizedDescription)"
            statusLine = "녹음 실패"
            malgyeolLog("record error \(error)")
        }
    }

    func cancel() {
        let job = jobs.bump()
        recorder.cancel()
        transcriber.cancel()
        polisher.cancel()
        models.cancel()
        cleanupWav()
        recording = false
        phase = .idle
        statusLine = "취소됨"
        level = 0
        elapsed = 0
        downloadProgress = 0
        wantsAutoPaste = false
        malgyeolLog("cancelled job=\(job)")
    }

    func stopAndTranscribe() {
        guard recording || phase == .recording else { return }
        recording = false
        let job = jobs.value
        let url: URL
        do {
            url = try recorder.stop()
        } catch {
            phase = .error
            lastError = "녹음 종료 실패: \(error.localizedDescription)"
            return
        }
        pendingWav = url
        level = 0
        func runSTT() {
            guard jobs.isCurrent(job) else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            phase = .transcribing
            statusLine = "받아적는 중"
            transcriber.transcribe(wav: url) { [weak self] result in
                Task { @MainActor in
                    try? FileManager.default.removeItem(at: url)
                    guard let self else { return }
                    if self.pendingWav == url { self.pendingWav = nil }
                    guard self.jobs.isCurrent(job) else { return }
                    switch result {
                    case .success(let text):
                        self.rawTranscript = text
                        if text.isEmpty {
                            self.transcript = ""
                            self.phase = .idle
                            self.statusLine = "알아들은 내용이 없습니다"
                            return
                        }
                        malgyeolLog("transcript chars=\(text.count) job=\(job)")
                        self.finishAfterTranscript(text, job: job)
                    case .failure(let err):
                        self.phase = .error
                        self.lastError = err.message
                        self.statusLine = "받아적기 실패"
                        malgyeolLog("stt fail \(err)")
                    }
                }
            }
        }
        if !models.sizeLooksReady() {
            phase = .downloading
            statusLine = "받아적기 파일을 받는 중입니다"
            models.download { [weak self] err in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.jobs.isCurrent(job) else {
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                    self.refreshPermissions()
                    if let err {
                        if err == "cancelled" { return }
                        try? FileManager.default.removeItem(at: url)
                        if self.pendingWav == url { self.pendingWav = nil }
                        self.phase = .error
                        self.lastError = err
                        self.statusLine = "준비 파일을 받지 못해 받아적지 못했습니다"
                    } else {
                        runSTT()
                    }
                }
            }
            return
        }
        runSTT()
    }

    func setPolishEnabled(_ on: Bool) {
        polishEnabled = on
        UserDefaults.standard.set(on, forKey: "malgyeol.polish")
    }

    func setPolishTier(_ tier: PolishTier) {
        var next = polishPlan
        next.tier = tier
        if tier == .free, next.provider.sendsOffDevice {
            next.provider = .apple
            next.model = PolishProvider.apple.defaultModel
        }
        polishPlan = next
        polishPlan.save()
        settingsNotice = "\(next.provider.hint)"
        refreshOAuthStatus()
    }

    func setPolishProvider(_ provider: PolishProvider) {
        if provider == .local, !LocalStudio.isInstalled {
            settingsNotice = "이 맥에는 20비·27비 파일이 없습니다. 애플 지능을 씁니다."
            var fallback = polishPlan
            fallback.provider = .apple
            fallback.model = PolishProvider.apple.defaultModel
            polishPlan = fallback
            polishPlan.save()
            return
        }
        var next = polishPlan
        next.provider = provider
        next.model = provider.defaultModel
        if provider.supportsOAuth {
            next.tier = .connected
            next.authMode = .oauth
        } else {
            next.authMode = .key
        }
        polishPlan = next
        polishPlan.save()
        polishKeyDraft = ""
        settingsNotice = provider.hint
        if !polishEnabled {
            setPolishEnabled(true)
        }
        refreshOAuthStatus()
        if polishPlan.usesOAuth {
            if oauthReady {
                settingsNotice = "\(provider.title) 연결됨"
            } else if oauthBlocked {
                settingsNotice = oauthNote
            } else {
                beginOAuthLogin()
            }
        }
    }

    func beginOAuthLogin() {
        guard polishPlan.provider.supportsOAuth else {
            settingsNotice = "이 모델은 로그인 창이 없습니다"
            return
        }
        if polishPlan.authMode != .oauth {
            polishPlan.authMode = .oauth
            polishPlan.save()
        }
        refreshOAuthStatus()
        if oauthReady {
            settingsNotice = "\(polishPlan.provider.title) 연결됨"
            return
        }
        if oauthBlocked {
            settingsNotice = oauthNote
            return
        }
        settingsNotice = OAuthCLI.startLogin(polishPlan.provider)
        watchOAuthUntilReady()
    }

    func setPolishAuthMode(_ mode: PolishAuthMode) {
        polishPlan.authMode = polishPlan.provider.supportsOAuth ? mode : .key
        polishPlan.save()
        settingsNotice = "\(polishPlan.authMode.title) 으로 연결합니다"
        refreshOAuthStatus()
    }

    func refreshOAuthStatus() {
        guard polishPlan.provider.supportsOAuth, polishPlan.tier == .connected else {
            oauthNote = ""
            oauthReady = false
            return
        }
        let probe = OAuthCLI.probe(polishPlan.provider)
        oauthNote = probe.note
        oauthReady = probe.ready
        oauthBlocked = probe.blocked
    }

    private func watchOAuthUntilReady() {
        oauthWatch?.cancel()
        oauthWatching = true
        let provider = polishPlan.provider
        oauthWatch = Task { [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                let probe = OAuthCLI.probe(provider)
                await MainActor.run {
                    guard let self else { return }
                    guard self.polishPlan.provider == provider else { return }
                    self.oauthNote = probe.note
                    self.oauthReady = probe.ready
                    self.oauthBlocked = probe.blocked
                    if probe.ready {
                        self.settingsNotice = "\(provider.title) 연결됨"
                        self.oauthWatching = false
                    } else if probe.blocked {
                        self.settingsNotice = probe.note
                        self.oauthWatching = false
                    }
                }
                if probe.ready || probe.blocked { return }
            }
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.oauthWatching = false
                if !self.oauthReady {
                    self.settingsNotice = "아직 로그인이 안 됐습니다. 브라우저에서 끝난 뒤 다시 눌러 보세요"
                }
            }
        }
    }

    func setLocalPolishModel(_ model: LocalPolishModel) {
        guard model.isPresent else {
            settingsNotice = "이 맥에는 \(model.title) 파일이 없습니다"
            return
        }
        var next = polishPlan
        next.provider = .local
        next.model = model.rawValue
        polishPlan = next
        polishPlan.save()
        settingsNotice = "\(model.title) 로 골랐습니다"
    }

    func savePolishKey() {
        KeychainBox.set(polishKeyDraft, provider: polishPlan.provider)
        polishKeyDraft = ""
        settingsNotice = KeychainBox.hasKey(polishPlan.provider) ? "키를 저장했습니다" : "키를 지웠습니다"
    }

    func clearPolishKey() {
        KeychainBox.delete(provider: polishPlan.provider)
        polishKeyDraft = ""
        settingsNotice = "키를 지웠습니다"
    }

    private func finishAfterTranscript(_ text: String, job: UInt64) {
        guard polishEnabled else {
            transcript = text
            phase = .idle
            statusLine = "받아 적었습니다"
            finishWithPasteIfNeeded()
            return
        }
        phase = .polishing
        statusLine = "말한 글을 다듬는 중"
        let selected = lockedSelectedText
        polisher.polish(raw: text, selected: selected, plan: polishPlan) { [weak self] result in
            Task { @MainActor in
                guard let self, self.jobs.isCurrent(job) else { return }
                self.transcript = result.skipPaste ? text : result.text
                self.phase = .idle
                self.statusLine = result.note
                if result.skipPaste { self.wantsAutoPaste = false }
                malgyeolLog("polish usedModel=\(result.usedModel) provider=\(self.polishPlan.provider.rawValue) chars=\(result.text.count)")
                self.finishWithPasteIfNeeded()
            }
        }
    }

    private func finishWithPasteIfNeeded() {
        guard wantsAutoPaste, let locked = lockedTarget else {
            lastPasteNote = "창에서 시작했거나 대상이 없어 자동으로 넣지 않았습니다. 복사를 쓰세요."
            return
        }
        wantsAutoPaste = false
        if !Paster.isTrusted() {
            lastPasteNote = "손쉬운 사용이 꺼져 있습니다. 결과는 보관했습니다."
            statusLine = lastPasteNote
            return
        }
        let note = paster.pasteLocked(transcript, expected: locked)
        lastPasteNote = note
        statusLine = note
        malgyeolLog("paste \(note)")
    }

    func copyTranscript() {
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        statusLine = "복사했습니다"
        lastPasteNote = statusLine
    }

    func downloadModel() {
        let job = jobs.bump()
        phase = .downloading
        statusLine = "받아적기 파일을 받습니다"
        downloadProgress = 0
        models.download { [weak self] err in
            Task { @MainActor in
                guard let self, self.jobs.isCurrent(job) else { return }
                self.hashChecked = false
                self.refreshPermissions()
                if let err {
                    if err == "cancelled" {
                        self.phase = .idle
                        self.statusLine = "받기를 취소했습니다"
                        return
                    }
                    self.phase = .error
                    self.lastError = err
                    self.statusLine = "받기 실패 — 다시 시도할 수 있습니다"
                } else {
                    self.phase = .idle
                    self.statusLine = "말한 소리를 글로 바꿀 준비가 되었습니다"
                }
            }
        }
    }

    func openProviderInstallPage() {
        guard let url = polishPlan.provider.installURL else {
            settingsNotice = "받는 곳 주소를 모릅니다"
            return
        }
        NSWorkspace.shared.open(url)
        settingsNotice = "\(polishPlan.provider.title) 받는 곳을 열었습니다"
    }

    func openMicSettings() { PrivacySettings.openMicrophone() }
    func openAxSettings() {
        _ = Paster.promptTrust()
        PrivacySettings.openAccessibility()
    }

    func applyHotKeys(toggle: HotKeySpec, cancel: HotKeySpec) {
        toggle.save(prefix: "toggle")
        cancel.save(prefix: "cancel")
        toggleKey = toggle
        cancelKey = cancel
        capturingHotkey = nil
        capturingMicButton = false
        onMicCaptureChange?(false)
        onHotKeyChange?()
        refreshPermissions()
    }

    private func cleanupWav() {
        if let u = pendingWav {
            try? FileManager.default.removeItem(at: u)
            pendingWav = nil
        }
    }
}
