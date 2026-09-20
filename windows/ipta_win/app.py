from __future__ import annotations

import tempfile
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from urllib.request import urlopen

from . import audio, info, keys, models, oauth, paste, polish, speech, store, transcribe


PHASES = {
    "idle": "대기",
    "recording": "녹음 중",
    "transcribing": "받아적는 중",
    "polishing": "다듬는 중",
    "downloading": "준비 파일 받는 중",
    "error": "오류",
}


@dataclass
class AppState:
    phase: str = "idle"
    status_line: str = "버튼을 누르면 받아 적습니다"
    transcript: str = ""
    raw_transcript: str = ""
    last_error: str = ""
    last_paste_note: str = ""
    download_note: str = ""
    download_progress: float = 0.0
    model_ready: bool = False
    polish_enabled: bool = False
    polish_plan: polish.PolishPlan = field(default_factory=polish.PolishPlan)
    oauth_note: str = ""
    oauth_ready: bool = False
    oauth_blocked: bool = False
    oauth_watching: bool = False
    recording: bool = False
    elapsed: float = 0.0
    level: float = 0.0
    devices: list[tuple[str, str]] = field(default_factory=list)
    selected_device_id: str = ""
    toggle_hotkey: str = store.DEFAULTS["toggle_hotkey"]
    cancel_hotkey: str = store.DEFAULTS["cancel_hotkey"]
    settings_notice: str = ""
    last_foreign_hwnd: int = 0
    last_cursor_hwnd: int = 0
    locked_hwnd: int = 0
    own_hwnds: tuple[int, ...] = ()
    _stop_record: bool = False
    _job: int = 0
    on_change: object | None = None

    def notify(self) -> None:
        if callable(self.on_change):
            self.on_change()

    def load_settings(self) -> None:
        data = store.load()
        self.polish_enabled = bool(data.get("polish_enabled"))
        self.polish_plan = polish.PolishPlan.load(data.get("polish") if isinstance(data.get("polish"), dict) else {})
        self.toggle_hotkey = str(data.get("toggle_hotkey") or store.DEFAULTS["toggle_hotkey"])
        self.cancel_hotkey = str(data.get("cancel_hotkey") or store.DEFAULTS["cancel_hotkey"])
        self.selected_device_id = str(data.get("selected_device_id") or "")
        self.refresh()

    def persist(self) -> None:
        data = store.load()
        data["polish_enabled"] = self.polish_enabled
        data["polish"] = self.polish_plan.to_dict()
        data["toggle_hotkey"] = self.toggle_hotkey
        data["cancel_hotkey"] = self.cancel_hotkey
        data["selected_device_id"] = self.selected_device_id
        store.save(data)

    def refresh(self) -> None:
        self.devices = audio.list_devices()
        if self.devices:
            picked = audio.pick_device_id(self.devices, self.selected_device_id)
            if picked != self.selected_device_id:
                self.selected_device_id = picked
                data = store.load()
                data["selected_device_id"] = picked
                store.save(data)
        self.model_ready = models.size_looks_ready()
        if self.model_ready:
            self.download_note = "준비됐어요. 말해도 됩니다."
        elif self.phase != "downloading":
            self.download_note = "아직 준비 안 됐어요. 받기 버튼을 누르세요."
        foreign = paste.lock_target(self.own_hwnds)
        if foreign:
            self.last_foreign_hwnd = foreign
            if paste.is_cursor_window(foreign):
                self.last_cursor_hwnd = foreign
        self.refresh_oauth()
        self.notify()

    def refresh_oauth(self) -> None:
        if not self.polish_plan.uses_oauth:
            self.oauth_note = ""
            self.oauth_ready = False
            self.oauth_blocked = False
            return
        probe = oauth.probe(self.polish_plan.provider)
        self.oauth_ready = probe.ready
        self.oauth_blocked = probe.blocked
        self.oauth_note = probe.note

    def set_polish_enabled(self, enabled: bool) -> None:
        self.polish_enabled = enabled
        self.persist()
        self.notify()

    def set_polish_tier(self, tier: str) -> None:
        self.polish_plan.tier = tier
        visible = polish.visible_providers(tier, polish.local_studio_installed())
        if self.polish_plan.provider not in visible:
            self.polish_plan.provider = visible[0] if visible else "local"
            self.polish_plan.model = polish.DEFAULT_MODELS.get(self.polish_plan.provider, "gpt-oss-20b")
        self.polish_plan = polish.PolishPlan.load(self.polish_plan.to_dict())
        self.persist()
        self.refresh_oauth()
        self.notify()

    def set_polish_provider(self, provider: str) -> None:
        if provider not in polish.ALL_PROVIDERS:
            return
        self.polish_plan.provider = provider
        self.polish_plan.model = polish.DEFAULT_MODELS[provider]
        self.polish_plan = polish.PolishPlan.load(self.polish_plan.to_dict())
        self.persist()
        self.refresh_oauth()
        self.notify()

    def set_local_model(self, model: str) -> None:
        self.polish_plan.model = polish.resolve_local_model(model)
        self.persist()
        self.notify()

    def set_auth_mode(self, mode: str) -> None:
        self.polish_plan.auth_mode = mode
        self.persist()
        self.refresh_oauth()
        self.notify()

    def begin_oauth_login(self) -> str:
        self.polish_plan.auth_mode = "oauth"
        self.persist()
        note = oauth.start_login(self.polish_plan.provider)
        self.settings_notice = note
        self.oauth_note = note
        self.oauth_watching = True
        self.notify()

        def watch() -> None:
            for _ in range(90):
                time.sleep(2)
                self.refresh_oauth()
                if self.oauth_ready:
                    break
            self.oauth_watching = False
            self.notify()

        threading.Thread(target=watch, daemon=True).start()
        return note

    def download_model(self) -> None:
        if self.phase == "downloading":
            return
        self.phase = "downloading"
        self.status_line = "준비 파일을 받는 중"
        self.notify()

        def work() -> None:
            def progress(written: int, expected: int) -> None:
                self.download_progress = written / expected if expected else 0
                self.download_note = f"받는 중 {written / 1_000_000:.0f} / {expected / 1_000_000:.0f} MB"
                self.notify()

            err = models.download(on_progress=progress)
            if err:
                self.phase = "error"
                self.last_error = err
                self.download_note = err
            else:
                self.phase = "idle"
                self.model_ready = True
                self.download_note = "준비됐어요. 말해도 됩니다."
                self.last_error = ""
            self.notify()

        threading.Thread(target=work, daemon=True).start()

    def toggle(self) -> None:
        if self.phase == "recording":
            self.stop_and_transcribe()
        elif self.phase in ("downloading", "transcribing", "polishing"):
            self.cancel()
        else:
            self.start()

    def cancel(self) -> None:
        self._job += 1
        self._stop_record = True
        self.recording = False
        self.phase = "idle"
        self.status_line = "취소했습니다"
        self.notify()

    def start(self) -> None:
        if not self.model_ready:
            self.last_error = "아직 준비 안 됐어요. 받기 버튼을 누르세요."
            self.notify()
            return
        self._job += 1
        job = self._job
        self._stop_record = False
        self.recording = True
        self.phase = "recording"
        self.elapsed = 0
        self.last_error = ""
        self.status_line = "듣는 중"
        self.locked_hwnd = (
            paste.lock_target(self.own_hwnds)
            or self.last_cursor_hwnd
            or paste.find_cursor_window()
            or paste.find_telegram_cursor_chat()
            or self.last_foreign_hwnd
        )
        if self.locked_hwnd:
            self.last_foreign_hwnd = self.locked_hwnd
            if paste.is_cursor_window(self.locked_hwnd):
                self.last_cursor_hwnd = self.locked_hwnd
        self.notify()

        def work() -> None:
            wav = Path(tempfile.gettempdir()) / f"ipta-{job}.wav"
            started = time.time()

            def on_level(level: float) -> None:
                self.level = level
                self.elapsed = min(info.MAX_SECONDS, time.time() - started)
                self.notify()

            try:
                audio.record_wav(
                    wav,
                    info.MAX_SECONDS,
                    self.selected_device_id,
                    should_stop=lambda: self._stop_record or self._job != job,
                    on_level=on_level,
                )
            except Exception as exc:
                if self._job != job:
                    return
                self.recording = False
                self.phase = "error"
                self.last_error = str(exc)
                self.notify()
                return
            if self._job != job:
                return
            self.recording = False
            self.finish_wav(wav, job)

        threading.Thread(target=work, daemon=True).start()

    def stop_and_transcribe(self) -> None:
        self._stop_record = True

    def finish_wav(self, wav: Path, job: int) -> None:
        self.phase = "transcribing"
        self.status_line = "받아적는 중"
        self.notify()
        try:
            raw = transcribe.transcribe(wav)
        except Exception as exc:
            if self._job != job:
                return
            self.phase = "error"
            self.last_error = str(exc)
            self.notify()
            return
        if self._job != job:
            return
        self.raw_transcript = raw
        if not raw.strip():
            self.transcript = ""
            self.phase = "error"
            self.last_error = "말을 못 알아들었어요. 더 가까이서 말해보세요."
            self.status_line = "받아적기 실패"
            self.notify()
            info.log("done used_model=False chars=0 empty-transcript")
            return
        self.transcript = raw
        self.notify()
        try:
            text, note, used_model = self.polish_text(raw)
        except Exception:
            text, note, used_model = raw, "다듬기를 건너뛰고 받아 적은 글만 넣었습니다", False
        if self._job != job:
            return
        self.transcript = text
        self.status_line = note
        self.phase = "idle"
        if text:
            try:
                self.last_paste_note = paste.paste_into_foreground(
                    text,
                    target_hwnd=self.locked_hwnd,
                    skip_hwnds=self.own_hwnds,
                )
                info.log(f"paste {self.last_paste_note}")
            except Exception as exc:
                self.last_paste_note = "자동 입력에 실패했습니다. " + str(exc)
                info.log(f"paste failed type={type(exc).__name__}")
        self.notify()
        info.log(f"done used_model={used_model} chars={len(text)}")

    def polish_text(self, raw: str) -> tuple[str, str, bool]:
        cleaned = speech.clean(raw)
        if not self.polish_enabled:
            fallback = cleaned or raw
            return fallback, "받아 적었습니다" if fallback == raw else "군더더기를 빼고 넣었습니다", False
        plan = self.polish_plan
        if not plan.can_attempt_model():
            fallback = cleaned or raw
            return fallback, "다듬기 연결이 없어 기본만 했습니다", False
        self.phase = "polishing"
        self.status_line = "다듬는 중"
        self.notify()
        started = time.monotonic()
        failure = ""
        try:
            modeled = self.model_transform(plan, polish.POLISH_INSTRUCTIONS, cleaned or raw)
        except oauth.CliFailure as exc:
            failure, modeled = exc.reason, None
        except Exception:
            failure, modeled = "execution", None
        info.log(f"polish provider={plan.provider} elapsed={time.monotonic() - started:.2f} result={'ok' if modeled else failure or 'invalid_output'}")
        if modeled:
            return modeled, f"말한 글을 {polish.title(plan.provider)}로 다듬었습니다", True
        fallback = cleaned or raw
        if failure == "timeout":
            note = "AI 응답이 늦어 기본 다듬기만 했습니다. 로그인 문제는 확인되지 않았습니다"
        elif failure in ("auth", "auth_unavailable"):
            note = f"{polish.title(plan.provider)} AI 연결을 확인하지 못해 기본 다듬기만 했습니다. 설정에서 AI 로그인을 확인하세요"
        elif plan.uses_oauth:
            note = "AI 다듬기에 실패해 기본 다듬기만 했습니다. 윈도우 로그인 문제는 아닙니다"
        elif plan.needs_pasted_key and not keys.has_key(plan.provider):
            note = "키가 없어 기본 다듬기만 했습니다"
        elif cleaned == raw:
            note = "받아 적었습니다"
        else:
            note = "군더더기를 빼고 넣었습니다"
        return fallback, note, False

    def model_transform(self, plan: polish.PolishPlan, instructions: str, user: str) -> str | None:
        if plan.provider == "cursor" or plan.uses_oauth:
            key = keys.get_key(plan.provider) if plan.needs_pasted_key else ""
            text = oauth.polish_via_cli(plan.provider, instructions, user, key=key)
            return speech.sanitize(text, user) if text else None
        key = keys.get_key(plan.provider) if polish.needs_key(plan.provider) else ""
        req = polish.make_request(plan.provider, key, plan.model, instructions, user)
        if req is None:
            return None
        try:
            with urlopen(req, timeout=polish.request_timeout(plan.provider)) as resp:
                data = resp.read()
        except OSError:
            return None
        parsed = polish.parse_text(plan.provider, data)
        return speech.sanitize(parsed, user) if parsed else None
