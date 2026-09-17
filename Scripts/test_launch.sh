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
cp -R "$APP" "$TESTDIR/말결.app"
echo "copied to $TESTDIR/말결.app"
# Launch without activating worker terminals; LSUIElement app
open "$TESTDIR/말결.app"
sleep 2
if pgrep -lf '말결.app/Contents/MacOS/Malgyeol|Malgyeol.app/Contents/MacOS/Malgyeol' >/dev/null; then
  echo "LAUNCH_OK"
  pgrep -lf 'Malgyeol|말결.app'
else
  echo "LAUNCH_FAIL" >&2
  exit 2
fi
