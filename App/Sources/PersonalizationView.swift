import SwiftUI

struct PersonalizationSettingsView: View {
    @ObservedObject var state: AppState
    @State private var heard = ""
    @State private var spelling = ""
    @State private var appID = ""
    @State private var tone = WritingTone.original

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSection("개인 용어 사전") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("자주 틀리는 표현과 올바른 표기를 등록하세요. 등록한 단어만 바꾸며, 긴 단어의 일부는 바꾸지 않습니다.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    TextField("인식되는 표현 (예: 입 타)", text: $heard)
                        .accessibilityIdentifier("ipta-vocabulary-heard")
                    TextField("올바른 표기 (예: 입타)", text: $spelling)
                        .accessibilityIdentifier("ipta-vocabulary-spelling")
                    AppKitActionButton(title: "단어 등록", identifier: "ipta-vocabulary-add", enabled: !heard.isEmpty && !spelling.isEmpty) {
                        state.addVocabulary(heard: heard, spelling: spelling)
                        if state.settingsNotice == "저장했습니다" { heard = ""; spelling = "" }
                    }.frame(height: 26)
                    ForEach(state.personalization.vocabulary) { word in
                        HStack {
                            Text("\(word.heard) → \(word.spelling)").textSelection(.enabled)
                            Spacer()
                            AppKitActionButton(title: "삭제", identifier: "ipta-word-\(word.id)") {
                                state.removeVocabulary(word.id)
                            }.frame(width: 56, height: 24)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            SettingsSection("앱별 말투") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("다듬기를 켰을 때, 녹음을 시작한 앱에 맞춰 적용합니다. 지정하지 않은 앱은 원래 말투를 유지합니다.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    Picker("앱", selection: $appID) {
                        Text("앱 선택").tag("")
                        ForEach(state.writingApps) { app in Text(app.name).tag(app.bundleID) }
                    }
                    Picker("말투", selection: $tone) {
                        ForEach(WritingTone.allCases) { item in Text(item.title).tag(item) }
                    }
                    HStack {
                        AppKitActionButton(title: "말투 저장", identifier: "ipta-tone-save", enabled: !appID.isEmpty) {
                            state.setWritingTone(bundleID: appID, tone: tone)
                        }.frame(height: 26)
                        AppKitActionButton(title: "앱 목록 새로고침") { state.refreshWritingApps() }.frame(height: 26)
                    }
                    ForEach(state.personalization.tones) { rule in
                        HStack {
                            Text("\(rule.name): \(rule.tone.title)")
                            Spacer()
                            AppKitActionButton(title: "해제") { state.removeWritingTone(rule.bundleID) }
                                .frame(width: 56, height: 24)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            SettingsSection("받아쓰기 기록") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("최근 50개를 이 맥에 저장", isOn: Binding(
                        get: { state.personalization.historyEnabled }, set: { state.setHistoryEnabled($0) }
                    ))
                    Text("켜면 원문과 결과를 저장합니다. 음성은 저장하지 않습니다. 끄면 저장된 기록도 삭제합니다.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    AppKitActionButton(title: "기록 전체 삭제", enabled: !state.personalization.history.isEmpty) {
                        state.deleteHistory()
                    }.frame(height: 26)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !state.settingsNotice.isEmpty {
                Text(state.settingsNotice).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            SettingsSection("글을 선택하고 말로 편집") {
                Text("다른 앱에서 글을 선택한 뒤 녹음 단축키를 누르세요. ‘존댓말로’, ‘절반으로 줄여’, ‘영어로 바꿔’라고 말하면 선택한 글을 편집합니다. 다듬기 연결이 필요합니다.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { state.refreshWritingApps() }
        .onChange(of: appID) { _, id in tone = state.personalization.tone(for: id) }
    }
}

struct DictationHistoryView: View {
    @ObservedObject var state: AppState
    @State private var search = ""
    private var records: [DictationRecord] {
        state.personalization.history.filter {
            search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) || $0.raw.localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        SettingsSection("최근 받아쓰기") {
            VStack(alignment: .leading, spacing: 8) {
                if !state.personalization.historyEnabled {
                    Text("설정에서 기록 보관을 켜면 이전 결과를 찾아 복구할 수 있습니다.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                } else {
                    TextField("기록 검색", text: $search).accessibilityIdentifier("ipta-history-search")
                    if records.isEmpty { Text("저장된 기록이 없습니다").font(.caption) }
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(record.appName)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(record.text).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                            HStack {
                                AppKitActionButton(title: "결과로 복구", identifier: "ipta-history-restore-\(record.id)",
                                    enabled: state.phase == .idle || state.phase == .error) { state.restoreHistory(record) }
                                    .frame(height: 24)
                                AppKitActionButton(title: "삭제") { state.deleteHistory(record.id) }.frame(width: 56, height: 24)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
