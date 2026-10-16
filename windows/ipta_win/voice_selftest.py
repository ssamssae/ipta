"""Exercise the packaged voice detector and both transcription paths on real WAVs."""
from __future__ import annotations

from array import array
import math
from pathlib import Path
import random
import sys
import tempfile
import wave

from . import transcribe
from .selftest import check
from .warm_engine import WarmEngine


def run(binary: Path, model: Path, spoken: Path) -> int:
    vad = transcribe.vad_model_path(binary)
    engine = WarmEngine(binary.with_name("ipta-transcriber.exe"), model, vad_model=vad)
    failed = 0
    try:
        first = engine.transcribe(spoken)
        pid = engine._proc.pid
        second = engine.transcribe(spoken)
        failed += check("bundled voiced worker reused", bool(first and second) and engine._proc.pid == pid)
        rng = random.Random(261017)
        fixtures = {
            "silence": [0] * 32000,
            "steady-noise": [rng.randint(-600, 600) for _ in range(32000)],
            "hum": [int(1200 * math.sin(2 * math.pi * 60 * i / 16000)) for i in range(32000)],
            "click": [12000 if i in (8000, 16000, 24000) else 0 for i in range(32000)],
        }
        with tempfile.TemporaryDirectory(prefix="ipta-voice-test-") as folder:
            for name, samples in fixtures.items():
                path = Path(folder) / (name + ".wav")
                pcm = array("h", samples)
                if sys.byteorder != "little": pcm.byteswap()
                with wave.open(str(path), "wb") as output:
                    output.setnchannels(1); output.setsampwidth(2); output.setframerate(16000)
                    output.writeframes(pcm.tobytes())
                failed += check("bundled worker rejects " + name, engine.transcribe(path) == "")
                failed += check("bundled CLI rejects " + name, transcribe._cli_transcribe(path, model, binary) == "")
        failed += check("bundled speech after silence preserved", bool(engine.transcribe(spoken)))
        return failed
    finally:
        engine.cancel()
