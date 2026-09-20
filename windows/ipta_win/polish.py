from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.request import Request

PROVIDERS_OFF_DEVICE = ("claude", "grok", "openai", "cursor")
PROVIDERS_ON_DEVICE = ("local",)
ALL_PROVIDERS = ("local", "claude", "grok", "openai", "cursor")

TITLES = {
    "local": "이 컴퓨터에 있는 모델",
    "claude": "클로드",
    "grok": "그록",
    "openai": "코덱스",
    "cursor": "커서",
}

TIER_TITLES = {"free": "이 컴퓨터에서만", "connected": "바깥 머리"}
AUTH_TITLES = {"oauth": "이 컴퓨터 로그인", "key": "내 키"}

DEFAULT_MODELS = {
    "local": "gpt-oss-20b",
    "claude": "claude-sonnet-4-5",
    "grok": "grok-4",
    "openai": "gpt-5",
    "cursor": "cursor-default",
}

HINTS = {
    "local": "이 컴퓨터 LM Studio에 켜 둔 모델로 다듬습니다. 글은 이 컴퓨터에만 있습니다.",
    "claude": "클로드를 이 컴퓨터에 이미 켜 둔 뒤, 로그인 버튼을 누르면 브라우저가 열립니다. 본인 계정으로 로그인하면 자동으로 붙습니다.",
    "grok": "그록을 이 컴퓨터에 이미 켜 둔 뒤, 로그인 버튼을 누르면 브라우저가 열립니다. 본인 계정으로 로그인하면 자동으로 붙습니다.",
    "openai": "코덱스를 이 컴퓨터에 이미 켜 둔 뒤, 로그인 버튼을 누르면 브라우저가 열립니다. 본인 계정으로 로그인하면 자동으로 붙습니다.",
    "cursor": "커서를 이 컴퓨터에 이미 켜 둔 뒤, 로그인 버튼을 누르면 브라우저가 열립니다. 본인 계정으로 로그인하면 자동으로 붙습니다.",
}

INSTALL_URLS = {
    "claude": "https://code.claude.com/docs/en/overview",
    "grok": "https://grok.x.ai",
    "openai": "https://github.com/openai/codex",
    "cursor": "https://cursor.com/docs/cli/overview",
}

CHAT_URLS = {
    "claude": "https://api.anthropic.com/v1/messages",
    "grok": "https://api.x.ai/v1/chat/completions",
    "openai": "https://api.openai.com/v1/chat/completions",
    "local": "http://127.0.0.1:1234/v1/chat/completions",
}

LOCAL_MODELS = {
    "gpt-oss-20b": {
        "title": "20비 — 가볍고 빠름",
        "hint": "이 컴퓨터에서 덜 버벅입니다. LM Studio에 gpt-oss-20b가 켜져 있어야 합니다.",
        "paths": (
            ".lmstudio/models/lmstudio-community/gpt-oss-20b-GGUF",
            ".lmstudio/models/local/gpt-oss-20b",
        ),
    },
    "qwen3.8-27b": {
        "title": "27비 — 한국어 더 나음",
        "hint": "한국어가 보통 더 낫습니다. 이 컴퓨터에서는 더 묵직합니다. LM Studio에 qwen3.8-27b가 켜져 있어야 합니다.",
        "paths": (
            ".lmstudio/models/mlx-community/Qwen3.8-27B-4bit",
            ".lmstudio/models/local/qwen3.8-27b",
        ),
    },
}

OUTSIDE_BRAIN_GUIDE = (
    "받아 적기는 입타만으로 됩니다. 그록·커서·클로드·코덱스로 다듬으려면 그 프로그램을 "
    "이 컴퓨터에 먼저 두고, 본인 계정으로 로그인하세요. 요금은 그 계정으로 나갑니다."
)

POLISH_INSTRUCTIONS = """받아적은 말을 글로 다듬는다. 의미와 고유명사는 유지한다.
음, 어, 그니까 같은 군더더기는 뺀다. 중간에 고친 말은 마지막 의도만 남긴다.
같은 말 반복은 한 번만. 목록이면 줄을 나눈다.
새 음식, 장소, 사람, 이유를 만들지 않는다. 추천하거나 질문으로 바꾸지 않는다.
설명 없이 다듬은 문장만 출력한다."""

EDIT_INSTRUCTIONS = """사용자가 고른 글을 지시에 맞게 다룬다. 새 사실은 만들지 않는다.
요약이면 짧게. 설명 없이 결과 문장만 출력한다."""


def title(provider: str) -> str:
    return TITLES[provider]


def sends_off_device(provider: str) -> bool:
    return provider in PROVIDERS_OFF_DEVICE


def needs_key(provider: str) -> bool:
    return provider in PROVIDERS_OFF_DEVICE


def supports_oauth(provider: str) -> bool:
    return provider in PROVIDERS_OFF_DEVICE


def request_timeout(provider: str) -> float:
    if provider == "local":
        return 60
    if provider in PROVIDERS_OFF_DEVICE:
        return 90
    return 12


