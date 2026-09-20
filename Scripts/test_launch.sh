#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${MALGYEOL_OUT:-$ROOT/dist}"
APP="$OUT/Malgyeol.app"
TESTDIR="${MALGYEOL_LAUNCH_DIR:-/tmp/malgyeol-dmg-launch-r2}"
rm -rf "$TESTDIR"
mkdir -p "$TESTDIR"
if [[ ! -d "$APP" ]]; then
  echo "app missing: $APP" >&2
  exit 1
fi
cp -R "$APP" "$TESTDIR/입타.app"
echo "copied to $TESTDIR/입타.app"
# Launch without activating worker terminals; LSUIElement app
open "$TESTDIR/입타.app"
sleep 2
if pgrep -lf '입타.app/Contents/MacOS/Ipta|Malgyeol.app/Contents/MacOS/Ipta|Malgyeol.app/Contents/MacOS/Malgyeol' >/dev/null; then
  echo "LAUNCH_OK"
  pgrep -lf 'Ipta|입타|Malgyeol'
else
  echo "LAUNCH_FAIL" >&2
  exit 2
fi
