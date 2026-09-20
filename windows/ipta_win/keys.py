from __future__ import annotations

import os
import sys
from pathlib import Path

from . import info


def _path(provider: str) -> Path:
    return info.keys_dir() / f"{provider}.txt"


def set_key(provider: str, value: str) -> None:
    delete_key(provider)
    trimmed = value.strip()
    if not trimmed:
        return
    path = _path(provider)
    data = trimmed.encode("utf-8")
    if sys.platform == "win32":
        data = _protect(data)
    path.write_bytes(data)
    os.chmod(path, 0o600)


def get_key(provider: str) -> str:
    path = _path(provider)
    if not path.is_file():
        return ""
    raw = path.read_bytes()
    if sys.platform == "win32":
        raw = _unprotect(raw)
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return ""


def delete_key(provider: str) -> None:
    path = _path(provider)
    if path.is_file():
        path.unlink()


def has_key(provider: str) -> bool:
    return bool(get_key(provider))


def _protect(data: bytes) -> bytes:
    import ctypes
    import ctypes.wintypes

    class DATA_BLOB(ctypes.Structure):
        _fields_ = [("cbData", ctypes.wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]

    crypt32 = ctypes.windll.crypt32
    kernel32 = ctypes.windll.kernel32
    blob_in = DATA_BLOB(len(data), ctypes.create_string_buffer(data, len(data)))
    blob_out = DATA_BLOB()
    if not crypt32.CryptProtectData(ctypes.byref(blob_in), None, None, None, None, 0, ctypes.byref(blob_out)):
        return data
    try:
        return ctypes.string_at(blob_out.pbData, blob_out.cbData)
    finally:
        kernel32.LocalFree(blob_out.pbData)


def _unprotect(data: bytes) -> bytes:
    import ctypes
    import ctypes.wintypes

    class DATA_BLOB(ctypes.Structure):
        _fields_ = [("cbData", ctypes.wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]

    crypt32 = ctypes.windll.crypt32
    kernel32 = ctypes.windll.kernel32
    blob_in = DATA_BLOB(len(data), ctypes.create_string_buffer(data, len(data)))
    blob_out = DATA_BLOB()
    if not crypt32.CryptUnprotectData(ctypes.byref(blob_in), None, None, None, None, 0, ctypes.byref(blob_out)):
        return data
    try:
        return ctypes.string_at(blob_out.pbData, blob_out.cbData)
    finally:
        kernel32.LocalFree(blob_out.pbData)
