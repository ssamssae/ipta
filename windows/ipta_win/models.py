from __future__ import annotations

import hashlib
import http.client
import ssl
import urllib.error
import urllib.request
from collections.abc import Callable
from pathlib import Path

from . import info


def size_looks_ready(path: Path | None = None) -> bool:
    try:
        target = path or info.model_path()
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
    tmp = None
    try:
        target = dest or info.model_path()
        tmp = target.with_suffix(".part")
        target.parent.mkdir(parents=True, exist_ok=True)
        if size_looks_ready(target) and verify_hash(target):
            return None
        req = urllib.request.Request(url, headers={"User-Agent": "Ipta/0.1"})
        # The pinned model size is authoritative, including chunked responses.
        with (opener or urllib.request.urlopen)(req, context=ssl.create_default_context(), timeout=30) as resp:
            written = 0
            with tmp.open("wb") as fh:
                while True:
                    chunk = resp.read(1024 * 64)
                    if not chunk:
                        break
                    written += len(chunk)
                    if written > info.MODEL_BYTES:
                        return "모델 크기가 예상과 다릅니다. 다시 받기를 눌러 주세요."
                    fh.write(chunk)
                    if on_progress:
                        on_progress(written, info.MODEL_BYTES)
        if tmp.stat().st_size != info.MODEL_BYTES:
            return "다운로드가 끝나기 전에 연결이 끊겼습니다. 인터넷 연결을 확인하고 다시 받기를 눌러 주세요."
        if sha256_file(tmp) != info.MODEL_SHA256:
            return "준비 파일이 손상되었습니다. 다시 받기를 눌러 주세요."
        tmp.replace(target)
        return None
    except (urllib.error.URLError, TimeoutError, ConnectionError, ssl.SSLError, http.client.HTTPException):
        return "모델을 받지 못했습니다. 오프라인이면 인터넷에 연결한 뒤 다시 받기를 눌러 주세요. 첫 다운로드 후에는 인터넷 없이 받아 적을 수 있습니다."
    except OSError:
        return "모델을 저장하거나 읽지 못했습니다. 저장 공간과 폴더 권한을 확인하고 다시 받기를 눌러 주세요."
    finally:
        try:
            if tmp is not None:
                tmp.unlink(missing_ok=True)
        except OSError:
            pass  # A subsequent retry truncates an incomplete file.
