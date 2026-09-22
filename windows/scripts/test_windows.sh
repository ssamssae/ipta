#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
export IPTA_SUPPORT_DIR="${IPTA_SUPPORT_DIR:-$ROOT/.tmp-support}"
mkdir -p "$IPTA_SUPPORT_DIR"
python3 -m ipta_win --selftest
python3 "$ROOT/tests/test_windows_polish.py"
python3 "$ROOT/tests/test_windows_speech.py"
python3 "$ROOT/tests/test_windows_oauth.py"
python3 "$ROOT/tests/test_windows_guide.py"
python3 "$ROOT/tests/test_windows_hud.py"
python3 "$ROOT/tests/test_windows_recovery.py"
python3 "$ROOT/tests/test_provider_workspace.py"
python3 "$ROOT/tests/test_windows_parity.py"
python3 "$ROOT/tests/test_windows_personalization_ui.py"
echo OK
