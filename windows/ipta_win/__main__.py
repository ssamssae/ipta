from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Allow `python3 -m ipta_win` from the windows/ folder.
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ipta_win import info  # noqa: E402
from ipta_win.hotkeys import HotkeyListener  # noqa: E402
from ipta_win.selftest import run_selftest  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ipta")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--selftest-output", type=Path)
    args = parser.parse_args(argv)
    if args.selftest_output:
        from contextlib import redirect_stdout, redirect_stderr
        with args.selftest_output.open("w", encoding="utf-8") as output:
            with redirect_stdout(output), redirect_stderr(output):
                from ipta_win import ui, audio, transcribe
                import subprocess
                from ipta_win.winhide import hidden_kwargs
                failed = run_selftest()
                binary = transcribe.whisper_cli()
                if binary is None:
                    print("FAIL bundled whisper missing")
                    return 1
                result = subprocess.run([str(binary), "--help"], capture_output=True, timeout=15, **hidden_kwargs())
                print("PASS bundled whisper" if result.returncode == 0 else "FAIL bundled whisper")
                return failed or int(result.returncode != 0)
    if args.selftest:
        return run_selftest()
    from ipta_win.ui import launch

    def bind(app) -> None:
        listener = HotkeyListener(
            app.state.toggle_hotkey,
            app.state.cancel_hotkey,
            on_toggle=app.state.toggle,
            on_cancel=app.state.cancel,
        )
        listener.start()
        info.log("ui start")

    launch(on_ready=bind)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
