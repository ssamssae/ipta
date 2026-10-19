#!/usr/bin/env python3
"""자체검사 실붙여넣기 시험이 AppleScript(자동화 허용)에 기대지 않는지 — 구조 확인(T-261017-030).

볼칸 ssh 에는 TextEdit 자동화 허용이 없다(AEDeterminePermission -1744). AppleScript 를 보내면
허용 질문 창이 뜨고 2분 뒤 -1712 로 끝난다. 붙여넣은 글은 잠근 입력칸에서 AX 로 읽는다.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check(name: str, cond: bool) -> int:
    print(("PASS " if cond else "FAIL ") + name)
    return 0 if cond else 1


def main() -> int:
    src = (ROOT / "App/Sources/SelfTest.swift").read_text(encoding="utf-8")
    failed = 0
    failed += check("selftest never runs osascript", "osascript" not in src)
    failed += check("selftest sends no AppleScript to TextEdit", 'tell application \\"TextEdit\\"' not in src)
    failed += check(
        "pasted body is read from the locked text area via AX",
        "TargetLock.axString(element, kAXValueAttribute as String)" in src,
    )
    print(f"failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
