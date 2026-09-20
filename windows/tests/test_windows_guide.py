#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
sys.path.insert(0, str(ROOT))

from ipta_win import polish
from ipta_win.selftest import check


def main() -> int:
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    ui = (ROOT / "ipta_win" / "ui.py").read_text(encoding="utf-8")
    plan = (ROOT / "ipta_win" / "polish.py").read_text(encoding="utf-8")
    root_readme = (REPO / "README.md").read_text(encoding="utf-8")
    failed = 0
    failed += check("windows readme own login", "본인 계정" in readme)
    failed += check("windows readme no apple default", "애플 지능" not in readme)
    failed += check("windows readme local model", "LM Studio" in readme)
    failed += check("ui mentions own login", "본인 계정" in ui)
    failed += check("ui has no apple label", "애플 지능" not in ui)
    failed += check("providers have install urls", "cursor.com" in plan)
    failed += check("root readme mentions windows", "windows" in root_readme.lower() or "윈도우" in root_readme)
    print(f"failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
