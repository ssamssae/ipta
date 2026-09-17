#!/usr/bin/env bash
# Reproducible 말결 .app build. Does not require Homebrew at runtime.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${MALGYEOL_OUT:-$ROOT/dist}"
BUILD="$ROOT/.build-cache"
APP="$OUT/Malgyeol.app"
PIN_WHISPER="${WHISPER_REF:-v1.7.5}"
DEPLOY=14.0
ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
  echo "supports Apple Silicon arm64 only (got $ARCH)" >&2
  exit 1
fi
export CC="${CC:-/usr/bin/clang}"
export CXX="${CXX:-/usr/bin/clang++}"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"
mkdir -p "$BUILD" "$OUT"

log() { printf '[malgyeol-build] %s\n' "$*"; }

if ! command -v cmake >/dev/null 2>&1; then
  CMAKE_VER=3.30.5
  CMAKE_TGZ="$BUILD/cmake-${CMAKE_VER}-macos-universal.tar.gz"
  CMAKE_DIR="$BUILD/cmake-${CMAKE_VER}-macos-universal"
  if [[ ! -x "$CMAKE_DIR/CMake.app/Contents/bin/cmake" ]]; then
    log "fetch cmake ${CMAKE_VER} (build machine only)"
    curl -L --fail --retry 3 -o "$CMAKE_TGZ" \
      "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}-macos-universal.tar.gz"
    tar -xzf "$CMAKE_TGZ" -C "$BUILD"
  fi
  export PATH="$CMAKE_DIR/CMake.app/Contents/bin:$PATH"
fi
log "cmake=$(command -v cmake)"

WHISPER_SRC="$ROOT/Vendor/whisper.cpp"
if [[ ! -d "$WHISPER_SRC/.git" ]]; then
  log "clone whisper.cpp $PIN_WHISPER"
  mkdir -p "$ROOT/Vendor"
  git clone --depth 1 --branch "$PIN_WHISPER" https://github.com/ggerganov/whisper.cpp.git "$WHISPER_SRC"
fi
WHISPER_HEAD="$(git -C "$WHISPER_SRC" rev-parse HEAD)"
log "whisper HEAD=$WHISPER_HEAD"

WHISPER_BLD="$BUILD/whisper-build"
mkdir -p "$WHISPER_BLD"
cmake -S "$WHISPER_SRC" -B "$WHISPER_BLD" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DWHISPER_BUILD_EXAMPLES=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON
cmake --build "$WHISPER_BLD" --config Release --target whisper-cli -j "$(sysctl -n hw.ncpu)"

CLI="$(find "$WHISPER_BLD" -name whisper-cli -type f | head -n 1)"
if [[ -z "$CLI" ]]; then
  echo "whisper-cli missing" >&2
  exit 1
fi
log "whisper-cli=$CLI"

log "swift build"
cd "$ROOT"
swift build -c release --arch arm64 -Xswiftc -target -Xswiftc "arm64-apple-macosx${DEPLOY}"
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Malgyeol"
test -x "$BIN"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources" "$APP/Contents/Library"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/Malgyeol"
cp "$CLI" "$APP/Contents/Helpers/whisper-cli"
chmod 755 "$APP/Contents/MacOS/Malgyeol" "$APP/Contents/Helpers/whisper-cli"

# Metal shader library is embedded in whisper-cli (GGML_METAL_EMBED_LIBRARY=ON).
# Helpers/ must contain Mach-O only; loose .metal sources break codesign --verify.
if ! otool -l "$APP/Contents/Helpers/whisper-cli" | grep -q 'sectname __ggml_metallib'; then
  echo "whisper-cli does not embed Metal shaders; refusing to ship loose .metal in Helpers" >&2
  exit 3
fi

# Drop build-machine toolchain rpaths (e.g. /Applications/Xcode-*.app/.../swift-6.2). /usr/lib/swift stays.
while IFS= read -r rp; do
  log "delete rpath $rp"
  install_name_tool -delete_rpath "$rp" "$APP/Contents/MacOS/Malgyeol"
