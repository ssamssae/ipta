from __future__ import annotations

import os
import sys
import time
from pathlib import Path

OWN_TITLES = ("입타", "설정", "듣는 중", "받아적는 중", "다듬는 중")
COPIED_ONLY = "복사했습니다. 넣을 칸을 누르고 Ctrl+V 하세요"
PASTED = "붙여넣기 요청을 보냈습니다"


def looks_own_title(title: str) -> bool:
    return any(part in (title or "") for part in OWN_TITLES)


def looks_telegram(title: str) -> bool:
    lower = (title or "").lower()
    return "telegram" in lower or "텔레그램" in title or "헤르메스" in (title or "")


def looks_cursor_ide(title: str) -> bool:
    text = title or ""
    lower = text.lower()
    if looks_telegram(text):
        return False
    return lower.endswith("cursor") or " - cursor" in lower or lower == "cursor"


def looks_telegram_cursor_chat(title: str) -> bool:
    text = title or ""
    return looks_telegram(text) and "cursor" in text.lower()


def copy_text(text: str) -> None:
    if sys.platform == "win32":
        _win_clipboard(text)
        return
    try:
        import subprocess

        subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=False)
    except OSError:
        pass


def foreground_hwnd() -> int:
    if sys.platform != "win32":
        return 0
    import ctypes

    return int(ctypes.windll.user32.GetForegroundWindow() or 0)


def window_title(hwnd: int) -> str:
    if sys.platform != "win32" or not hwnd:
        return ""
    import ctypes

    user32 = ctypes.windll.user32
    length = int(user32.GetWindowTextLengthW(hwnd) or 0)
    buf = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buf, length + 1)
    return buf.value


def process_name(hwnd: int) -> str:
    if sys.platform != "win32" or not hwnd:
        return ""
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.windll.user32
    kernel32 = ctypes.windll.kernel32
    pid = wintypes.DWORD(0)
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    if not pid.value:
        return ""
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
    kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel32.OpenProcess(0x1000, False, pid.value)
    if not handle:
        return ""
    try:
        buf = ctypes.create_unicode_buffer(32768)
        size = wintypes.DWORD(32768)
        if kernel32.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size)):
            return Path(buf.value).name.lower()
    finally:
        kernel32.CloseHandle(handle)
    return ""


def is_own_process(hwnd: int) -> bool:
    if sys.platform != "win32" or not hwnd:
        return False
    import ctypes

    pid = ctypes.c_ulong(0)
    ctypes.windll.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return int(pid.value) == os.getpid()


def is_own_window(hwnd: int) -> bool:
    return is_own_process(hwnd) or looks_own_title(window_title(hwnd))


def is_cursor_window(hwnd: int) -> bool:
    if not hwnd or is_own_window(hwnd):
        return False
    return process_name(hwnd) == "cursor.exe" or looks_cursor_ide(window_title(hwnd))


def lock_target(own_hwnds: tuple[int, ...] = ()) -> int:
    hwnd = foreground_hwnd()
    if not hwnd or hwnd in own_hwnds or is_own_window(hwnd):
        return 0
    return hwnd


def _enum_visible() -> list[int]:
    if sys.platform != "win32":
        return []
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.windll.user32
    found: list[int] = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def _cb(hwnd, _lparam):
        if user32.IsWindowVisible(hwnd):
            found.append(int(hwnd))
        return True

    user32.EnumWindows(_cb, 0)
    return found


def find_cursor_window() -> int:
    for hwnd in _enum_visible():
        if is_cursor_window(hwnd):
            return hwnd
    return 0


def find_telegram_cursor_chat() -> int:
    for hwnd in _enum_visible():
        if looks_telegram_cursor_chat(window_title(hwnd)):
            return hwnd
    return 0


