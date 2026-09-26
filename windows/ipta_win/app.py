from __future__ import annotations

import tempfile
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from urllib.request import urlopen

from . import personalization, selection
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
    download_failed: bool = False
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
    personal: personalization.Personalization = field(default_factory=personalization.Personalization)
    selection_edit_enabled: bool = False
    target_app: str = ""
    selected_text: selection.Selection | None = None
    _selection_ready: threading.Event = field(default_factory=threading.Event)
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
        self.personal.load()
        self.selection_edit_enabled = bool(data.get("selection_edit_enabled"))
        if self.personal.error: self.last_error = self.personal.error
        self.refresh()
        if self.model_ready: transcribe.prepare()

    def persist(self) -> None:
        data = store.load()
        data["polish_enabled"] = self.polish_enabled
        data["polish"] = self.polish_plan.to_dict()
        data["toggle_hotkey"] = self.toggle_hotkey
        data["cancel_hotkey"] = self.cancel_hotkey
        data["selected_device_id"] = self.selected_device_id
        data["selection_edit_enabled"] = self.selection_edit_enabled
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
            self.download_note = "첫 사용에는 인터넷으로 모델 약 465 MiB를 받아야 합니다. 준비 후에는 오프라인으로 받아 적을 수 있습니다."
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
        if self.phase in ("downloading", "recording", "transcribing", "polishing"):
            return
        self.phase = "downloading"
        self.download_failed = False
        self.download_progress = 0.0
        self.last_error = ""
        self.download_note = "서버에 연결하는 중 · 약 465 MiB · 인터넷 연결이 필요합니다"
        self.status_line = "준비 파일을 받는 중"
        self.notify()

        def work() -> None:
            last_update = 0.0

            def progress(written: int, expected: int) -> None:
                nonlocal last_update
                now = time.monotonic()
                if written < expected and now - last_update < 0.1:
                    return
                last_update = now
                self.download_progress = min(written / expected, 1.0) if expected else 0
                self.download_note = f"{self.download_progress:.0%} · {written / 1048576:.1f} / {expected / 1048576:.1f} MiB"
                if written == expected:
                    self.status_line = "다운로드 완료 · 파일 무결성 확인 중"
                self.notify()

            err = models.download(on_progress=progress)
            if err:
                self.phase = "error"
                self.download_failed = True
                self.status_line = "준비 파일을 받지 못했습니다"
                self.last_error = err
                self.download_note = "연결·저장 공간을 확인한 뒤 다시 받을 수 있습니다."
            else:
                self.phase = "idle"
                self.model_ready = True
                transcribe.prepare()
                self.download_progress = 1.0
                self.status_line = "준비 완료 · 녹음 버튼을 누르세요"
                self.download_note = "준비됐어요. 인터넷 없이 받아 적을 수 있습니다."
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
        if self.phase == "downloading":
            self.download_note = "모델 준비 중입니다. 완료 또는 연결 시간 초과까지 기다려 주세요."
            self.notify()
            return
        self._job += 1
        transcribe.cancel()
        self._stop_record = True
        self.recording = False
        self.phase = "idle"
        self.status_line = "취소했습니다"
        self.notify()

    def start(self) -> None:
        if not self.model_ready:
            self.last_error = "첫 사용에는 인터넷으로 모델 약 465 MiB를 받아야 합니다. 준비 후에는 오프라인으로 받아 적을 수 있습니다."
            self.notify()
            return
        self._job += 1
        job = self._job
        self._stop_record = False
        transcribe.prepare()
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

        self.target_app = paste.process_name(self.locked_hwnd)
        self.selected_text = None
        ready = threading.Event()
        self._selection_ready = ready
        def capture_selection():
            try:
                captured = selection.capture(self.locked_hwnd) if self.selection_edit_enabled else None
                if self._job == job: self.selected_text = captured
            finally: ready.set()
        threading.Thread(target=capture_selection, daemon=True).start()

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
        if not raw.strip():
            self.phase = "error"
            self.last_error = "말을 못 알아들었어요. 더 가까이서 말해보세요."
            self.status_line = "알아들은 내용이 없어 이전 결과를 유지했습니다" if self.transcript else "받아적기 실패"
            self.notify()
            info.log("done used_model=False chars=0 empty-transcript")
            return
        self.raw_transcript = raw
        self._selection_ready.wait(timeout=3.1) if self.selection_edit_enabled else None
        if self._job != job: return
        instruction = personalization.edit_instruction(raw) if self.selection_edit_enabled else None
        if instruction:
            self.finish_selection_edit(raw, instruction, job)
            return
        normalized = self.personal.apply(raw)
        self.transcript = normalized
        self.notify()
        try:
            text, note, used_model = self.polish_text(normalized)
        except Exception:
            text, note, used_model = normalized, "다듬기를 건너뛰고 받아 적은 글만 넣었습니다", False
        if self._job != job:
            return
        try: self.personal.remember(raw, text, self.target_app)
        except (OSError, ValueError): self.last_error = "기록을 저장하지 못했습니다. 받아쓰기 결과는 아래에 남아 있습니다."
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

    def recover_history(self, record_id: str) -> bool:
        if self.phase not in ("idle", "error"): return False
        record = next((r for r in self.personal.data['history'] if r['id']==record_id), None)
        if not record: return False
        self.transcript, self.raw_transcript = record['text'], record['raw']
        self.status_line = "이전 결과를 복구했습니다. 복사해서 사용하세요."
        self.notify()
        return True

    def finish_selection_edit(self, raw: str, instruction: str, job: int) -> None:
        snapshot = self.selected_text
        self.phase = "idle"
        if not snapshot:
            self.transcript = ""
            self.status_line = "선택한 글을 읽지 못했습니다. 지원되는 입력칸에서 글을 선택한 뒤 다시 말해 주세요."
            self.notify(); return
        if not self.polish_enabled or not self.polish_plan.can_attempt_model():
            self.transcript = snapshot.text
            self.status_line = "선택 글 편집에는 AI 다듬기 연결이 필요합니다. 원문을 유지했습니다."
            self.notify(); return
        self.phase, self.status_line = "polishing", "선택한 글을 다듬는 중"
        self.notify()
        try: edited = self.model_transform(self.polish_plan, instruction, snapshot.text, editing=True)
        except Exception: edited = None
        if self._job != job: return
        self.phase = "idle"
        if not edited:
            self.transcript = snapshot.text
            self.status_line = "편집에 실패해 선택한 원문을 유지했습니다."
        else:
            self.transcript = edited
            try: inserted = selection.replace_if_unchanged(snapshot, edited)
            except Exception: inserted = False
            self.status_line = "선택한 글 교체를 요청했습니다" if inserted else "선택한 글이나 입력칸이 바뀌어 자동 입력하지 않았습니다. 결과를 복사하세요."
            try: self.personal.remember(snapshot.text, edited, self.target_app)
            except (OSError, ValueError): self.last_error = "기록 저장 실패"
        self.notify()

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
            modeled = self.model_transform(plan, polish.POLISH_INSTRUCTIONS + "\n" + self.personal.instructions(self.target_app, cleaned or raw), cleaned or raw)
        except oauth.CliFailure as exc:
            failure, modeled = exc.reason, None
        except Exception:
            failure, modeled = "execution", None
        info.log(f"polish provider={plan.provider} elapsed={time.monotonic() - started:.2f} result={'ok' if modeled else failure or 'invalid_output'}")
        if modeled:
            required = [entry['spelling'] for entry in self.personal.data['vocabulary'] if entry['spelling'] in (cleaned or raw)]
            if not speech.keeps_spoken_facts(modeled, cleaned or raw) or not all(word in modeled for word in required):
                return cleaned or raw, "숫자나 등록한 단어가 바뀌어 기본 다듬기 결과를 보관했습니다", False
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

    def model_transform(self, plan: polish.PolishPlan, instructions: str, user: str, *, editing: bool = False) -> str | None:
        if plan.provider == "cursor" or plan.uses_oauth:
            key = keys.get_key(plan.provider) if plan.needs_pasted_key else ""
            text = oauth.polish_via_cli(plan.provider, instructions, user, key=key)
            return (text.strip() if editing and text and len(text)<=20000 else None) if editing else (speech.sanitize(text, user) if text else None)
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
        return (parsed.strip() if editing and parsed and len(parsed)<=20000 else None) if editing else (speech.sanitize(parsed, user) if parsed else None)
