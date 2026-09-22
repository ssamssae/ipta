from __future__ import annotations

import sys
import tkinter as tk
from tkinter import messagebox, ttk
from typing import Callable

from . import info, paste, polish, store, personalization_ui
from .app import AppState, PHASES
from .hotkeys import label as hotkey_label
from .hud import hud_geometry, hud_subtitle, hud_title


def _noactivate(win: tk.Toplevel) -> None:
    if sys.platform != "win32":
        return
    import ctypes

    win.update_idletasks()
    hwnd = int(win.winfo_id())
    user32 = ctypes.windll.user32
    style = user32.GetWindowLongW(hwnd, -20)
    user32.SetWindowLongW(hwnd, -20, style | 0x08000000 | 0x00000080 | 0x00000008)


class IptaApp:
    def __init__(self, state: AppState):
        self.state = state
        self.root = tk.Tk()
        self.root.title(info.LABEL)
        self.root.geometry("380x650")
        self.root.minsize(340, 560)
        self.settings: tk.Toplevel | None = None
        self.hud: tk.Toplevel | None = None
        self.welcome: tk.Toplevel | None = None
        self.personal_window: tk.Toplevel | None = None
        state.on_change = self.refresh
        self._apply_icon()
        self._build_main()
        self._remember_own_hwnds()
        self.refresh()
        self.root.after(400, self._poll_foreign)
        if not store.load().get("windows_guide_seen"):
            self.root.after(100, self.open_start_guide)

    def _apply_icon(self) -> None:
        path = info.icon_path()
        if not path.is_file():
            return
        try:
            self.root.iconbitmap(default=str(path))
        except tk.TclError:
            pass

    def _build_main(self) -> None:
        pad = {"padx": 16, "pady": 4}
        ttk.Label(self.root, text=info.LABEL, font=("Segoe UI", 18, "bold")).pack(anchor="w", padx=16, pady=(16, 4))
        ttk.Label(
            self.root,
            text="받아적기는 이 컴퓨터에서만 합니다. 다듬기는 선택입니다. 그록·커서·클로드를 쓰려면 그 프로그램을 이 컴퓨터에 두고 본인 계정으로 로그인하세요.",
            wraplength=340,
        ).pack(anchor="w", **pad)
        self.toggle_btn = ttk.Button(self.root, text="녹음", command=self.state.toggle)
        self.toggle_btn.pack(fill="x", padx=16, pady=8)
        self.status = ttk.Label(self.root, text="", wraplength=340, font=("Segoe UI", 11, "bold"))
        self.status.pack(anchor="w", **pad)
        self.note = ttk.Label(self.root, text="", wraplength=340)
        self.note.pack(anchor="w", **pad)
        self.err = ttk.Label(self.root, text="", wraplength=340, foreground="#b00020")
        self.err.pack(anchor="w", **pad)
        self.model_box = ttk.Frame(self.root)
        self.model_box.pack(fill="x", padx=16, pady=4)
        self.model_progress = ttk.Progressbar(self.model_box, maximum=1.0, mode="determinate")
        self.model_progress.pack(fill="x", pady=4)
        self.model_btn = ttk.Button(self.model_box, text="지금 받기 · 약 465 MiB", command=self.state.download_model)
        self.model_btn.pack(anchor="w")
        ttk.Label(self.root, text="결과", font=("Segoe UI", 10, "bold")).pack(anchor="w", padx=16, pady=(12, 0))
        self.result = tk.Text(self.root, height=8, wrap="word")
        self.result.pack(fill="both", expand=True, padx=16, pady=8)
        btns = ttk.Frame(self.root)
        btns.pack(fill="x", padx=16, pady=(0, 16))
        ttk.Button(btns, text="시작 안내", command=self.open_start_guide).pack(side="left", padx=(0, 8))
        ttk.Button(btns, text="복사", command=lambda: paste.copy_text(self.state.transcript) if self.state.transcript else None).pack(side="left", padx=(0, 8))
        ttk.Button(btns, text="설정", command=self.open_settings).pack(side="left")
        ttk.Button(btns, text="숨기기", command=self.hide).pack(side="left", padx=8)

    def open_start_guide(self) -> None:
        if self.welcome and self.welcome.winfo_exists():
            self.welcome.lift()
            return
        win = tk.Toplevel(self.root)
        self.welcome = win
        win.title("입타 Windows 시작 안내")
        win.resizable(False, False)
        ttk.Label(win, text="처음 사용하시나요?", font=("Segoe UI", 14, "bold")).pack(anchor="w", padx=20, pady=(20, 8))
        for text in (
            "Windows 10/11 x64용입니다. 이 EXE에는 코드 서명이 없어 Windows가 ‘확인되지 않은 게시자’ 또는 SmartScreen 경고를 표시할 수 있습니다.",
            "배포처는 github.com/ssamssae/ipta입니다. 받은 파일의 SHA-256을 배포 파일과 비교하세요. 실행 전 차단 안내는 함께 제공되는 Windows-start-guide.html 또는 Windows README에서 볼 수 있습니다.",
            "SmartScreen에서 출처를 확인하고 신뢰하는 경우에만 ‘추가 정보 → 실행’을 선택하세요. 실행 선택지가 없거나 Smart App Control·조직 정책이 차단하면 관리자에게 문의하세요.",
            "첫 사용에는 인터넷 연결과 모델 약 465 MiB(약 488 MB)의 저장 공간이 필요합니다. ‘지금 받기’에서 진행률을 확인하고 실패하면 ‘다시 받기’를 누르세요.",
            "모델 준비 후 받아 적기는 오프라인으로 작동합니다. 온라인 제공자의 다듬기 기능은 별도로 인터넷 연결이 필요합니다.",
        ):
            ttk.Label(win, text=text, wraplength=400).pack(anchor="w", padx=20, pady=6)

        def acknowledge() -> None:
            try:
                data = store.load()
                data["windows_guide_seen"] = True
                store.save(data)
            except OSError:
                messagebox.showerror("입타", "설정을 저장하지 못했습니다. 폴더 권한과 저장 공간을 확인해 주세요.", parent=win)
                return
            win.destroy()

        ttk.Button(win, text="확인 · 시작하기", command=acknowledge).pack(anchor="e", padx=20, pady=16)
        self._remember_own_hwnds()

    def hide(self) -> None:
        self.root.withdraw()

    def show(self) -> None:
        self.root.deiconify()
        self.root.lift()

    def open_settings(self) -> None:
        if self.settings and self.settings.winfo_exists():
            self.settings.lift()
            return
        win = tk.Toplevel(self.root)
        win.title("설정")
        win.geometry("420x640")
        self.settings = win
        canvas = tk.Canvas(win, highlightthickness=0)
        scroll = ttk.Scrollbar(win, orient="vertical", command=canvas.yview)
        frame = ttk.Frame(canvas)
        frame.bind("<Configure>", lambda _e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=frame, anchor="nw")
        canvas.configure(yscrollcommand=scroll.set)
        canvas.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        ttk.Label(frame, text="설정", font=("Segoe UI", 14, "bold")).pack(anchor="w", padx=12, pady=8)
        ttk.Button(frame, text="개인 사전·앱별 말투·기록·음성 편집", command=self.open_personalization).pack(anchor="w", padx=12, pady=8)
        self._status_box(frame)
        self._polish_box(frame)
        self._hotkey_box(frame)
        ttk.Button(frame, text="닫기", command=win.destroy).pack(anchor="e", padx=12, pady=12)

    def open_personalization(self) -> None:
        if self.personal_window and self.personal_window.winfo_exists():
            self.personal_window.lift()
        else:
            self.personal_window = personalization_ui.open_window(self.root, self.state)
        self._remember_own_hwnds()

    def _status_box(self, parent: tk.Widget) -> None:
        box = ttk.LabelFrame(parent, text="지금 상태")
        box.pack(fill="x", padx=12, pady=6)
        self.settings_phase = ttk.Label(box, text="")
        self.settings_phase.pack(anchor="w", padx=8, pady=4)
        ttk.Label(box, text=f"기록 파일: {info.log_path()}", wraplength=360).pack(anchor="w", padx=8, pady=4)

    def _polish_box(self, parent: tk.Widget) -> None:
        box = ttk.LabelFrame(parent, text="말한 글 다듬기")
        box.pack(fill="x", padx=12, pady=6)
        ttk.Label(box, text=polish.OUTSIDE_BRAIN_GUIDE, wraplength=360).pack(anchor="w", padx=8, pady=6)
        self.polish_var = tk.BooleanVar(value=self.state.polish_enabled)
        ttk.Checkbutton(
            box,
            text="말한 글을 다듬어 넣기",
            variable=self.polish_var,
            command=lambda: self.state.set_polish_enabled(self.polish_var.get()),
        ).pack(anchor="w", padx=8)
        ttk.Label(box, text="어디서").pack(anchor="w", padx=8, pady=(8, 0))
        self.tier_var = tk.StringVar(value=self.state.polish_plan.tier)
        for value, title in polish.TIER_TITLES.items():
            ttk.Radiobutton(
                box,
                text=title,
                value=value,
                variable=self.tier_var,
                command=lambda v=value: self.state.set_polish_tier(v),
            ).pack(anchor="w", padx=16)
        ttk.Label(box, text="어디 모델").pack(anchor="w", padx=8, pady=(8, 0))
        self.provider_var = tk.StringVar(value=self.state.polish_plan.provider)
        self.provider_frame = ttk.Frame(box)
        self.provider_frame.pack(anchor="w", padx=8)
        self.provider_hint = ttk.Label(box, text="", wraplength=360)
        self.provider_hint.pack(anchor="w", padx=8, pady=4)
        self.oauth_label = ttk.Label(box, text="", wraplength=360)
        self.oauth_label.pack(anchor="w", padx=8)
        ttk.Button(box, text="로그인", command=self._login).pack(anchor="w", padx=8, pady=4)
        ttk.Button(box, text="키를 직접 넣을게요", command=lambda: self.state.set_auth_mode("key")).pack(anchor="w", padx=8)
        self.redraw_providers()

    def _login(self) -> None:
        note = self.state.begin_oauth_login()
        messagebox.showinfo(info.LABEL, note)

    def _hotkey_box(self, parent: tk.Widget) -> None:
        box = ttk.LabelFrame(parent, text="단축키")
        box.pack(fill="x", padx=12, pady=6)
        self.hotkey_label = ttk.Label(box, text="", wraplength=360)
        self.hotkey_label.pack(anchor="w", padx=8, pady=6)
        ttk.Label(box, text="기본은 Alt+D 시작/정지, Alt+Shift+C 취소입니다.").pack(anchor="w", padx=8, pady=4)

    def redraw_providers(self) -> None:
        for child in self.provider_frame.winfo_children():
            child.destroy()
        visible = polish.visible_providers(self.state.polish_plan.tier, polish.local_studio_installed())
        if not visible:
            ttk.Label(self.provider_frame, text="이 컴퓨터에 로컬 모델이 없습니다. 받아 적기만 쓰거나 바깥 머리를 고르세요.").pack(anchor="w")
            return
        for provider in visible:
            ttk.Radiobutton(
                self.provider_frame,
                text=polish.title(provider),
                value=provider,
                variable=self.provider_var,
                command=lambda p=provider: self.state.set_polish_provider(p),
            ).pack(anchor="w")

    def refresh(self) -> None:
        try:
            self.root.after(0, self._refresh_now)
        except tk.TclError:
            pass

    def _remember_own_hwnds(self) -> None:
        hwnds: list[int] = []
        for win in (self.root, self.settings, self.hud, self.welcome, self.personal_window):
            if win is None:
                continue
            try:
                if win.winfo_exists():
                    hwnds.append(int(win.winfo_id()))
            except tk.TclError:
                pass
        self.state.own_hwnds = tuple(hwnds)

    def _poll_foreign(self) -> None:
        if self.state.phase == "idle":
            foreign = paste.lock_target(self.state.own_hwnds)
            if foreign:
                self.state.last_foreign_hwnd = foreign
                if paste.is_cursor_window(foreign):
                    self.state.last_cursor_hwnd = foreign
        try:
            self.root.after(150, self._poll_foreign)
        except tk.TclError:
            pass

    def _refresh_now(self) -> None:
        self._remember_own_hwnds()
        self.toggle_btn.configure(text="정지" if self.state.recording else "녹음")
        self.status.configure(text=self.state.status_line)
        extra = self.state.download_note
        if self.state.last_paste_note:
            extra = f"{extra}\n{self.state.last_paste_note}".strip()
        self.note.configure(text=extra)
        self.err.configure(text=self.state.last_error)
        downloading = self.state.phase == "downloading"
        self.model_progress.configure(value=self.state.download_progress)
        self.model_btn.configure(
            text="준비 중…" if downloading else ("다시 받기" if self.state.download_failed else "지금 받기 · 약 465 MiB"),
            state="disabled" if downloading else "normal",
        )
        if self.state.model_ready:
            self.model_box.pack_forget()
        elif not self.model_box.winfo_manager():
            self.model_box.pack(fill="x", padx=16, pady=4, before=self.result)
        self.toggle_btn.configure(state="disabled" if downloading or not self.state.model_ready else "normal")
        busy = self.state.phase in ("downloading", "recording", "transcribing", "polishing")
        if not busy:
            self.result.delete("1.0", "end")
            self.result.insert("1.0", self.state.transcript or "아직 없습니다")
        self.sync_hud()
        if self.settings and self.settings.winfo_exists():
            self.settings_phase.configure(text=f"지금 하는 일: {PHASES.get(self.state.phase, self.state.phase)}")
            self.provider_hint.configure(text=polish.HINTS.get(self.state.polish_plan.provider, ""))
            self.oauth_label.configure(text=self.state.oauth_note)
            self.hotkey_label.configure(
                text=f"{hotkey_label(self.state.toggle_hotkey)} 시작/정지 · {hotkey_label(self.state.cancel_hotkey)} 취소"
            )
            self.redraw_providers()

    def _place_hud(self, hud: tk.Toplevel) -> None:
        hud.update_idletasks()
        sw = int(hud.winfo_screenwidth())
        sh = int(hud.winfo_screenheight())
        hud.geometry(hud_geometry(sw, sh))

    def _draw_levels(self, level: float) -> None:
        if not getattr(self, "hud_levels", None):
            return
        canvas = self.hud_levels
        canvas.delete("all")
        for i in range(7):
            on = level > i / 7.0
            color = "#e11d48" if on else "#6b7280"
            h = 8 + i * 2
            x = 4 + i * 10
            canvas.create_rectangle(x, 20 - h, x + 6, 20, fill=color, outline="")

    def _build_hud(self) -> tk.Toplevel:
        hud = tk.Toplevel(self.root)
        hud.overrideredirect(True)
        hud.attributes("-topmost", True)
        hud.configure(bg="#1c1c1e")
        try:
            hud.attributes("-alpha", 0.96)
        except tk.TclError:
            pass
        bar = tk.Frame(hud, bg="#1c1c1e")
        bar.pack(fill="both", expand=True, padx=12, pady=8)
        self.hud_dot = tk.Canvas(bar, width=12, height=12, bg="#1c1c1e", highlightthickness=0)
        self.hud_dot.pack(side="left")
        text = tk.Frame(bar, bg="#1c1c1e")
        text.pack(side="left", padx=8)
        self.hud_label = tk.Label(text, text="듣는 중", fg="#f5f5f5", bg="#1c1c1e", font=("Segoe UI", 11, "bold"))
        self.hud_label.pack(anchor="w")
        self.hud_sub = tk.Label(text, text="잠시만요", fg="#9ca3af", bg="#1c1c1e", font=("Segoe UI", 8))
        self.hud_sub.pack(anchor="w")
        self.hud_levels = tk.Canvas(bar, width=76, height=20, bg="#1c1c1e", highlightthickness=0)
        self.hud_levels.pack(side="left", padx=8)
        self.hud_stop = tk.Button(
            bar,
            text="정지",
            command=self.state.toggle,
            bg="#3f3f46",
            fg="#f5f5f5",
            relief="flat",
            width=4,
        )
        self.hud_stop.pack(side="right")
        self._place_hud(hud)
        _noactivate(hud)
        if self.state.locked_hwnd:
            paste.activate_hwnd(self.state.locked_hwnd)
        return hud

    def sync_hud(self) -> None:
        show = self.state.phase in ("recording", "transcribing", "polishing")
        if show and (self.hud is None or not self.hud.winfo_exists()):
            self.hud = self._build_hud()
            self._remember_own_hwnds()
        if self.hud and self.hud.winfo_exists():
            if not show:
                self.hud.destroy()
                self.hud = None
                return
            self.hud_label.configure(text=hud_title(self.state.phase))
            self.hud_sub.configure(text=hud_subtitle(self.state.phase, self.state.elapsed))
            self.hud_dot.delete("all")
            color = "#e11d48" if self.state.recording else "#f97316"
            self.hud_dot.create_oval(1, 1, 11, 11, fill=color, outline="")
            self._draw_levels(self.state.level if self.state.recording else 0)
            self.hud_stop.configure(text="정지" if self.state.recording else "취소")

    def run(self) -> None:
        self.root.mainloop()


def launch(on_ready: Callable[[IptaApp], None] | None = None) -> None:
    state = AppState()
    state.load_settings()
    app = IptaApp(state)
    if on_ready:
        on_ready(app)
    app.run()
