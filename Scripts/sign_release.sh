#!/usr/bin/env bash
# Developer ID sign + optional notarize. Does not print secrets.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${MALGYEOL_OUT:-$ROOT/dist}"
APP="$OUT/Malgyeol.app"
ENT="$ROOT/App/Malgyeol.entitlements"
ID="${MALGYEOL_SIGN_ID:-Developer ID Application: Minus Beta Studio (46UH85U2B8)}"
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH_TAG="${IPTA_ARCH:-universal}"
case "$ARCH_TAG" in
  arm64) DMG="$OUT/Ipta-${VER}-arm64.dmg" ;;
  x86_64) DMG="$OUT/Ipta-${VER}-x86_64.dmg" ;;
  *) DMG="$OUT/Ipta-${VER}-macos.dmg" ;;
esac
STAGE="$OUT/dmg-stage"

if ! security find-identity -v -p codesigning | grep -F "$ID" >/dev/null; then
  echo "missing_identity" >&2
  exit 4
fi

sign_macho() {
  codesign --force --options runtime --timestamp --sign "$ID" "$1"
}

while IFS= read -r f; do
  if file "$f" | grep -q 'Mach-O'; then
    sign_macho "$f"
  fi
done < <(find "$APP/Contents/Helpers" -type f)

codesign --force --options runtime --timestamp \
  --sign "$ID" \
  --entitlements "$ENT" \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" >"$OUT/codesign-devid.txt" 2>&1 || true

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/입타.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/README.md" "$STAGE/README.txt"
hdiutil create -volname "입타 Ipta" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$ID" "$DMG"
shasum -a 256 "$DMG" | tee "${DMG}.sha256"

NOTARIZED=no
if python3 "$ROOT/Scripts/notarize_release.py" "$DMG"; then
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  NOTARIZED=yes
else
  echo "notarize_failed_or_skipped" >&2
fi
printf '%s\n' "$NOTARIZED" >"$OUT/notarized.txt"
echo "dmg=$DMG notarized=$NOTARIZED"
