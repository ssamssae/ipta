#!/usr/bin/env python3
"""Submit a DMG to Apple notary without printing secrets."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: notarize_release.py <dmg>", file=sys.stderr)
        return 2
    dmg = Path(sys.argv[1])
    if not dmg.is_file():
        print("dmg_missing", file=sys.stderr)
        return 2
    sec = Path.home() / ".claude" / "secrets"
    asc = json.loads((sec / "asc-api-key.json").read_text())
    key_id = str(asc.get("key_id") or "").strip()
    issuer = str(asc.get("issuer_id") or "").strip()
    p8 = sec / f"AuthKey_{key_id}.p8"
    if not key_id or not issuer or not p8.is_file():
        print("notary_creds_incomplete", file=sys.stderr)
        return 3
    cmd = [
        "xcrun",
        "notarytool",
        "submit",
        str(dmg),
        "--key",
        str(p8),
        "--key-id",
        key_id,
        "--issuer",
        issuer,
        "--wait",
    ]
    print("notary_submit_start", flush=True)
    proc = subprocess.run(cmd, text=True, capture_output=True)
    out = (proc.stdout or "") + "\n" + (proc.stderr or "")
    # Redact likely secret-shaped tokens if the tool echoes them.
    out = out.replace(key_id, "[key-id]").replace(issuer, "[issuer]")
    print(out)
    if proc.returncode != 0:
        return proc.returncode
    if "status: Accepted" in out or "status: Success" in out or "Accepted" in out:
        print("notary_accepted")
        return 0
    print("notary_not_accepted", file=sys.stderr)
    return 5


if __name__ == "__main__":
    raise SystemExit(main())
