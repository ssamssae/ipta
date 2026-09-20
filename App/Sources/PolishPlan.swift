import Foundation
import Security

enum PolishTier: String, CaseIterable, Identifiable {
    case free
    case connected

    var id: String { rawValue }
    var title: String {
        switch self {
        case .free: return "이 맥에서만"
        case .connected: return "바깥 머리"
        }
    }
}

enum PolishAuthMode: String, CaseIterable, Identifiable {
    case oauth
    case key

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oauth: return "이 맥 로그인"
        case .key: return "내 키"
        }
    }
}

enum PolishProvider: String, CaseIterable, Identifiable {
    case apple
    case claude
    case grok
    case openai
    case cursor
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "애플 지능"
        case .claude: return "클로드"
        case .grok: return "그록"
        case .openai: return "코덱스"
        case .cursor: return "커서"
        case .local: return "이 맥에 있는 모델"
        }
    }

    var needsKey: Bool {
        switch self {
        case .claude, .grok, .openai, .cursor: return true
        case .apple, .local: return false
        }
    }

    var supportsOAuth: Bool {
        switch self {
        case .claude, .grok, .openai, .cursor: return true
        case .apple, .local: return false
        }
    }

    var defaultModel: String {
        switch self {
        case .apple: return "apple-intelligence"
        case .claude: return "claude-sonnet-4-5"
        case .grok: return "grok-4"
        case .openai: return "gpt-5"
        case .cursor: return "cursor-default"
        case .local: return LocalPolishModel.twenty.rawValue
        }
    }

    var hint: String {
        switch self {
        case .apple: return "이 맥의 애플 지능으로 군더더기만 뺍니다. 글은 밖으로 안 나갑니다."
        case .claude: return "클로드를 이 맥에 이미 켜 둔 뒤, 로그인 버튼을 누르면 브라우저가 열립니다. 본인 계정으로 로그인하면 자동으로 붙습니다."
        case .grok: return "그록을 이 맥에 이미 켜 둔 뒤, 로그인 버튼을 누르면 브라우저가 열립니다. 본인 계정으로 로그인하면 자동으로 붙습니다."
        case .openai: return "코덱스를 이 맥에 이미 켜 둔 뒤, 로그인 버튼을 누르면 브라우저가 열립니다. 본인 계정으로 로그인하면 자동으로 붙습니다."
        case .cursor: return "커서를 이 맥에 이미 켜 둔 뒤, 로그인 버튼을 누르면 브라우저가 열립니다. 본인 계정으로 로그인하면 자동으로 붙습니다."
        case .local: return "이 맥 LM Studio에 켜 둔 모델로 다듬습니다. 글은 이 맥에만 있습니다."
        }
    }

    static var outsideBrainGuide: String {
        "받아 적기는 입타만으로 됩니다. 그록·커서·클로드·코덱스로 다듬으려면 그 프로그램을 이 맥에 먼저 두고, 본인 계정으로 로그인하세요. 요금은 그 계정으로 나갑니다."
    }

    var missingProgramNote: String {
        "이 맥에 \(title) 프로그램이 없습니다. \(title)을 이 맥에 깐 다음, 받는 곳 버튼으로 안내를 보고 다시 고르세요."
    }

    var installURL: URL? {
        switch self {
        case .claude: return URL(string: "https://code.claude.com/docs/en/overview")
        case .grok: return URL(string: "https://grok.x.ai")
        case .openai: return URL(string: "https://github.com/openai/codex")
        case .cursor: return URL(string: "https://cursor.com/docs/cli/overview")
        case .apple, .local: return nil
        }
    }

    var hasLocalModelPicker: Bool { self == .local }

    static func visible(for tier: PolishTier, localAvailable: Bool = LocalStudio.isInstalled) -> [PolishProvider] {
        let base: [PolishProvider]
        switch tier {
        case .free: base = allCases.filter { !$0.sendsOffDevice }
        case .connected: base = Array(allCases)
        }
        return localAvailable ? base : base.filter { $0 != .local }
    }

    var requestTimeout: TimeInterval {
        switch self {
        case .local: return 60
        case .claude, .grok, .openai, .cursor: return 90
        default: return 12
        }
    }

    var chatURL: URL? {
        switch self {
        case .apple: return nil
        case .claude: return URL(string: "https://api.anthropic.com/v1/messages")
        case .grok: return URL(string: "https://api.x.ai/v1/chat/completions")
        case .openai: return URL(string: "https://api.openai.com/v1/chat/completions")
        case .cursor: return nil
        case .local: return URL(string: "http://127.0.0.1:1234/v1/chat/completions")
        }
    }

    var sendsOffDevice: Bool {
        switch self {
        case .claude, .grok, .openai, .cursor: return true
        case .apple, .local: return false
        }
    }
}

enum LocalPolishModel: String, CaseIterable, Identifiable {
    case twenty = "gpt-oss-20b"
    case twentySeven = "qwen3.8-27b"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twenty: return "20비 — 가볍고 빠름"
        case .twentySeven: return "27비 — 한국어 더 나음"
        }
    }

    var hint: String {
        switch self {
        case .twenty: return "이 맥에서 덜 버벅입니다. LM Studio에 gpt-oss-20b가 켜져 있어야 합니다."
        case .twentySeven: return "한국어가 보통 더 낫습니다. 이 맥 24기에서는 더 묵직합니다. LM Studio에 qwen3.8-27b가 켜져 있어야 합니다."
        }
    }

    static func resolve(_ raw: String) -> LocalPolishModel {
        LocalPolishModel(rawValue: raw) ?? .twenty
    }

    static func visibleOnThisMac() -> [LocalPolishModel] {
        allCases.filter(\.isPresent)
    }

    var isPresent: Bool {
        switch self {
        case .twenty: return LocalStudio.hasTwenty
        case .twentySeven: return LocalStudio.hasTwentySeven
        }
    }
}

