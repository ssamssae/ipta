#!/usr/bin/env python3
"""대상 잠금(TargetLock) 견고성 회귀 검사 — 구조 확인(T-261017-015)."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check(name: str, cond: bool) -> int:
    print(("PASS " if cond else "FAIL ") + name)
    return 0 if cond else 1


def main() -> int:
    lock = (ROOT / "App/Sources/TargetLock.swift").read_text(encoding="utf-8")
    state = (ROOT / "App/Sources/AppState.swift").read_text(encoding="utf-8")
    failed = 0
    failed += check("ax calls carry a timeout on the app element", "AXUIElementSetMessagingTimeout(appEl, axTimeout)" in lock)
    failed += check("ax calls carry a timeout on the focused element", "AXUIElementSetMessagingTimeout(focused, axTimeout)" in lock)
    failed += check("timeout is sub-second", "axTimeout: Float = 0.3" in lock)
    failed += check("enhanced ui retried only when focus is missing", "if focusedEl == nil, enableEnhancedUserInterface(appEl" in lock)
    failed += check("enhanced ui is not re-set when already on", 'AXUIElementCopyAttributeValue(appEl, attr, &current) == .success' in lock)
    failed += check("slow capture is logged", "lock capture slow" in lock)
    failed += check("record start reads selection from the locked target", "TargetLock.selectedText(of: lockedTarget)" in state)
    failed += check("record start does not capture twice", state.count("TargetLock.capture()") == 1)
    print(f"failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
