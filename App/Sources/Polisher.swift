import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct PolishResult {
    let text: String
    let note: String
    let usedModel: Bool
    var skipPaste: Bool = false
}

enum SpeechCommand: Equatable {
    case polishSpoken
    case editSelection
}

enum SpeechCleaner {
    /// Instant, local cleanup in the Typeless style: fillers, repeats, last intent.
    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return s }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        for pat in [#"^(음+|어+|아+|에+|그+)\s*"#, #"(음+|어+)\s+"#] {
            s = s.replacingOccurrences(of: pat, with: "", options: .regularExpression)
        }
        for filler in ["그니까", "그러니까", "뭐랄까", "있잖아", "뭐지"] {
            s = s.replacingOccurrences(of: filler, with: " ")
        }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = keepLastIntent(s)
        s = dropImmediateRepeats(s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func command(from spoken: String) -> SpeechCommand {
        let compact = spoken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        guard compact.count <= 24 else { return .polishSpoken }
        let pats = [
            "^(이거|이걸|이글|선택)?(을|를)?(요약|짧게|정리|번역)",
            "^(요약|짧게|정리)(해|해줘|해주세요)?$",
        ]
        for p in pats {
            if compact.range(of: p, options: .regularExpression) != nil {
                return .editSelection
            }
        }
        return .polishSpoken
    }

    private static func keepLastIntent(_ s: String) -> String {
        for sep in [" 아니라 ", " 아니 ", " 말고 "] {
            if let r = s.range(of: sep, options: .backwards) {
                let tail = s[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if tail.count >= 2 { return String(tail) }
            }
        }
        return s
    }

    private static func dropImmediateRepeats(_ s: String) -> String {
        let parts = s.split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return s }
        var out: [String] = []
        for w in parts where out.last != w {
            out.append(w)
        }
        return out.joined(separator: " ")
    }
}

