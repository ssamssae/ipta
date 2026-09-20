#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ipta_win import oauth, polish
from ipta_win.selftest import check


def main() -> int:
    failed = 0
    ready = oauth.parse_cursor_status('{"isAuthenticated":true,"status":"ok"}')
    failed += check("json ready", ready.ready and not ready.blocked)
    not_ready = oauth.parse_cursor_status('{"isAuthenticated":false}')
    failed += check("json not ready", (not not_ready.ready) and not not_ready.blocked)
    locked = oauth.parse_cursor_status("Error: Your macOS login keychain is locked.\nRun security unlock-keychain")
    failed += check("locked is blocked", locked.blocked and not locked.ready)
    import tempfile
    with tempfile.TemporaryDirectory(prefix="ipta-oauth-test-") as directory:
        probe = oauth.probe("local", home=Path(directory))
    failed += check("local oauth blocked", probe.blocked)
    failed += check("cursor install url", polish.INSTALL_URLS["cursor"].startswith("https://cursor.com"))
    failed += check("login args grok oauth", oauth.LOGIN_ARGS["grok"] == ["login", "--oauth"])
    failed += check("claude login is auth login", oauth.LOGIN_ARGS["claude"] == ["auth", "login"])
    cursor_ready = oauth.parse_cursor_status('{"isAuthenticated":true,"status":"authenticated"}')
    failed += check("cursor json ready", cursor_ready.ready and not cursor_ready.blocked)
    launched = []
    oauth.probe = lambda *a, **k: oauth.Probe(True, False, "이 컴퓨터 커서에 이미 붙어 있습니다")
    oauth._popen_visible = lambda *a, **k: launched.append("visible")
    oauth._popen_wsl_login = lambda *a, **k: launched.append("wsl")
    skip_note = oauth.start_login("cursor")
    failed += check("ready cursor skips login window", "이미 붙어" in skip_note and not launched)
    import importlib
    importlib.reload(oauth)
    opened: list[str] = []
    oauth.webbrowser.open = lambda url: opened.append(url)
    oauth.binary = lambda *a, **k: None
    oauth.wsl_command_exists = lambda *_a, **_k: False
    oauth.probe = lambda *a, **k: oauth.Probe(False, True, polish.missing_program_note("grok"))
    note = oauth.start_login("grok")
    failed += check("missing grok opens install page", bool(opened) and "x.ai" in opened[0])
    failed += check("missing grok explains", "그록" in note)
    import tempfile
    from pathlib import Path as P

    with tempfile.TemporaryDirectory() as tmp:
        root = P(tmp)
        (root / "codex").write_bytes(b"#!/bin/sh\n")
        (root / "codex.cmd").write_text("@echo off\n", encoding="ascii")
        found = None
        for name in oauth.BINARY_NAMES["openai"]:
            candidate = root / name
            if oauth._usable_binary(candidate):
                found = candidate
                break
        failed += check("cmd is first openai name", oauth.BINARY_NAMES["openai"][0] == "codex.cmd")
        failed += check("windows prefers codex.cmd", found is not None and found.name == "codex.cmd")
    failed += check("utf8 korean decode", oauth.decode_cli_output("안녕하세요".encode("utf-8")) == "안녕하세요")
    failed += check("strip fence", oauth.strip_fences("```\n안녕\n```") == "안녕")
    hung = oauth.run_cli([sys.executable, "-c", "import time; time.sleep(8)"], timeout=0.3)
    failed += check("cli timeout returns none", hung is None)
    oauth.probe = lambda *a, **k: oauth.Probe(False, False, "아직 커서에 안 붙어 있습니다")
    try:
        oauth.polish_via_cli("cursor", "다듬어", "안녕")
        reason = ""
    except oauth.CliFailure as exc:
        reason = exc.reason
    failed += check("unready cursor skips hang", reason == "auth_unavailable")
    importlib.reload(oauth)
    from ipta_win.app import AppState

    state = AppState()
    state.polish_enabled = True
    state.polish_plan = polish.PolishPlan(tier="connected", provider="cursor", auth_mode="oauth")
    state.model_transform = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("hang"))
    text, note, used = state.polish_text("안녕하세요")
    failed += check("polish exception keeps spoken", text == "안녕하세요")
    failed += check("polish exception unused model", used is False)
    failed += check("polish exception has note", "기본" in note or "건너" in note)
    print(f"failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