def resolve_target(target_hwnd: int = 0, skip_hwnds: tuple[int, ...] = ()) -> int:
    if target_hwnd and target_hwnd not in skip_hwnds and not is_own_window(target_hwnd):
        return target_hwnd
    return (
        find_cursor_window()
        or find_telegram_cursor_chat()
        or (foreground_hwnd() if foreground_hwnd() not in skip_hwnds and not is_own_window(foreground_hwnd()) else 0)
    )


def _click_compose(hwnd: int) -> None:
    if sys.platform != "win32" or not hwnd:
        return
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.windll.user32
    rect = wintypes.RECT()
    if not user32.GetWindowRect(hwnd, ctypes.byref(rect)):
        return
    x = (int(rect.left) + int(rect.right)) // 2
    y = int(rect.bottom) - 56
    user32.SetCursorPos(x, y)
    user32.mouse_event(0x0002, 0, 0, 0, 0)
    user32.mouse_event(0x0004, 0, 0, 0, 0)


def activate_hwnd(hwnd: int) -> bool:
    if sys.platform != "win32" or not hwnd:
        return False
    import ctypes

    user32 = ctypes.windll.user32
    kernel32 = ctypes.windll.kernel32
    if not user32.IsWindow(hwnd):
        return False
    user32.ShowWindow(hwnd, 9)
    user32.keybd_event(0x12, 0, 0, 0)
    fg = user32.GetForegroundWindow()
    fg_tid = user32.GetWindowThreadProcessId(fg, None)
    cur_tid = kernel32.GetCurrentThreadId()
    user32.AttachThreadInput(cur_tid, fg_tid, True)
    try:
        user32.BringWindowToTop(hwnd)
        ok = bool(user32.SetForegroundWindow(hwnd))
    finally:
        user32.AttachThreadInput(cur_tid, fg_tid, False)
        user32.keybd_event(0x12, 0, 2, 0)
    return ok or int(user32.GetForegroundWindow() or 0) == hwnd


def _hide_own_windows() -> list[int]:
    if sys.platform != "win32":
        return []
    import ctypes

    user32 = ctypes.windll.user32
    hidden: list[int] = []
    for hwnd in _enum_visible():
        if is_own_process(hwnd):
            user32.ShowWindow(hwnd, 0)
            hidden.append(hwnd)
    return hidden


def _show_windows(hwnds: list[int]) -> None:
    if sys.platform != "win32":
        return
    import ctypes

    user32 = ctypes.windll.user32
    for hwnd in hwnds:
        user32.ShowWindow(hwnd, 5)


def paste_into_foreground(text: str, target_hwnd: int = 0, skip_hwnds: tuple[int, ...] = ()) -> str:
    copy_text(text)
    if sys.platform != "win32":
        return "복사했습니다. 윈도우에서는 쓰던 칸에 바로 넣습니다."
    hwnd = resolve_target(target_hwnd, skip_hwnds)
    if not hwnd or hwnd in skip_hwnds or is_own_window(hwnd):
        return COPIED_ONLY
    hidden = _hide_own_windows()
    try:
        if not activate_hwnd(hwnd):
            return COPIED_ONLY
        time.sleep(0.12)
        if looks_telegram(window_title(hwnd)) or process_name(hwnd) == "telegram.exe":
            _click_compose(hwnd)
            time.sleep(0.12)
        _send_ctrl_v()
    finally:
        _show_windows(hidden)
    if is_cursor_window(hwnd) or looks_telegram_cursor_chat(window_title(hwnd)):
        return "커서 칸에 붙여넣기 요청을 보냈습니다"
    return PASTED


