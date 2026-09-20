#!/usr/bin/env python3
"""Guide-copy contract for Ipta first-run and outside-brain help."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check(name: str, cond: bool) -> int:
    print(("PASS " if cond else "FAIL ") + name)
    return 0 if cond else 1


def main() -> int:
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    result = (ROOT / "App/Sources/ResultView.swift").read_text(encoding="utf-8")
    plan = (ROOT / "App/Sources/PolishPlan.swift").read_text(encoding="utf-8")
    failed = 0
    failed += check("readme mentions own login", "본인 계정" in readme)
    failed += check("readme mentions accessibility", "손쉬운 사용" in readme)
    failed += check("readme mentions install button", "받는 곳 열기" in readme)
    failed += check("settings shows outside guide", "outsideBrainGuide" in result)
    failed += check("main window mentions own login", "본인 계정" in result)
    failed += check("ax copy names 입타", "손쉬운 사용에서 입타" in result)
    failed += check("providers have install urls", plan.count("installURL") >= 1 and "cursor.com" in plan)
    print(f"failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
