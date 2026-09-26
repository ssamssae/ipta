#!/usr/bin/env python3
"""Real Swift storage, vocabulary, prompt routing and editing regressions; no API calls."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''
import Foundation
func malgyeolLog(_ text: String) {}
@main struct Tests {
 static func main() throws {
    var p = Personalization()
    precondition(!p.historyEnabled)
    try p.addVocabulary(heard: "입 타", spelling: "입타")
    try p.addVocabulary(heard: "아태나", spelling: "아테나")
    try p.addVocabulary(heard: "API", spelling: "API")
    precondition(p.applyingVocabulary(to: "입 타를 아태나에서 써요. 아태나무 APIKEY API") == "입타를 아테나에서 써요. 아태나무 APIKEY API")
    precondition(p.applyingVocabulary(to: "가입 타자와 아태나무") == "가입 타자와 아태나무")
    var cascade = Personalization()
    try cascade.addVocabulary(heard: "A", spelling: "B")
    try cascade.addVocabulary(heard: "B", spelling: "C")
    precondition(cascade.applyingVocabulary(to: "A B") == "B C")
    do { try p.addVocabulary(heard: "입 타", spelling: "다른값"); preconditionFailure("duplicate accepted") } catch {}
    do { try p.addVocabulary(heard: " ", spelling: "단어"); preconditionFailure("empty accepted") } catch {}
    precondition(SpeechCleaner.clean("어도비로 작업해") == "어도비로 작업해")
    precondition(SpeechCleaner.clean("어 작업해") == "작업해")
    precondition(SpeechCleaner.clean("플레이어 단어 음악") == "플레이어 단어 음악")
    p.tones = [AppToneRule(bundleID: "test.mail", name: "Mail", tone: .polite)]
    precondition(p.tone(for: "test.mail") == .polite && p.tone(for: "test.chat") == .original)
    precondition(p.instructions(for: "test.mail").contains("존댓말"))
    precondition(!p.instructions(for: "test.chat").contains("존댓말"))
    p.remember(raw: "private", text: "not saved", appName: "test")
    precondition(p.history.isEmpty)
    p.historyEnabled = true
    for i in 0..<55 { p.remember(raw: "raw \(i)", text: "text \(i)", appName: "test") }
    precondition(p.history.count == 50 && p.history.first!.text == "text 54" && p.history.last!.text == "text 5")
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    let store = PersonalizationStore(directory: root.appendingPathComponent("data"))
    try store.save(p)
    let loaded = try store.load()
    precondition(loaded.history.count == 50 && loaded.vocabulary.count == 3 && loaded.tone(for: "test.mail") == .polite)
    let attrs = try FileManager.default.attributesOfItem(atPath: store.file.path)
    precondition((attrs[.posixPermissions] as! NSNumber).intValue == 0o600)
    p.history.removeAll(); p.historyEnabled = false; try store.save(p)
    let cleared = try store.load(); precondition(cleared.history.isEmpty)
    try Data("broken".utf8).write(to: store.file)
    do { _ = try store.load(); preconditionFailure("corrupt file accepted") } catch {}
    let damaged = try String(contentsOf: store.file, encoding: .utf8); precondition(damaged == "broken")
    for command in ["존댓말로", "절반으로 줄여", "영어로 바꿔", "선택한 글을 일본어로 번역해 줘", "요약해", "짧게 해줘"] {
        precondition(SpeechCleaner.command(from: command) == .editSelection, command)
    }
    for speech in ["영어로 바꿔 달라고 말했어요", "정리하는 방법을 알려주세요", "내일 회의는 세 시입니다"] {
        precondition(SpeechCleaner.command(from: speech) == .polishSpoken, speech)
    }
    let plan = PolishPlan(tier: .free, provider: .apple, model: "apple-intelligence", authMode: .key)
    var captured = ""
    let editor = Polisher { instructions, input in captured = instructions; return "See you tomorrow." }
    func run(_ polisher: Polisher, raw: String, selected: String = "", options: Personalization = Personalization(), bundle: String = "") -> PolishResult {
        let done = DispatchSemaphore(value: 0)
        var result: PolishResult?
        polisher.polish(raw: raw, selected: selected, plan: plan, personalization: options, bundleID: bundle) { result = $0; done.signal() }
        precondition(done.wait(timeout: .now()+5) == .success)
        return result!
    }
    let translated = run(editor, raw: "영어로 바꿔", selected: "내일 봐요")
    precondition(translated.text == "See you tomorrow." && !translated.skipPaste && translated.usedModel)
    precondition(captured.contains("지정 언어"))
    precondition(run(editor, raw: "존댓말로").skipPaste)
    let failed = Polisher { _,_ in nil }
    precondition(run(failed, raw: "절반으로 줄여", selected: "길이가 긴 문장입니다").skipPaste)
    let regular = Polisher { instructions, input in captured = instructions; return input }
    _ = run(regular, raw: "입 타를 써요", options: p, bundle: "test.mail")
    precondition(captured.contains("존댓말") && captured.contains("입타"))
    let changedNumber = run(Polisher { _,_ in "금액은 29000원입니다" }, raw: "금액은 19000원입니다")
    precondition(!changedNumber.usedModel && changedNumber.text == "금액은 19000원입니다")
    precondition(SpeechCleaner.keepsSpokenFacts("금액은 19,900원", source:"금액은 19900원"))
    precondition(!SpeechCleaner.keepsSpokenFacts("3시에서 2시로", source:"2시에서 3시로"))
    precondition(!SpeechCleaner.keepsSpokenFacts("1.5mg", source:"15mg"))
    precondition(!SpeechCleaner.keepsSpokenFacts("3도", source:"-3도"))
    let changedName = run(Polisher { _,_ in "아테네에서 써요" }, raw: "아태나에서 써요", options:p)
    precondition(!changedName.usedModel && changedName.text == "아테나에서 써요")
    let vocabResult = run(failed, raw: "입 타를 써요", options: p)
    precondition(vocabResult.text == "입타를 써요")
    print("PASS vocabulary boundaries/particles/no cascade; tone routing; opt-in bounded history, reload/delete/permissions/corruption; selection command routing, translation, no-selection/failure safety; dictionary fallback")
 }
}
'''

def main():
    with tempfile.TemporaryDirectory(prefix="ipta-personalization-") as tmp:
        folder = Path(tmp)
        (folder / "Tests.swift").write_text(HARNESS)
        names = ["Personalization", "Polisher", "PolishPlan", "OAuthCLI"]
        subprocess.run(["swiftc", "-swift-version", "5", *[str(ROOT / f"App/Sources/{n}.swift") for n in names], str(folder / "Tests.swift"), "-framework", "AppKit", "-framework", "Security", "-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels", "-o", str(folder / "tests")], check=True)
        subprocess.run([str(folder / "tests"), str(folder)], check=True, timeout=30)

if __name__ == "__main__":
    main()
