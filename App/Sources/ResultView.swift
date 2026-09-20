import Carbon
import SwiftUI

struct ResultView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(MalgyeolInfo.label)
                    .font(.title.weight(.semibold))
                Text("받아적기는 이 Mac에서만 합니다. 다듬기는 선택입니다. 그록·커서·클로드를 쓰려면 그 프로그램을 이 맥에 두고 본인 계정으로 로그인하세요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                AppKitActionButton(
                    title: state.recording ? "정지" : "녹음",
                    identifier: "malgyeol-main-toggle",
                    prominent: true,
                    danger: state.recording,
                    action: { state.toggle(fromHotkey: false) }
                )
                .frame(maxWidth: .infinity, minHeight: 36)

                if state.phase == .downloading || state.phase == .transcribing || state.phase == .polishing || state.phase == .requestingMic {
                    AppKitActionButton(title: "취소", identifier: "malgyeol-cancel", action: { state.cancel() })
                        .frame(maxWidth: .infinity, minHeight: 28)
                }

                statusBlock
                firstRunBlock
                resultBlock

                if !state.lastError.isEmpty {
                    Text(state.lastError)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    AppKitActionButton(title: "설정", identifier: "malgyeol-settings", action: { state.showSettings = true })
                        .frame(width: 80, height: 24)
                    AppKitActionButton(title: "숨기기", identifier: "malgyeol-hide", action: { state.hidePanel() })
                        .frame(width: 80, height: 24)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 320, minHeight: 280)
        .onAppear { state.refreshPermissions() }
    }

    @ViewBuilder
    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.statusLine)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if state.recording {
                ProgressView(value: state.level) { Text("소리") }
                ProgressView(value: min(1, state.elapsed / state.maxSeconds)) {
                    Text(String(format: "%.0f / %.0f초", state.elapsed, state.maxSeconds))
                }
            }
            if state.phase == .downloading {
                ProgressView(value: state.downloadProgress)
                Text(state.downloadNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !state.lastPasteNote.isEmpty {
                Text(state.lastPasteNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var firstRunBlock: some View {
        if state.micStatus != "허용" {
            guidance(
                title: "마이크 허용",
                body: "처음이면 입타가 마이크를 쓰는지 물어봅니다. 허용해야 받아 적을 수 있습니다.",
                action: "마이크 설정 열기",
                run: state.openMicSettings
            )
        }
        if !state.modelReady, state.phase != .downloading {
            guidance(
                title: "말한 소리를 글로 바꿀 준비",
                body: "처음 한 번만 준비 파일을 받습니다. 약 465MB이고, 이 맥에만 둡니다. 다 받으면 바로 말할 수 있습니다.",
                action: "지금 받기",
                run: state.downloadModel
            )
        }
        if !state.axTrusted {
            guidance(
                title: "다른 앱에 바로 넣기",
                body: "시스템 설정 → 손쉬운 사용에서 입타를 켜면, 말한 글이 원래 쓰던 칸에 들어갑니다. 꺼져 있으면 아래 복사로 직접 붙여 넣으세요.",
                action: "손쉬운 사용 설정 열기",
                run: state.openAxSettings
            )
        }
    }

    private func guidance(title: String, body: String, action: String, run: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            AppKitActionButton(title: action, action: run)
                .frame(maxWidth: 160, minHeight: 24)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("결과")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                AppKitActionButton(
                    title: "복사",
                    identifier: "malgyeol-copy",
                    enabled: !state.transcript.isEmpty,
                    action: { state.copyTranscript() }
                )
                .frame(width: 72, height: 28)
            }
            Text(state.transcript.isEmpty ? "아직 없습니다" : state.transcript)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            if !state.rawTranscript.isEmpty, state.rawTranscript != state.transcript {
                Text("받아적은 원문")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.rawTranscript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("설정").font(.title3.weight(.semibold))
                Spacer()
                AppKitActionButton(title: "닫기", identifier: "malgyeol-settings-close", action: { state.showSettings = false })
                    .frame(width: 72, height: 24)
            }

            GroupBox("지금 상태") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("지금 하는 일: \(state.phase.rawValue)")
                    Text("다른 앱에 바로 넣기: \(state.axTrusted ? "켜짐" : "꺼짐")")
                    Text("넣을 칸: \(state.lockedSummary.isEmpty ? "아직 없음" : state.lockedSummary)")
                    Text("기록 파일: \(MalgyeolInfo.logURL.path)")
                        .textSelection(.enabled)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("마이크") {
                Picker("장치", selection: Binding(
                    get: { state.selectedDeviceId },
                    set: { state.setSelectedDevice($0) }
                )) {
                    ForEach(state.devices, id: \.id) { d in
                        Text(WirelessMicHint.looksWireless(d.name) ? "\(d.name) · 무선" : d.name).tag(d.id)
                    }
                }
                Text("상태: \(state.micStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox("무선 마이크") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("돌아다니며 쓰려면 여기서 소리 장치와 송신기 버튼을 연결합니다. 한 번 누르면 녹음, 다시 누르면 받아 적어 넣습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(state.micButton.map { "연결됨: \($0.label)" } ?? "아직 버튼을 연결하지 않았습니다")
                    HStack {
                        AppKitActionButton(
                            title: state.capturingMicButton ? "버튼을 누르세요…" : "마이크 버튼 연결",
                            action: {
                                state.settingsNotice = ""
                                state.beginMicButtonCapture()
                            }
                        )
                        .frame(minWidth: 140, minHeight: 24)
                        AppKitActionButton(
                            title: "연결 지우기",
                            action: { state.clearMicButton() }
                        )
                        .frame(minWidth: 90, minHeight: 24)
                    }
                    Text("키보드·트랙패드는 무시합니다. DJI 같은 송신기 버튼을 누르세요. 버튼이 볼륨으로 잡히면 맥 키보드 볼륨과 겹칠 수 있습니다. Esc는 연결 취소입니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GroupBox("말한 글 다듬기") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(PolishProvider.outsideBrainGuide)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("말한 글을 다듬어 넣기", isOn: Binding(
                        get: { state.polishEnabled },
                        set: { state.setPolishEnabled($0) }
                    ))
                    Picker("어디서", selection: Binding(
                        get: { state.polishPlan.tier },
                        set: { state.setPolishTier($0) }
                    )) {
                        ForEach(PolishTier.allCases) { t in
                            Text(t.title).tag(t)
                        }
                    }
                    Picker("어디 모델", selection: Binding(
                        get: { state.polishPlan.provider },
                        set: { state.setPolishProvider($0) }
                    )) {
                        ForEach(PolishProvider.visible(for: state.polishPlan.tier)) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    Text(state.polishPlan.provider.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if state.polishPlan.tier == .connected, state.polishPlan.provider.supportsOAuth {
                        if !state.oauthNote.isEmpty {
                            Text(state.oauthNote)
                                .font(.caption)
                                .foregroundStyle(state.oauthReady ? .primary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !state.oauthReady, !state.oauthBlocked {
                            Text("로그인 버튼을 누르면 브라우저가 열립니다. 본인 계정으로 끝나면 여기 자동으로 붙습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if state.polishPlan.provider.installURL != nil {
                            AppKitActionButton(
                                title: "\(state.polishPlan.provider.title) 받는 곳 열기",
                                action: { state.openProviderInstallPage() }
                            )
                            .frame(minWidth: 180, minHeight: 24)
                        }
                        AppKitActionButton(
                            title: state.oauthWatching
                                ? "로그인 기다리는 중…"
                                : (state.oauthReady
                                    ? "\(state.polishPlan.provider.title) 다시 로그인"
                                    : "\(state.polishPlan.provider.title)으로 로그인"),
                            action: { state.beginOAuthLogin() }
                        )
                        .frame(minWidth: 180, minHeight: 28)
                        if state.polishPlan.authMode != .key {
                            AppKitActionButton(
                                title: "키를 직접 넣을게요",
                                action: { state.setPolishAuthMode(.key) }
                            )
                            .frame(minWidth: 140, minHeight: 24)
                        } else {
                            AppKitActionButton(
                                title: "로그인으로 돌아가기",
                                action: { state.setPolishAuthMode(.oauth) }
                            )
                            .frame(minWidth: 140, minHeight: 24)
                        }
                    }
                    if state.polishPlan.provider.hasLocalModelPicker, !LocalPolishModel.visibleOnThisMac().isEmpty {
                        Picker("이 맥 모델", selection: Binding(
                            get: { LocalPolishModel.resolve(state.polishPlan.model) },
                            set: { state.setLocalPolishModel($0) }
                        )) {
                            ForEach(LocalPolishModel.visibleOnThisMac()) { m in
                                Text(m.title).tag(m)
                            }
                        }
                        Text(LocalPolishModel.resolve(state.polishPlan.model).hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if state.polishPlan.needsPastedKey {
                        SecureField("내 키만 넣기", text: $state.polishKeyDraft)
                        HStack {
                            AppKitActionButton(title: "내 키 저장", action: { state.savePolishKey() })
                                .frame(width: 90, height: 24)
                            AppKitActionButton(title: "내 키 지우기", action: { state.clearPolishKey() })
                                .frame(width: 90, height: 24)
                            Text(KeychainBox.hasKey(state.polishPlan.provider) ? "이 맥에 내 키 있음" : "아직 안 넣음")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if state.polishPlan.provider.sendsOffDevice, state.polishPlan.tier == .connected {
                        Text("다듬을 글만 고른 곳으로 갑니다. 받아 적기 소리는 안 보냅니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("단축키") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.hotkeyNote)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        AppKitActionButton(
                            title: state.capturingHotkey == .toggle ? "키를 누르세요…" : "시작/정지 바꾸기",
                            action: {
                                if state.capturingMicButton {
                                    state.cancelMicButtonCapture()
                                }
                                state.settingsNotice = ""
                                state.capturingHotkey = .toggle
                            }
                        )
                        .frame(minWidth: 140, minHeight: 24)
                        AppKitActionButton(
                            title: state.capturingHotkey == .cancel ? "키를 누르세요…" : "취소 키 바꾸기",
                            action: {
                                if state.capturingMicButton {
                                    state.cancelMicButtonCapture()
                                }
                                state.settingsNotice = ""
                                state.capturingHotkey = .cancel
                            }
                        )
                        .frame(minWidth: 140, minHeight: 24)
                    }
                    AppKitActionButton(
                        title: "기본값으로",
                        action: {
                            state.applyHotKeys(toggle: .defaultToggle, cancel: .defaultCancel)
                            state.settingsNotice = "기본 단축키로 되돌렸습니다"
                        }
                    )
                    .frame(width: 120, height: 28)
                    Text("다른 앱이 같은 키를 쓰면 등록이 실패합니다. 그때는 다른 조합으로 바꾸세요. Esc는 입력 취소입니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !state.settingsNotice.isEmpty {
                        Text(state.settingsNotice).font(.caption)
                    }
                }
            }

            GroupBox("말할 준비") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("말을 글로 바꾸려면 처음에 준비 파일을 받아 둬요. 한 번만 받으면 됩니다. 약 465MB이고 이 맥에만 둡니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(state.downloadNote)
                        .font(.body.weight(.medium))
                    if state.phase == .downloading {
                        ProgressView(value: state.downloadProgress)
                    }
                    HStack {
                        AppKitActionButton(
                            title: state.modelReady ? "준비 파일 다시 받기" : "준비 파일 받기",
                            enabled: state.phase != .downloading && !state.recording,
                            action: { state.downloadModel() }
                        )
                        .frame(minWidth: 140, minHeight: 24)
                        AppKitActionButton(
                            title: "취소",
                            enabled: state.phase == .downloading,
                            action: { state.cancel() }
                        )
                        .frame(width: 72, height: 24)
                    }
                }
            }
            }
            .padding(16)
            .frame(minWidth: 400)
        }
        .frame(minWidth: 420, minHeight: 480)
        .onAppear {
            state.refreshPermissions()
            state.refreshOAuthStatus()
        }
    }
}
