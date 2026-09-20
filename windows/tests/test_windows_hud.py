#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ipta_win import paste, transcribe
from ipta_win.selftest import check
from ipta_win.hud import hud_geometry, hud_subtitle, hud_title
from ipta_win.winhide import CREATE_NO_WINDOW, hidden_kwargs


def main() -> int:
    failed = 0
    geo = hud_geometry(1280, 720)
    failed += check("hud centered x", geo.startswith("320x56+480+"))
    failed += check("hud near bottom", geo.endswith("+636"))
    failed += check("recording title", hud_title("recording") == "듣는 중")
    failed += check("transcribe title", hud_title("transcribing") == "받아적는 중")
    failed += check("recording subtitle has seconds", "초" in hud_subtitle("recording", 3))
    failed += check("own title ipta", paste.looks_own_title("입타"))
    failed += check("cursor is not own", not paste.looks_own_title("Cursor"))
    failed += check("telegram cursor chat is not ide", not paste.looks_cursor_ide("Cursor 헤르메스"))
    failed += check("cursor ide title", paste.looks_cursor_ide("app.py - Cursor"))
    failed += check("telegram title", paste.looks_telegram("Cursor 헤르메스"))
    failed += check("telegram cursor chat title", paste.looks_telegram_cursor_chat("‎Cursor 헤르메스 – (6)"))
    failed += check("lock empty off windows", paste.lock_target() == 0 or sys.platform == "win32")
    failed += check("skip own paste note", paste.COPIED_ONLY.startswith("복사"))
    src = Path(transcribe.__file__).read_text(encoding="utf-8")
    failed += check("whisper hides console", "hidden_kwargs" in src)
    kwargs = hidden_kwargs()
    if sys.platform == "win32":
        failed += check("hidden flag", int(kwargs.get("creationflags") or 0) & CREATE_NO_WINDOW == CREATE_NO_WINDOW)
    else:
        failed += check("hidden kwargs empty off windows", "creationflags" not in kwargs)
    ui_src = (ROOT / "ipta_win" / "ui.py").read_text(encoding="utf-8")
    failed += check("old top-left hud gone", "+80+40" not in ui_src)
    failed += check("hud uses geometry helper", "hud_geometry" in ui_src)
    failed += check("hud helper bottom", "HUD_BOTTOM" in (ROOT / "ipta_win" / "hud.py").read_text(encoding="utf-8"))
    print(f"failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
