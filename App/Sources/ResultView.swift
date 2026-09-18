import Carbon
import SwiftUI

struct ResultView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(MalgyeolInfo.label)
                    .font(.title.weight(.semibold))
                Text("받아적기는 이 Mac에서만 합니다. 다듬기 연결을 켜면 고른 모델로 글만 보냅니다.")
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

                AppKitActionButton(title: "설정", identifier: "malgyeol-settings", action: { state.showSettings = true })
                    .frame(maxWidth: 80, minHeight: 24)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 320, minHeight: 280)
        .sheet(isPresented: $state.showSettings) {
            SettingsView(state: state)
        }
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
                title: "받아적기 준비",
                body: "처음 한 번만 준비 파일을 받습니다. 약 465MB, 이 Mac에만 저장됩니다.",
                action: "지금 받기",
                run: state.downloadModel
            )
        }
        if !state.axTrusted {
            guidance(
                title: "다른 앱에 바로 넣기",
                body: "손쉬운 사용을 켜면 단축키로 원래 칸에 넣습니다. 꺼져 있어도 아래 복사로 쓸 수 있습니다.",
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("설정").font(.title3.weight(.semibold))
                Spacer()
                AppKitActionButton(title: "닫기", identifier: "malgyeol-settings-close", action: { dismiss() })
                    .frame(width: 72, height: 28)
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

            GroupBox("다듬기 구독") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("말한 글을 다듬어 넣기", isOn: Binding(
                        get: { state.polishEnabled },
                        set: { state.setPolishEnabled($0) }
                    ))
                    Picker("요금", selection: Binding(
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
                        ForEach(PolishProvider.allCases) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    .disabled(state.polishPlan.tier == .free)
                    if state.polishPlan.tier == .connected, state.polishPlan.provider.supportsOAuth {
                        Picker("연결", selection: Binding(
                            get: { state.polishPlan.authMode },
                            set: { state.setPolishAuthMode($0) }
                        )) {
                            ForEach(PolishAuthMode.allCases) { m in
                                Text(m.title).tag(m)
                            }
                        }
                        if state.polishPlan.authMode == .oauth, !state.oauthNote.isEmpty {
                            Text(state.oauthNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if state.polishPlan.tier == .connected, state.polishPlan.provider.hasLocalModelPicker {
                        Picker("이 맥 모델", selection: Binding(
                            get: { LocalPolishModel.resolve(state.polishPlan.model) },
                            set: { state.setLocalPolishModel($0) }
                        )) {
                            ForEach(LocalPolishModel.allCases) { m in
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
                    Text("이 맥 로그인은 이미 켜 둔 클로드·코덱스·커서·그록을 그대로 씁니다. 입타가 토큰을 꺼내 저장하지 않습니다. 내 키를 고르면 열쇠고리에만 넣습니다. 함대 공용 키는 안 씁니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if state.polishPlan.provider.sendsOffDevice, state.polishPlan.tier == .connected {
                        Text("연결하면 다듬을 글만 고른 회사로 갑니다. 받아적기 소리는 안 보냅니다.")
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

            GroupBox("받아적기 파일") {
                VStack(alignment: .leading) {
                    Text(state.downloadNote)
                    if state.phase == .downloading {
                        ProgressView(value: state.downloadProgress)
                    }
                    HStack {
                        AppKitActionButton(
                            title: "받기 / 다시 시도",
                            enabled: state.phase != .downloading && !state.recording,
                            action: { state.downloadModel() }
                        )
                        .frame(minWidth: 120, minHeight: 24)
                        AppKitActionButton(
                            title: "취소",
                            enabled: state.phase == .downloading,
                            action: { state.cancel() }
                        )
                        .frame(width: 72, height: 28)
                    }
                }
            }

            DisclosureGroup("자세한 상태") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("단계: \(state.phase.rawValue)")
                    Text("손쉬운 사용: \(state.axTrusted ? "허용" : "없음")")
                    Text("대상: \(state.lockedSummary.isEmpty ? "없음" : state.lockedSummary)")
                    Text("로그: \(MalgyeolInfo.logURL.path)")
                }
                .font(.caption)
                .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(minWidth: 400, minHeight: 820)
        .onAppear {
            state.refreshPermissions()
            state.refreshOAuthStatus()
        }
    }
}
