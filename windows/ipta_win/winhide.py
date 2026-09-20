from __future__ import annotations

import subprocess
import sys

CREATE_NO_WINDOW = 0x08000000


def hidden_kwargs(extra: dict[str, object] | None = None) -> dict[str, object]:
    kwargs: dict[str, object] = dict(extra or {})
    if sys.platform != "win32":
        return kwargs
    flags = int(kwargs.get("creationflags") or 0) | CREATE_NO_WINDOW
    kwargs["creationflags"] = flags
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    kwargs["startupinfo"] = startup
    return kwargs
