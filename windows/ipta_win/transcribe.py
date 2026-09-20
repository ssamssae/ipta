from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from . import info
from .winhide import hidden_kwargs


def whisper_cli(bundle_dir: Path | None = None) -> Path | None:
    names = ("whisper-cli.exe", "whisper-cli") if sys.platform != "win32" else ("whisper-cli.exe",)
    candidates: list[Path] = []
    if bundle_dir:
        candidates.extend(bundle_dir / name for name in names)
    bundled = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parents[1])) / "Helpers"
    candidates.extend(bundled / name for name in names)
    candidates.extend(info.helpers_dir() / name for name in names)
    here = Path(sys.executable).resolve().parent
    candidates.extend(here / name for name in names)
    for path in candidates:
        if path.is_file():
            return path
    return None


def transcribe(wav: Path, model: Path | None = None, cli: Path | None = None) -> str:
    binary = cli or whisper_cli()
    if binary is None:
        raise RuntimeError("앱 안의 whisper-cli 를 찾지 못했습니다. 다시 설치하세요.")
    model_file = model or info.model_path()
    if not model_file.is_file():
        raise RuntimeError("모델 파일이 없습니다. 창에서 모델을 받으세요.")
    out_base = wav.with_suffix("")
    proc = subprocess.run(
        [
            str(binary),
            "-m",
            str(model_file),
            "-f",
            str(wav),
            "-l",
            "ko",
            "-nt",
            "-np",
            "-otxt",
            "-of",
            str(out_base),
            "-t",
            "4",
        ],
        capture_output=True,
        check=False,
        cwd=str(binary.parent),
        env={**os.environ, "HOME": str(Path.home())},
        **hidden_kwargs(),
    )
    stdout = (proc.stdout or b"").decode("utf-8", errors="replace")
    stderr = (proc.stderr or b"").decode("utf-8", errors="replace")
    if proc.returncode != 0:
        raise RuntimeError(f"whisper-cli 종료 {proc.returncode}: {stderr[-400:]}")
    txt = Path(str(out_base) + ".txt")
    if txt.is_file():
        file_text = txt.read_text(encoding="utf-8", errors="replace").strip()
        if file_text:
            return file_text
    return stdout.strip()
