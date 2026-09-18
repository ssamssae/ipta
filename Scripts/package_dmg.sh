#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${MALGYEOL_OUT:-$ROOT/dist}"
APP="$OUT/Malgyeol.app"
DMG="$OUT/Malgyeol-0.1.1-arm64.dmg"
STAGE="$OUT/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/입타.app"
ln -s /Applications "$STAGE/Applications"
# README for the disk image
cp "$ROOT/README.md" "$STAGE/README.txt"
hdiutil create -volname "입타 Ipta" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
shasum -a 256 "$DMG" | tee "$OUT/Malgyeol-0.1.1-arm64.dmg.sha256"
shasum -a 256 "$APP/Contents/MacOS/Malgyeol" | tee "$OUT/Malgyeol.exec.sha256"
echo "dmg=$DMG"
