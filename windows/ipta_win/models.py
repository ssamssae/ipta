from __future__ import annotations

import hashlib
import ssl
import urllib.request
from collections.abc import Callable
from pathlib import Path

from . import info


def size_looks_ready(path: Path | None = None) -> bool:
    target = path or info.model_path()
    try:
        return target.stat().st_size == info.MODEL_BYTES
    except OSError:
        return False


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_hash(path: Path | None = None) -> bool:
    target = path or info.model_path()
    if not target.is_file():
        return False
    return sha256_file(target) == info.MODEL_SHA256


def download(
    dest: Path | None = None,
    url: str = info.MODEL_URL,
    on_progress: Callable[[int, int], None] | None = None,
    opener: Callable[..., object] | None = None,
) -> str | None:
    if not info.url_allowed(url):
        return "모델 주소가 HTTPS 허용 목록이 아닙니다"
    target = dest or info.model_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    if size_looks_ready(target) and verify_hash(target):
        return None
    tmp = target.with_suffix(".part")
    ctx = ssl.create_default_context()
    req = urllib.request.Request(url, headers={"User-Agent": "Ipta/0.1"})
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=60) as resp:
            expected = int(resp.headers.get("Content-Length") or info.MODEL_BYTES)
            written = 0
            with tmp.open("wb") as fh:
                while True:
                    chunk = resp.read(1024 * 64)
                    if not chunk:
                        break
                    fh.write(chunk)
                    written += len(chunk)
                    if on_progress:
                        on_progress(written, expected)
    except OSError as exc:
        if tmp.exists():
            tmp.unlink()
        return f"준비 파일을 받지 못했습니다: {exc}"
    size = tmp.stat().st_size
    if size != info.MODEL_BYTES:
        tmp.unlink()
        return f"모델 크기 불일치 ({size} ≠ {info.MODEL_BYTES}). 파일을 버렸습니다."
    if sha256_file(tmp) != info.MODEL_SHA256:
        tmp.unlink()
        return "준비 파일이 손상되어 다시 받아야 합니다"
    tmp.replace(target)
    return None
