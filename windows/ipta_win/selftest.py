from __future__ import annotations

from . import info, oauth, polish, speech


def check(name: str, cond: bool) -> int:
    print(("PASS " if cond else "FAIL ") + name)
    return 0 if cond else 1


def run_selftest() -> int:
    failed = 0
    failed += check("no apple provider", "apple" not in polish.ALL_PROVIDERS)
    failed += check("free hides cloud", polish.visible_providers("free", True) == ["local"])
    failed += check("free hides local when missing", polish.visible_providers("free", False) == [])
    failed += check("connected keeps claude", "claude" in polish.visible_providers("connected", True))
    failed += check("connected hides local when missing", "local" not in polish.visible_providers("connected", False))
    plan = polish.PolishPlan.load({"tier": "free", "provider": "claude"}, local_available=True)
    failed += check("free cloud falls back local", plan.provider == "local" and plan.can_attempt_model(True))
    plan = polish.PolishPlan.load({"provider": "apple"}, local_available=False)
    failed += check("stored apple is dropped", plan.provider != "apple")
    failed += check("apple is not a live provider", "apple" not in polish.visible_providers("connected", True))
    failed += check("default polish off is documented", polish.OUTSIDE_BRAIN_GUIDE.startswith("받아 적기는"))
    failed += check("local default 20b", polish.DEFAULT_MODELS["local"] == "gpt-oss-20b")
    failed += check("claude url", polish.CHAT_URLS["claude"].endswith("/v1/messages"))
    failed += check("cursor has no chat url", "cursor" not in polish.CHAT_URLS)
    req = polish.make_request("claude", "", "m", "s", "u")
    failed += check("claude request needs key", req is None)
    req = polish.make_request("claude", "sk-test", "m", "s", "u")
    failed += check("claude request ok", req is not None and req.full_url.startswith("https://api.anthropic.com"))
    parsed = polish.parse_text("openai", '{"choices":[{"message":{"content":"다듬은 글"}}]}'.encode())
    failed += check("openai parse", parsed == "다듬은 글")
    failed += check("clean fillers", speech.clean("음 그니까 오늘 회의") == "오늘 회의")
    failed += check("last intent", speech.clean("이거 말고 저걸로") == "저걸로")
    failed += check("edit command", speech.command_from("요약해줘") == "editSelection")
    failed += check("model url allowed", info.url_allowed(info.MODEL_URL))
    failed += check("http rejected", not info.url_allowed("http://huggingface.co/x"))
    ready_probe = oauth.parse_cursor_status('{"isAuthenticated": true}')
    failed += check("cursor json ready", ready_probe.ready and not ready_probe.blocked)
    print(f"failed={failed}")
    return 1 if failed else 0