final class Polisher: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0

    func cancel() {
        lock.lock()
        generation += 1
        lock.unlock()
    }

    func polish(raw: String, selected: String, plan: PolishPlan, completion: @escaping (PolishResult) -> Void) {
        lock.lock()
        generation += 1
        let job = generation
        lock.unlock()

        let cleaned = SpeechCleaner.clean(raw)
        let cmd = SpeechCleaner.command(from: raw)
        let wantsSelection = cmd == .editSelection && selected.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8

        DispatchQueue.global(qos: .userInitiated).async {
            if wantsSelection {
                if !plan.canAttemptModel {
                    completion(PolishResult(text: raw, note: "요약은 다듬기 연결이 필요합니다", usedModel: false, skipPaste: true))
                    return
                }
                if let text = self.modelTransform(
                    job: job,
                    plan: plan,
                    instructions: Self.editInstructions,
                    user: "지시: \(raw)\n\n글:\n\(selected)"
                ) {
                    completion(PolishResult(text: text, note: "고른 글을 \(plan.provider.title)로 다듬었습니다", usedModel: true))
                    return
                }
                completion(PolishResult(text: raw, note: "요약 모델을 쓰지 못했습니다. 로그인이나 키를 확인하세요", usedModel: false, skipPaste: true))
                return
            }

            if plan.canAttemptModel,
               let text = self.modelTransform(job: job, plan: plan, instructions: Self.polishInstructions, user: cleaned.isEmpty ? raw : cleaned)
            {
                completion(PolishResult(text: text, note: "말한 글을 \(plan.provider.title)로 다듬었습니다", usedModel: true))
                return
            }
            let fallback = cleaned.isEmpty ? raw : cleaned
            let note: String
            if plan.usesOAuth {
                note = "이 맥 로그인을 쓰지 못해 기본 다듬기만 했습니다"
            } else if plan.needsPastedKey && !KeychainBox.hasKey(plan.provider) {
                note = "키가 없어 기본 다듬기만 했습니다"
            } else if cleaned == raw {
                note = "받아 적었습니다"
            } else {
                note = "군더더기를 빼고 넣었습니다"
            }
            completion(PolishResult(text: fallback, note: note, usedModel: false))
        }
    }

    private static let polishInstructions = """
    받아적은 말을 글로 다듬는다. 의미와 고유명사는 유지한다.
    음, 어, 그니까 같은 군더더기는 뺀다. 중간에 고친 말은 마지막 의도만 남긴다.
    같은 말 반복은 한 번만. 목록이면 줄을 나눈다. 새 사실은 만들지 않는다.
    설명 없이 다듬은 문장만 출력한다.
    """

    private static let editInstructions = """
    사용자가 고른 글을 지시에 맞게 다룬다. 새 사실은 만들지 않는다.
    요약이면 짧게. 설명 없이 결과 문장만 출력한다.
    """

    private func stillCurrent(_ job: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == job
    }

    private func modelTransform(job: UInt64, plan: PolishPlan, instructions: String, user: String) -> String? {
        guard stillCurrent(job), plan.canAttemptModel else { return nil }
        switch plan.provider {
        case .apple:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                if let text = appleTransform(instructions: instructions, user: user) {
                    return stillCurrent(job) ? sanitize(text, source: user) : nil
                }
            }
            #endif
            return nil
        case .cursor:
            let key = plan.needsPastedKey ? KeychainBox.get(provider: .cursor) : ""
            if plan.usesOAuth || !key.isEmpty,
               let text = OAuthCLI.polish(provider: .cursor, instructions: instructions, user: user, key: key)
            {
                return stillCurrent(job) ? sanitize(text, source: user) : nil
            }
            return nil
        case .claude, .grok, .openai, .local:
            if plan.usesOAuth {
                if let text = OAuthCLI.polish(provider: plan.provider, instructions: instructions, user: user) {
                    return stillCurrent(job) ? sanitize(text, source: user) : nil
                }
                return nil
            }
            if let text = cloudTransform(plan: plan, instructions: instructions, user: user) {
                return stillCurrent(job) ? sanitize(text, source: user) : nil
            }
            return nil
        }
    }

    private func cloudTransform(plan: PolishPlan, instructions: String, user: String) -> String? {
        let key = plan.provider.needsKey ? KeychainBox.get(provider: plan.provider) : ""
        guard let req = PolishAPI.makeRequest(
            provider: plan.provider,
            key: key,
            model: plan.model,
            system: instructions,
            user: user
        ) else { return nil }
        malgyeolLog("polish http provider=\(plan.provider.rawValue) model=\(plan.model)")
        let box = TimeoutBox<Data>()
        let group = DispatchGroup()
        group.enter()
        let task = URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data { box.set(data) }
            group.leave()
        }
        task.resume()
        if group.wait(timeout: .now() + plan.provider.requestTimeout) == .timedOut {
            task.cancel()
            return nil
        }
        guard let data = box.get() else { return nil }
        return PolishAPI.parseText(provider: plan.provider, data: data)
    }

    private func sanitize(_ text: String, source: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 {
            t = String(t.dropFirst().dropLast())
        }
        if t.isEmpty { return nil }
        if t.count > max(source.count * 4, 80) { return nil }
        return t
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func appleTransform(instructions: String, user: String) -> String? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }
        let session = LanguageModelSession(model: model, instructions: instructions)
        let opts = GenerationOptions(temperature: 0.2, maximumResponseTokens: 220)
        let box = TimeoutBox<String>()
        let group = DispatchGroup()
        group.enter()
        Task {
            defer { group.leave() }
            do {
                let response = try await session.respond(to: user, options: opts)
                box.set(response.content)
            } catch {
                malgyeolLog("polish apple fail \(error.localizedDescription)")
            }
        }
        _ = group.wait(timeout: .now() + 6)
        return box.get()
    }
    #endif
}

private final class TimeoutBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    func set(_ v: T) {
        lock.lock()
        value = v
        lock.unlock()
    }
    func get() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