def _clipboard_api():
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.windll.user32
    kernel32 = ctypes.windll.kernel32
    for name, args, result in (
        ("GlobalAlloc", [wintypes.UINT, ctypes.c_size_t], wintypes.HGLOBAL),
        ("GlobalLock", [wintypes.HGLOBAL], ctypes.c_void_p),
        ("GlobalUnlock", [wintypes.HGLOBAL], wintypes.BOOL),
        ("GlobalFree", [wintypes.HGLOBAL], wintypes.HGLOBAL),
    ):
        fn = getattr(kernel32, name)
        fn.argtypes, fn.restype = args, result
    user32.CreateWindowExW.argtypes = [wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.DWORD, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wintypes.HWND, wintypes.HMENU, wintypes.HINSTANCE, ctypes.c_void_p]
    user32.CreateWindowExW.restype = wintypes.HWND
    user32.DestroyWindow.argtypes = [wintypes.HWND]
    user32.OpenClipboard.argtypes = [wintypes.HWND]
    user32.OpenClipboard.restype = wintypes.BOOL
    user32.SetClipboardData.argtypes = [wintypes.UINT, wintypes.HANDLE]
    user32.SetClipboardData.restype = wintypes.HANDLE
    return user32, kernel32


def _win_clipboard(text: str) -> None:
    import ctypes

    user32, kernel32 = _clipboard_api()
    data = text.encode("utf-16-le") + b"\x00\x00"
    handle = kernel32.GlobalAlloc(0x0002, len(data))
    if not handle:
        raise RuntimeError("클립보드 메모리를 확보하지 못했습니다")
    opened = False
    owner = user32.CreateWindowExW(0, "STATIC", "IptaClipboard", 0, 0, 0, 0, 0, -3, None, None, None)
    try:
        if not owner:
            raise RuntimeError("클립보드 소유 창을 만들지 못했습니다")
        locked = kernel32.GlobalLock(handle)
        if not locked:
            raise RuntimeError("클립보드 메모리에 접근하지 못했습니다")
        try:
            ctypes.memmove(locked, data, len(data))
        finally:
            kernel32.GlobalUnlock(handle)
        for _ in range(5):
            opened = bool(user32.OpenClipboard(owner))
            if opened:
                break
            time.sleep(0.02)
        if not opened:
            raise RuntimeError("클립보드를 열지 못했습니다")
        if not user32.EmptyClipboard():
            raise RuntimeError("클립보드를 준비하지 못했습니다")
        if not user32.SetClipboardData(13, handle):
            raise RuntimeError("클립보드에 글을 복사하지 못했습니다")
        handle = None  # Windows owns the allocation after SetClipboardData.
    finally:
        if opened:
            user32.CloseClipboard()
        if handle:
            kernel32.GlobalFree(handle)
        if owner:
            user32.DestroyWindow(owner)


def _send_ctrl_v() -> None:
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.windll.user32
    INPUT_KEYBOARD = 1
    KEYEVENTF_KEYUP = 0x0002
    VK_CONTROL = 0x11
    VK_V = 0x56
    extra = ctypes.c_ulonglong if ctypes.sizeof(ctypes.c_void_p) == 8 else ctypes.c_ulong

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [
            ("wVk", wintypes.WORD),
            ("wScan", wintypes.WORD),
            ("dwFlags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", extra),
        ]

    class INPUT(ctypes.Structure):
        class _I(ctypes.Union):
            _fields_ = [("ki", KEYBDINPUT), ("pad", ctypes.c_ubyte * 32)]

        _anonymous_ = ("i",)
        _fields_ = [("type", wintypes.DWORD), ("i", _I)]

    def tap(vk: int, up: bool = False) -> None:
        event = INPUT()
        event.type = INPUT_KEYBOARD
        event.ki = KEYBDINPUT(vk, 0, KEYEVENTF_KEYUP if up else 0, 0, 0)
        if user32.SendInput(1, ctypes.byref(event), ctypes.sizeof(INPUT)) != 1:
            raise RuntimeError("붙여넣기 키를 보내지 못했습니다. 입력칸에서 Ctrl+V 하세요")

    time.sleep(0.05)
    tap(VK_CONTROL)
    try:
        tap(VK_V)
    finally:
        try:
            tap(VK_V, True)
        finally:
            tap(VK_CONTROL, True)
