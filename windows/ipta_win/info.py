from __future__ import annotations

import os
from pathlib import Path

PRODUCT_KO = "입타"
PRODUCT_EN = "Ipta"
LABEL = "입타"
MAX_SECONDS = 60.0
MODEL_NAME = "ggml-small.bin"
MODEL_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
MODEL_SHA256 = "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
MODEL_BYTES = 487_601_967
WHISPER_CLI_NAME = "whisper-cli.exe"


def host_allowed(host: str) -> bool:
    h = (host or "").lower()
    if h == "huggingface.co" or h.endswith(".huggingface.co"):
        return True
    if h.endswith(".cdn.hf.co") or h.endswith(".xethub.hf.co"):
        return True
    return False


def url_allowed(url: str) -> bool:
    from urllib.parse import urlparse

    parsed = urlparse(url)
    return parsed.scheme == "https" and host_allowed(parsed.hostname or "")


def support_dir() -> Path:
    override = os.environ.get("IPTA_SUPPORT_DIR") or os.environ.get("MALGYEOL_SUPPORT_DIR")
    if override:
        path = Path(override)
    else:
        base = os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming")
        path = Path(base) / "Ipta"
    path.mkdir(parents=True, exist_ok=True)
    return path


def models_dir() -> Path:
    path = support_dir() / "Models"
    path.mkdir(parents=True, exist_ok=True)
    return path


def model_path() -> Path:
    return models_dir() / MODEL_NAME


def helpers_dir() -> Path:
    path = support_dir() / "Helpers"
    path.mkdir(parents=True, exist_ok=True)
    return path


def icon_path() -> Path:
    bundled = Path(__file__).resolve().parents[1] / "ipta.ico"
    if bundled.is_file():
        return bundled
    return support_dir() / "ipta.ico"


def log_path() -> Path:
    return support_dir() / "ipta.log"


def settings_path() -> Path:
    return support_dir() / "settings.json"


def keys_dir() -> Path:
    path = support_dir() / "keys"
    path.mkdir(parents=True, exist_ok=True)
    return path


def log(message: str) -> None:
    from datetime import datetime, timezone

    line = f"{datetime.now(timezone.utc).isoformat()} {message}\n"
    path = log_path()
    with path.open("a", encoding="utf-8") as fh:
        fh.write(line)
