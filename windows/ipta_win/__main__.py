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
    parser.add_argument("--selftest-model", type=Path)
    parser.add_argument("--selftest-audio", type=Path)
    args = parser.parse_args(argv)
    if bool(args.selftest_model) != bool(args.selftest_audio):
        parser.error("--selftest-model and --selftest-audio must be supplied together")
    if args.selftest_model and not args.selftest_output:
        parser.error("transcription smoke test requires --selftest-output")
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
                if failed or result.returncode != 0:
                    return 1
                if args.selftest_model:
                    import re
                    import time
                    start = time.monotonic()
                    result = subprocess.run(
                        [str(binary), "-m", str(args.selftest_model), "-f", str(args.selftest_audio),
                         "-l", "en", "-nt", "-t", "4"],
                        capture_output=True, timeout=60, cwd=binary.parent, **hidden_kwargs(),
                    )
                    transcript = result.stdout.decode("utf-8", errors="replace").lower()
                    diagnostics = result.stderr.decode("utf-8", errors="replace")
                    accelerated = re.search(r"loaded CPU backend from .*ggml-cpu-(sandybridge|haswell|skylakex|icelake|alderlake)\.dll", diagnostics)
                    ok = result.returncode == 0 and "country" in transcript and bool(accelerated)
                    print(f"{'PASS' if ok else 'FAIL'} bundled transcription {time.monotonic() - start:.2f}s")
                    print(diagnostics)
                    return int(not ok)
                return 0
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
