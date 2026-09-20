#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check(name: str, cond: bool) -> int:
    print(("PASS " if cond else "FAIL ") + name)
    return 0 if cond else 1


def main() -> int:
    hud = (ROOT / "App/Sources/RecordingHUD.swift").read_text(encoding="utf-8")
    delegate = (ROOT / "App/Sources/AppDelegate.swift").read_text(encoding="utf-8")
    failed = 0
    failed += check("hud title is listening", 'return "듣는 중"' in hud)
    failed += check("hud is nonactivating", ".nonactivatingPanel" in hud)
    failed += check("hud does not steal key", "becomesKeyOnlyIfNeeded = true" in hud)
    failed += check("hud shows recording and polish", "transcribing, .polishing" in hud)
    failed += check("delegate syncs hud", "syncActivityChrome" in delegate and "setupHUD" in delegate)
    failed += check("menubar tints while recording", "contentTintColor = state.recording ? .systemRed" in delegate)
    print(f"failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