done < <(otool -l "$APP/Contents/MacOS/Malgyeol" | awk '/LC_RPATH/{f=1} f&&/path /{print $2; f=0}' | grep -E '^/Applications/Xcode|/Developer/Toolchains|/opt/homebrew|/usr/local|^/Users/' || true)

for bin in "$APP/Contents/MacOS/Malgyeol" "$APP/Contents/Helpers/whisper-cli"; do
  if otool -l "$bin" | awk '/LC_RPATH/{f=1} f&&/path /{print $2; f=0}' | grep -E '^/Applications/Xcode|/Developer/Toolchains|/opt/homebrew|/usr/local|^/Users/'; then
    echo "forbidden rpath in $bin" >&2
    exit 2
  fi
  if otool -L "$bin" | awk 'NR>1' | grep -E '/opt/homebrew|/usr/local|/Users/'; then
    echo "forbidden path in $bin" >&2
    otool -L "$bin" >&2
    exit 2
  fi
done

IDENTITIES_FILE="$OUT/codesign-identities.txt"
security find-identity -v -p codesigning > "$IDENTITIES_FILE"
VALID_IDS="$(grep -c 'valid identities found' "$IDENTITIES_FILE" || true)"
# The summary line is like "     0 valid identities found"
ID_COUNT="$(awk '/valid identities found/ {print $1}' "$IDENTITIES_FILE" | tail -1)"
ID_COUNT="${ID_COUNT:-0}"
SIGNING_KIND="adhoc"
NOTARIZED="no"
if [[ "$ID_COUNT" != "0" ]]; then
  SIGNING_KIND="developer-id-available-but-unused-adhoc"
fi

log "codesign identities count=$ID_COUNT (keys not printed)"
log "signing=$SIGNING_KIND notarized=$NOTARIZED"

# All bundle resources must exist BEFORE signing, or the resource seal breaks.
printf '%s\n' "$WHISPER_HEAD" > "$APP/Contents/Resources/whisper-commit.txt"
printf '%s\n' "$PIN_WHISPER" > "$APP/Contents/Resources/whisper-ref.txt"
printf '%s\n' "$SIGNING_KIND" > "$APP/Contents/Resources/signing.txt"
printf '%s\n' "$NOTARIZED" > "$APP/Contents/Resources/notarized.txt"

sign_macho() {
  local f="$1"
  if file "$f" | grep -q 'Mach-O'; then
    codesign --force --sign - --timestamp=none "$f"
  fi
}

while IFS= read -r f; do
  if ! file "$f" | grep -q 'Mach-O'; then
    echo "non-Mach-O file in Helpers: $f" >&2
    exit 3
  fi
  sign_macho "$f"
done < <(find "$APP/Contents/Helpers" -type f)

codesign --force --sign - --timestamp=none \
  --identifier app.malgyeol.Malgyeol \
  --entitlements "$ROOT/App/Malgyeol.entitlements" \
  "$APP"

codesign --verify --verbose=2 "$APP"
codesign --verify --verbose=2 "$APP/Contents/Helpers/whisper-cli"
codesign --verify --verbose=2 "$APP/Contents/MacOS/Malgyeol"

{
  echo "signing=$SIGNING_KIND"
  echo "notarized=$NOTARIZED"
  echo "valid_identities=$ID_COUNT"
  echo "developer_id_usable=no"
  echo "reason=no valid codesigning identity in keychain; ad-hoc only. Not notarized."
  echo "--- identities listing (hashes/names only, no private keys) ---"
  cat "$IDENTITIES_FILE"
  echo "--- codesign -dv --verbose=4 (app) ---"
  codesign -dv --verbose=4 "$APP" 2>&1 || true
} > "$OUT/codesign-report.txt"

# Post-sign check: a copy elsewhere must still verify (catches resources written after signing).
VERIFY_COPY="$(mktemp -d)/Malgyeol.app"
cp -R "$APP" "$VERIFY_COPY"
codesign --verify --deep --strict --verbose=2 "$VERIFY_COPY"
rm -rf "$(dirname "$VERIFY_COPY")"

log "app=$APP"
log "signing=$SIGNING_KIND notarized=$NOTARIZED"