def missing_program_note(provider: str) -> str:
    name = title(provider)
    return f"이 컴퓨터에 {name} 프로그램이 없습니다. {name}을 이 컴퓨터에 깐 다음, 받는 곳 버튼으로 안내를 보고 다시 고르세요."


def local_model_present(model: str, home: Path | None = None) -> bool:
    root = home or Path.home()
    spec = LOCAL_MODELS.get(model)
    if not spec:
        return False
    return any((root / rel).exists() for rel in spec["paths"])


def local_studio_installed(home: Path | None = None) -> bool:
    return any(local_model_present(model, home=home) for model in LOCAL_MODELS)


def visible_providers(tier: str, local_available: bool) -> list[str]:
    if tier == "free":
        base = [p for p in ALL_PROVIDERS if not sends_off_device(p)]
    else:
        base = list(ALL_PROVIDERS)
    if not local_available:
        base = [p for p in base if p != "local"]
    return base


def resolve_local_model(raw: str) -> str:
    return raw if raw in LOCAL_MODELS else "gpt-oss-20b"


@dataclass
class PolishPlan:
    tier: str = "free"
    provider: str = "local"
    model: str = DEFAULT_MODELS["local"]
    auth_mode: str = "oauth"

    @classmethod
    def load(cls, data: dict[str, Any] | None = None, *, local_available: bool | None = None) -> "PolishPlan":
        src = data or {}
        local_ok = local_studio_installed() if local_available is None else local_available
        tier = src.get("tier") if src.get("tier") in ("free", "connected") else "free"
        provider = src.get("provider") if src.get("provider") in ALL_PROVIDERS else "local"
        if provider == "apple":
            provider = "local"
        if tier == "free" and sends_off_device(provider):
            provider = "local"
        if provider == "local" and not local_ok:
            provider = "local"
        stored = str(src.get("model") or "")
        if provider == "local":
            model = resolve_local_model(stored or DEFAULT_MODELS["local"])
        else:
            model = stored or DEFAULT_MODELS[provider]
        raw_auth = str(src.get("auth_mode") or "")
        if supports_oauth(provider):
            prefer_key = bool(src.get("prefer_pasted_key"))
            auth_mode = "key" if raw_auth == "key" and prefer_key else "oauth"
        else:
            auth_mode = "key"
        return cls(tier=tier, provider=provider, model=model, auth_mode=auth_mode)

    def to_dict(self) -> dict[str, Any]:
        return {
            "tier": self.tier,
            "provider": self.provider,
            "model": self.model,
            "auth_mode": self.auth_mode,
            "prefer_pasted_key": self.auth_mode == "key" and supports_oauth(self.provider),
        }

    @property
    def uses_oauth(self) -> bool:
        return self.tier == "connected" and self.auth_mode == "oauth" and supports_oauth(self.provider)

    @property
    def needs_pasted_key(self) -> bool:
        return self.tier == "connected" and self.auth_mode == "key" and needs_key(self.provider)

    def can_attempt_model(self, local_available: bool | None = None) -> bool:
        local_ok = local_studio_installed() if local_available is None else local_available
        if self.provider == "local":
            return local_ok
        if self.tier == "free":
            return not sends_off_device(self.provider)
        return True


def make_request(provider: str, key: str, model: str, system: str, user: str) -> Request | None:
    url = CHAT_URLS.get(provider)
    if not url:
        return None
    if needs_key(provider) and not key.strip():
        return None
    headers = {"Content-Type": "application/json"}
    if provider == "claude":
        headers["x-api-key"] = key
        headers["anthropic-version"] = "2023-06-01"
        body: dict[str, Any] = {
            "model": model,
            "max_tokens": 220,
            "system": system,
            "messages": [{"role": "user", "content": user}],
        }
    else:
        if needs_key(provider):
            headers["Authorization"] = f"Bearer {key}"
        body = {
            "model": model,
            "temperature": 0.2,
            "max_tokens": 220,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        }
    req = Request(url, data=json.dumps(body).encode("utf-8"), headers=headers, method="POST")
    return req


def parse_text(provider: str, data: bytes) -> str | None:
    try:
        obj = json.loads(data.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    if not isinstance(obj, dict):
        return None
    if provider == "claude":
        content = obj.get("content")
        if not isinstance(content, list):
            return None
        texts = [item.get("text") for item in content if isinstance(item, dict)]
        joined = "".join(t for t in texts if isinstance(t, str)).strip()
        return joined or None
    if provider in ("grok", "openai", "local"):
        choices = obj.get("choices")
        if not isinstance(choices, list) or not choices:
            return None
        msg = choices[0].get("message") if isinstance(choices[0], dict) else None
        if not isinstance(msg, dict):
            return None
        content = msg.get("content")
        if isinstance(content, str) and content.strip():
            return content.strip()
        reasoning = msg.get("reasoning")
        if isinstance(reasoning, str):
            lines = [ln.strip() for ln in reasoning.splitlines() if ln.strip()]
            return lines[-1] if lines else None
    return None