enum LocalStudio {
    static var isInstalled: Bool { hasTwenty || hasTwentySeven }

    static var hasTwenty: Bool {
        pathExists([
            ".lmstudio/models/lmstudio-community/gpt-oss-20b-GGUF",
            ".lmstudio/models/local/gpt-oss-20b",
        ])
    }

    static var hasTwentySeven: Bool {
        pathExists([
            ".lmstudio/models/mlx-community/Qwen3.8-27B-4bit",
            ".lmstudio/models/local/qwen3.8-27b",
        ])
    }

    private static func pathExists(_ relatives: [String]) -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        return relatives.contains { fm.fileExists(atPath: home.appendingPathComponent($0).path) }
    }
}

struct PolishPlan: Equatable {
    var tier: PolishTier
    var provider: PolishProvider
    var model: String
    var authMode: PolishAuthMode

    static func load() -> PolishPlan {
        let d = UserDefaults.standard
        let tier = PolishTier(rawValue: d.string(forKey: "malgyeol.polish.tier") ?? "") ?? .free
        var provider = PolishProvider(rawValue: d.string(forKey: "malgyeol.polish.provider") ?? "") ?? .apple
        if tier == .free, provider.sendsOffDevice {
            provider = .apple
        }
        if provider == .local, !LocalStudio.isInstalled {
            provider = .apple
        }
        let stored = d.string(forKey: "malgyeol.polish.model") ?? ""
        let model: String
        if provider == .local {
            model = LocalPolishModel.resolve(stored.isEmpty ? provider.defaultModel : stored).rawValue
        } else {
            model = stored.isEmpty ? provider.defaultModel : stored
        }
        let rawAuth = d.string(forKey: "malgyeol.polish.authMode") ?? ""
        let authMode: PolishAuthMode
        if provider.supportsOAuth {
            // 바깥 머리는 로그인 연결이 기본. 예전에 키 칸을 열어 둔 설정도 로그인으로 되돌린다.
            authMode = rawAuth == PolishAuthMode.key.rawValue && d.bool(forKey: "malgyeol.polish.preferPastedKey")
                ? .key
                : .oauth
        } else {
            authMode = .key
        }
        return PolishPlan(tier: tier, provider: provider, model: model, authMode: authMode)
    }

    func save() {
        let d = UserDefaults.standard
        d.set(tier.rawValue, forKey: "malgyeol.polish.tier")
        d.set(provider.rawValue, forKey: "malgyeol.polish.provider")
        d.set(model, forKey: "malgyeol.polish.model")
        d.set(authMode.rawValue, forKey: "malgyeol.polish.authMode")
        d.set(authMode == .key && provider.supportsOAuth, forKey: "malgyeol.polish.preferPastedKey")
    }

    var usesOAuth: Bool {
        tier == .connected && authMode == .oauth && provider.supportsOAuth
    }

    var needsPastedKey: Bool {
        tier == .connected && authMode == .key && provider.needsKey
    }

    var canUseCloudModel: Bool {
        needsPastedKey
    }

    var canAttemptModel: Bool {
        canAttemptModel(localAvailable: LocalStudio.isInstalled)
    }

    func canAttemptModel(localAvailable: Bool) -> Bool {
        if provider == .local { return localAvailable }
        switch tier {
        case .free: return !provider.sendsOffDevice
        case .connected: return true
        }
    }
}

enum KeychainBox {
    /// Only the current Mac user's own key. Never read ~/.claude/secrets or a shared vault.
    static let service = "app.malgyeol.Malgyeol.keys"

    static func account(for provider: PolishProvider) -> String { provider.rawValue }

    static func set(_ value: String, provider: PolishProvider) {
        let account = account(for: provider)
        delete(provider: provider)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(provider: PolishProvider) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func delete(provider: PolishProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func hasKey(_ provider: PolishProvider) -> Bool {
        !get(provider: provider).isEmpty
    }
}

enum PolishAPI {
    static func makeRequest(
        provider: PolishProvider,
        key: String,
        model: String,
        system: String,
        user: String
    ) -> URLRequest? {
        guard let url = provider.chatURL else { return nil }
        if provider.needsKey, provider.chatURL != nil, key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = provider.requestTimeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any]
        switch provider {
        case .claude:
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": model,
                "max_tokens": 220,
                "system": system,
                "messages": [["role": "user", "content": user]],
            ]
        case .cursor:
            return nil
        case .grok, .openai, .local:
            if provider.needsKey {
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            body = [
                "model": model,
                "temperature": 0.2,
                "max_tokens": 220,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user],
                ],
            ]
        case .apple:
            return nil
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    static func parseText(provider: PolishProvider, data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch provider {
        case .claude:
            guard let content = obj["content"] as? [[String: Any]] else { return nil }
            let texts = content.compactMap { $0["text"] as? String }
            return texts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        case .cursor:
            return nil
        case .grok, .openai, .local:
            guard
                let choices = obj["choices"] as? [[String: Any]],
                let msg = choices.first?["message"] as? [String: Any]
            else { return nil }
            if let c = msg["content"] as? String, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return c.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let r = msg["reasoning"] as? String {
                return lastNonEmptyLine(r)
            }
            return nil
        case .apple:
            return nil
        }
    }

    private static func lastNonEmptyLine(_ s: String) -> String? {
        let lines = s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.last
    }
}
