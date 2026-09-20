#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ipta_win import polish
from ipta_win.selftest import check


def main() -> int:
    failed = 0
    failed += check("no apple in all providers", "apple" not in polish.ALL_PROVIDERS)
    failed += check("free only local", polish.visible_providers("free", True) == ["local"])
    failed += check("free empty without local", polish.visible_providers("free", False) == [])
    failed += check("connected has grok cursor claude codex", set(polish.visible_providers("connected", False)) == {"claude", "grok", "openai", "cursor"})
    plan = polish.PolishPlan.load({"tier": "free", "provider": "grok"}, local_available=True)
    failed += check("free grok coerced to local", plan.provider == "local")
    plan = polish.PolishPlan.load({"provider": "apple", "tier": "connected"}, local_available=True)
    failed += check("apple storage becomes local", plan.provider == "local")
    failed += check("local can attempt when present", polish.PolishPlan(provider="local").can_attempt_model(True))
    failed += check("local cannot attempt when missing", not polish.PolishPlan(provider="local").can_attempt_model(False))
    failed += check("connected claude can attempt", polish.PolishPlan(tier="connected", provider="claude").can_attempt_model(False))
    failed += check("guide mentions own login", "본인 계정" in polish.OUTSIDE_BRAIN_GUIDE)
    failed += check("guide does not mention apple", "애플" not in polish.OUTSIDE_BRAIN_GUIDE)
    req = polish.make_request("local", "", "gpt-oss-20b", "s", "u")
    failed += check("local request no key", req is not None and "127.0.0.1" in req.full_url)
    failed += check("cursor request is none", polish.make_request("cursor", "k", "m", "s", "u") is None)
    print(f"failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
