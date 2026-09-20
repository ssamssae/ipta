from __future__ import annotations

import json
from typing import Any

from . import info


DEFAULTS: dict[str, Any] = {
    "polish_enabled": False,
    "polish": {
        "tier": "free",
        "provider": "local",
        "model": "gpt-oss-20b",
        "auth_mode": "key",
        "prefer_pasted_key": False,
    },
    "toggle_hotkey": "alt+d",
    "cancel_hotkey": "alt+shift+c",
    "selected_device_id": "",
}


def load() -> dict[str, Any]:
    path = info.settings_path()
    data = dict(DEFAULTS)
    if path.is_file():
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            raw = {}
        if isinstance(raw, dict):
            data.update(raw)
            polish = dict(DEFAULTS["polish"])
            if isinstance(raw.get("polish"), dict):
                polish.update(raw["polish"])
            data["polish"] = polish
    return data


def save(data: dict[str, Any]) -> None:
    path = info.settings_path()
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
