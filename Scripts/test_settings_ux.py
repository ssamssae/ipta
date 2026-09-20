#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check(name: str, cond: bool) -> int:
    print(("PASS " if cond else "FAIL ") + name)
    return 0 if cond else 1


def main() -> int:
    result = (ROOT / "App/Sources/ResultView.swift").read_text(encoding="utf-8")
    state = (ROOT / "App/Sources/AppState.swift").read_text(encoding="utf-8")
    delegate = (ROOT / "App/Sources/AppDelegate.swift").read_text(encoding="utf-8")
    failed = 0
    failed += check("no settings sheet", ".sheet(isPresented: $state.showSettings)" not in result)
    failed += check("status always visible", 'GroupBox("지금 상태")' in result)
    failed += check("no collapsed details", "DisclosureGroup" not in result)
    failed += check("model box is plain language", 'GroupBox("말할 준비")' in result)
    failed += check("ready note is plain", "준비됐어요. 말해도 됩니다." in state)
    failed += check("settings window is titled", "settingsStyleMask" in delegate and "isMovableByWindowBackground = true" in delegate)
    failed += check("escape and command-w close settings", "closesSettingsWindow" in delegate and "closeSettingsWindow" in delegate)
    failed += check("file menu close is command-w", 'keyEquivalent: "w"' in delegate)
    failed += check("main window can minimize", "mainStyleMask" in delegate and ".miniaturizable" in delegate)
    failed += check("main window is not floating", "panel.level = .floating" not in delegate and "panel.level = .normal" in delegate)
    failed += check("hide button exists", 'title: "숨기기"' in result and "hidePanel" in delegate)
    print(f"failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
