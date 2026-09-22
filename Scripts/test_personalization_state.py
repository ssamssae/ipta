#!/usr/bin/env python3
"""Exercise AppState settings/recovery against an isolated support directory."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''
import AppKit
import Foundation
@main struct StateTests {
 @MainActor static func main() throws {
    let state = AppState()
    state.addVocabulary(heard: "입 타", spelling: "입타")
    precondition(state.personalization.vocabulary.count == 1)
    state.addVocabulary(heard: "입 타", spelling: "다른값")
    precondition(state.personalization.vocabulary.count == 1)
    state.writingApps = [AppToneRule(bundleID: "test.mail", name: "Test Mail", tone: .original)]
    state.setWritingTone(bundleID: "test.mail", tone: .polite)
    precondition(state.personalization.tone(for: "test.mail") == .polite)
    state.setHistoryEnabled(true)
    var record = DictationRecord(raw: "입 타를 써요", text: "입타를 써요", appName: "Test")
    state.personalization.history = [record]
    state.phase = .recording
    state.restoreHistory(record)
    precondition(state.transcript.isEmpty, "restore must not overwrite active dictation")
    state.phase = .idle
    state.restoreHistory(record)
    precondition(state.transcript == record.text && state.rawTranscript == record.raw)
    precondition(state.lockedSummary.contains("복구"))
    state.deleteHistory(record.id)
    precondition(state.personalization.history.isEmpty)
    record.text = "another fixture"
    state.personalization.history = [record]
    state.setHistoryEnabled(false)
    let store = PersonalizationStore(directory: MalgyeolInfo.supportDir.appendingPathComponent("Personalization"))
    let saved = try store.load()
    precondition(saved.history.isEmpty && !saved.historyEnabled)
    precondition(saved.vocabulary.count == 1 && saved.tone(for: "test.mail") == .polite)
    state.removeVocabulary(saved.vocabulary[0].id)
    state.removeWritingTone("test.mail")
    let removed = try store.load()
    precondition(removed.vocabulary.isEmpty && removed.tones.isEmpty)
    try Data("corrupt fixture".utf8).write(to: store.file)
    let damaged = AppState()
    damaged.addVocabulary(heard: "새단어", spelling: "표기")
    let content = try String(contentsOf: store.file, encoding: .utf8)
    precondition(content == "corrupt fixture", "load failure overwrote original file")
    print("PASS AppState vocabulary add/delete, tone save/remove, history opt-in/off/delete, idle-only recovery, corrupt-file preservation")
 }
}
'''

def main():
    with tempfile.TemporaryDirectory(prefix="ipta-state-test-") as tmp:
        folder = Path(tmp)
        (folder / "Info.swift").write_text((ROOT / "App/Sources/Main.swift").read_text().split("@main")[0])
        (folder / "Harness.swift").write_text(HARNESS)
        sources = [str(p) for p in (ROOT / "App/Sources").glob("*.swift") if p.name != "Main.swift"]
        cmd = ["swiftc", "-swift-version", "5", *sources, str(folder / "Info.swift"), str(folder / "Harness.swift")]
        for framework in ["AppKit", "SwiftUI", "AVFoundation", "AVFAudio", "CoreAudio", "ApplicationServices", "Carbon", "CoreGraphics", "Security", "IOKit"]:
            cmd += ["-framework", framework]
        cmd += ["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels", "-o", str(folder / "ipta-feature-state-test")]
        subprocess.run(cmd, check=True)
        env = dict(os.environ, MALGYEOL_SUPPORT_DIR=str(folder / "support"))
        subprocess.run([str(folder / "ipta-feature-state-test")], env=env, check=True, timeout=30)

if __name__ == "__main__":
    main()
