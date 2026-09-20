#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${MALGYEOL_OUT:-$ROOT/dist}"
APP="$OUT/Malgyeol.app"
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH_TAG="${IPTA_ARCH:-universal}"
case "$ARCH_TAG" in
  arm64) DMG="$OUT/Ipta-${VER}-arm64.dmg" ;;
  x86_64) DMG="$OUT/Ipta-${VER}-x86_64.dmg" ;;
  *) DMG="$OUT/Ipta-${VER}-macos.dmg" ;;
esac
STAGE="$OUT/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/입타.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/README.md" "$STAGE/README.txt"
hdiutil create -volname "입타 Ipta" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
shasum -a 256 "$DMG" | tee "${DMG}.sha256"
shasum -a 256 "$APP/Contents/MacOS/Ipta" | tee "$OUT/Ipta.exec.sha256"
echo "dmg=$DMG"
