from __future__ import annotations

import re

_LEAD_FILLER = re.compile(r"^(음+|어+|아+|에+|그+)\s*")
_MID_FILLER = re.compile(r"(음+|어+)\s+")
_WS = re.compile(r"\s+")
_HANGUL_RUN = re.compile(r"[가-힣]{2,}")

FILLERS = ("그니까", "그러니까", "뭐랄까", "있잖아", "뭐지")
INTENT_SEPS = (" 아니라 ", " 아니야 ", " 아냐 ", " 아니 ", " 말고 ")
EDIT_PATS = (
    re.compile(r"^(이거|이걸|이글|선택)?(을|를)?(요약|짧게|정리|번역)"),
    re.compile(r"^(요약|짧게|정리)(해|해줘|해주세요)?$"),
)


def clean(raw: str) -> str:
    s = raw.strip()
    if not s:
        return s
    s = _WS.sub(" ", s)
    s = _LEAD_FILLER.sub("", s)
    s = _MID_FILLER.sub("", s)
    for filler in FILLERS:
        s = s.replace(filler, " ")
    s = _WS.sub(" ", s)
    s = keep_last_intent(s)
    s = drop_immediate_repeats(s)
    return s.strip()


def command_from(spoken: str) -> str:
    compact = spoken.strip().replace(" ", "")
    if len(compact) > 24:
        return "polishSpoken"
    for pat in EDIT_PATS:
        if pat.search(compact):
            return "editSelection"
    return "polishSpoken"


def keep_last_intent(s: str) -> str:
    last = -1
    sep_len = 0
    for sep in INTENT_SEPS:
        idx = s.rfind(sep)
        if idx > last:
            last = idx
            sep_len = len(sep)
    if last >= 0:
        tail = s[last + sep_len :].strip()
        if len(tail) >= 2:
            return tail
    return s


def drop_immediate_repeats(s: str) -> str:
    parts = s.split()
    if len(parts) < 2:
        return s
    out: list[str] = []
    for word in parts:
        if not out or out[-1] != word:
            out.append(word)
    return " ".join(out)


def keeps_spoken_facts(polished: str, source: str) -> bool:
    if "**" in polished:
        return False
    compact = re.sub(r"\s+", "", source)
    novel = [tok for tok in _HANGUL_RUN.findall(polished) if len(tok) >= 2 and tok not in compact]
    return len(novel) < 2


def sanitize(text: str, source: str) -> str | None:
    t = text.strip()
    if len(t) >= 2 and t[0] == '"' and t[-1] == '"':
        t = t[1:-1]
    if not t:
        return None
    if len(t) > max(len(source) * 2, 40):
        return None
    if not keeps_spoken_facts(t, source):
        return None
    return t
