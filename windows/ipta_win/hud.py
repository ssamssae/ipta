from __future__ import annotations

HUD_WIDTH = 320
HUD_HEIGHT = 56
HUD_BOTTOM = 28


def hud_geometry(screen_w: int, screen_h: int, width: int = HUD_WIDTH, height: int = HUD_HEIGHT, bottom: int = HUD_BOTTOM) -> str:
    x = max(0, (screen_w - width) // 2)
    y = max(0, screen_h - height - bottom)
    return f"{width}x{height}+{x}+{y}"


def hud_title(phase: str) -> str:
    return {"recording": "듣는 중", "transcribing": "받아적는 중", "polishing": "다듬는 중"}.get(phase, "입타")


def hud_subtitle(phase: str, elapsed: float) -> str:
    if phase == "recording":
        return f"{elapsed:.0f}초 · 같은 키로 멈춤"
    return "잠시만요"
