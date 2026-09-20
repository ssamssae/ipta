from __future__ import annotations

import sys
import wave
from collections.abc import Callable
from pathlib import Path

NO_MIC = (
    "마이크가 꺼져 있거나 기본 입력이 없습니다. "
    "윈도우 설정에서 소리 → 입력으로 가서 마이크를 켜고 기본으로 지정하세요."
)


def _host_name(sd, item: dict) -> str:
    try:
        return str(sd.query_hostapis()[int(item.get("hostapi") or 0)].get("name") or "")
    except Exception:
        return ""


def list_devices() -> list[tuple[str, str]]:
    if sys.platform != "win32":
        return []
    try:
        import sounddevice as sd
    except ImportError:
        return []
    devices = []
    for idx, item in enumerate(sd.query_devices()):
        if int(item.get("max_input_channels") or 0) <= 0:
            continue
        if "WDM-KS" in _host_name(sd, item):
            continue
        name = str(item.get("name") or f"장치 {idx}")
        devices.append((str(idx), name))
    return devices


PREFER_MIC = ("usb audio", "usb", "마이크", "microphone", "headset", "헤드셋", "wireless")
AVOID_MIC = ("stereo mix", "스테레오 믹스", "what u hear", "loopback", "케이블 출력")


def pick_device_id(devices: list[tuple[str, str]], selected: str = "") -> str:
    if selected and any(item[0] == selected for item in devices):
        return selected
    usable = [(did, name) for did, name in devices if not any(tok in name.lower() for tok in AVOID_MIC)]
    if not usable:
        usable = list(devices)
    for did, name in usable:
        lower = name.lower()
        if any(tok in lower for tok in PREFER_MIC):
            return did
    return usable[0][0] if usable else ""


def level_from_block(samples) -> float:
    flat: list[float] = []
    try:
        import numpy as np

        data = np.asarray(samples, dtype="float32").reshape(-1)
        if data.size == 0:
            return 0.0
        peak = float(np.max(np.abs(data)))
        rms = float(np.sqrt(np.mean(np.square(data))))
        return float(min(1.0, max(0.0, max(peak * 2.4, rms * 14))))
    except ImportError:
        for item in samples:
            if hasattr(item, "__iter__") and not isinstance(item, (str, bytes)):
                flat.extend(float(x) for x in item)
            else:
                flat.append(float(item))
        if not flat:
            return 0.0
        peak = max(abs(x) for x in flat)
        rms = (sum(x * x for x in flat) / len(flat)) ** 0.5
        return float(min(1.0, max(0.0, max(peak * 2.4, rms * 14))))


def friendly_record_error(exc: BaseException) -> RuntimeError:
    text = str(exc)
    if any(token in text for token in ("WDM-KS", "Blocking API", "Invalid device", "device -1", "PaErrorCode")):
        return RuntimeError(NO_MIC)
    return RuntimeError(
        "마이크를 열지 못했습니다. 다른 앱이 쓰고 있는지 보고, 윈도우 소리 설정에서 입력을 확인해 주세요."
    )


def record_wav(
    dest: Path,
    seconds: float,
    device_id: str = "",
    should_stop: Callable[[], bool] | None = None,
    on_level: Callable[[float], None] | None = None,
) -> None:
    if sys.platform != "win32":
        raise RuntimeError("녹음은 윈도우에서만 됩니다")
    try:
        import numpy as np
        import sounddevice as sd
    except ImportError as exc:
        raise RuntimeError("녹음 준비 파일이 없습니다. requirements-windows.txt 를 설치하세요.") from exc

    usable = list_devices()
    if not usable:
        raise RuntimeError(NO_MIC)

    samplerate = 16000
    chosen = pick_device_id(usable, device_id)
    device: int | None = int(chosen) if chosen.isdigit() else None
    frames: list[np.ndarray] = []
    chunk = 1024

    def callback(indata, _frames, _time, status):  # type: ignore[no-untyped-def]
        frames.append(indata.copy())
        if on_level:
            on_level(level_from_block(indata))

    try:
        with sd.InputStream(
            samplerate=samplerate,
            channels=1,
            dtype="float32",
            device=device,
            blocksize=chunk,
            callback=callback,
        ):
            import time

            started = time.time()
            while time.time() - started < seconds:
                if should_stop and should_stop():
                    break
                time.sleep(0.05)
    except Exception as exc:
        raise friendly_record_error(exc) from exc

    if not frames:
        raise RuntimeError("소리가 녹음되지 않았습니다")
    audio = np.concatenate(frames, axis=0)
    pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2").tobytes()
    dest.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(dest), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(samplerate)
        wav.writeframes(pcm)
