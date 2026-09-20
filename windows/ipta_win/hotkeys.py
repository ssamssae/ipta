from __future__ import annotations

import sys
import threading
from collections.abc import Callable

DEFAULT_TOGGLE = "alt+d"
DEFAULT_CANCEL = "alt+shift+c"

_MOD = {
    "alt": 0x0001,
    "ctrl": 0x0002,
    "control": 0x0002,
    "shift": 0x0004,
    "win": 0x0008,
}


def parse_hotkey(spec: str) -> tuple[int, int]:
    parts = [p for p in spec.lower().replace(" ", "").split("+") if p]
    mods = 0
    key = ""
    for part in parts:
        if part in _MOD:
            mods |= _MOD[part]
        else:
            key = part
    if len(key) != 1 or not key.isalpha():
        raise ValueError(f"지원하지 않는 단축키: {spec}")
    vk = ord(key.upper())
    return mods, vk


def label(spec: str) -> str:
    parts = [p for p in spec.lower().replace(" ", "").split("+") if p]
    out = ""
    for part in parts:
        out += {"alt": "Alt+", "ctrl": "Ctrl+", "control": "Ctrl+", "shift": "Shift+", "win": "Win+"}.get(part, part.upper())
    return out


class HotkeyListener:
    def __init__(self, toggle: str, cancel: str, on_toggle: Callable[[], None], on_cancel: Callable[[], None]):
        self.toggle = toggle
        self.cancel = cancel
        self.on_toggle = on_toggle
        self.on_cancel = on_cancel
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if sys.platform != "win32":
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _loop(self) -> None:
        import ctypes
        from ctypes import wintypes

        user32 = ctypes.windll.user32
        WM_HOTKEY = 0x0312
        toggle_mods, toggle_vk = parse_hotkey(self.toggle)
        cancel_mods, cancel_vk = parse_hotkey(self.cancel)
        if not user32.RegisterHotKey(None, 1, toggle_mods, toggle_vk):
            return
        if not user32.RegisterHotKey(None, 2, cancel_mods, cancel_vk):
            user32.UnregisterHotKey(None, 1)
            return
        try:
            msg = wintypes.MSG()
            while not self._stop.is_set():
                got = user32.PeekMessageW(ctypes.byref(msg), None, 0, 0, 1)
                if got and msg.message == WM_HOTKEY:
                    if msg.wParam == 1:
                        self.on_toggle()
                    elif msg.wParam == 2:
                        self.on_cancel()
                else:
                    self._stop.wait(0.05)
        finally:
            user32.UnregisterHotKey(None, 1)
            user32.UnregisterHotKey(None, 2)
