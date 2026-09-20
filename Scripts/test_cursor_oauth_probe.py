#!/usr/bin/env python3
"""Contract for Ipta Cursor login probe. Mirrors OAuthCLI.parseCursorStatus."""
from __future__ import annotations

import json
import sys


def parse_cursor_status(raw: str) -> tuple[bool, bool]:
    lower = raw.lower()
    if "keychain is locked" in lower or "unlock-keychain" in lower:
        return False, True
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError:
        obj = None
    if isinstance(obj, dict) and isinstance(obj.get("isAuthenticated"), bool):
        ready = bool(obj["isAuthenticated"])
        return ready, False
    if "not logged in" in lower or "logged out" in lower:
        return False, False
    if "logged in" in lower:
        return True, False
    return False, False


def check(name: str, cond: bool) -> int:
    print(("PASS " if cond else "FAIL ") + name)
    return 0 if cond else 1


def main() -> int:
    failed = 0
    ready, blocked = parse_cursor_status('{"isAuthenticated":true,"status":"ok"}')
    failed += check("json ready", ready and not blocked)
    ready, blocked = parse_cursor_status('{"isAuthenticated":false,"status":"ok"}')
    failed += check("json not ready", (not ready) and not blocked)
    ready, blocked = parse_cursor_status(
        "Error: Your macOS login keychain is locked.\nRun security unlock-keychain and try again."
    )
    failed += check("keychain lock is blocked", (not ready) and blocked)
    ready, blocked = parse_cursor_status("✗ Not logged in")
    failed += check("not-logged-in is waiting", (not ready) and not blocked)
    print(f"failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
