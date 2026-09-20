#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ipta_win import audio, speech
from ipta_win.selftest import check


def main() -> int:
    failed = 0
    failed += check("strip lead filler", speech.clean("음 오늘 날씨") == "오늘 날씨")
    failed += check("drop repeat", speech.clean("바로 바로 가자") == "바로 가자")
    failed += check("keep last intent", speech.clean("이걸로 아니라 저걸로 해") == "저걸로 해")
    failed += check("summarize command", speech.command_from("이거 요약") == "editSelection")
    failed += check("long spoken stays polish", speech.command_from("오늘 회의 내용 전부 정리해서 보내") == "polishSpoken")
    failed += check("reject invented hangul", not speech.keeps_spoken_facts("김치찌개 먹자", "오늘 회의"))
    failed += check("keep spoken facts", speech.keeps_spoken_facts("오늘 회의", "오늘 회의 하자"))
    failed += check("sanitize too long", speech.sanitize("가" * 80, "짧음") is None)
    mapped = audio.friendly_record_error(RuntimeError("Error opening InputStream: Invalid device [PaErrorCode -9996]"))
    failed += check("portaudio becomes no-mic", str(mapped) == audio.NO_MIC)
    devices = [("0", "Microsoft 기본 장치 - Input"), ("1", "마이크(USB AUDIO DEVICE)")]
    failed += check("prefer usb mic", audio.pick_device_id(devices, "") == "1")
    failed += check("keep chosen mic", audio.pick_device_id(devices, "0") == "0")
    failed += check("silent level low", audio.level_from_block([0.0] * 32) < 0.05)
    failed += check("loud level high", audio.level_from_block([0.4] * 32) > 0.7)
    print(f"failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
