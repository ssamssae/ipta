#!/usr/bin/env bash
# Reproducible 입타 .app build. Does not require Homebrew at runtime.
# IPTA_ARCH=arm64|x86_64|universal  (default: universal — one product for Intel + Apple Silicon)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${MALGYEOL_OUT:-$ROOT/dist}"
BUILD="$ROOT/.build-cache"
APP="$OUT/Malgyeol.app"
PIN_WHISPER="${WHISPER_REF:-v1.7.5}"
DEPLOY=14.0
IPTA_ARCH="${IPTA_ARCH:-universal}"
case "$IPTA_ARCH" in
  arm64|x86_64|universal) ;;
  *) echo "IPTA_ARCH must be arm64, x86_64, or universal (got $IPTA_ARCH)" >&2; exit 1 ;;
esac

export CC="${CC:-/usr/bin/clang}"
export CXX="${CXX:-/usr/bin/clang++}"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"
mkdir -p "$BUILD" "$OUT"

log() { printf '[ipta-build] %s\n' "$*"; }

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
log "cmake=$(command -v cmake) arch=$IPTA_ARCH"

WHISPER_SRC="$ROOT/Vendor/whisper.cpp"
if [[ ! -d "$WHISPER_SRC/.git" ]]; then
  log "clone whisper.cpp $PIN_WHISPER"
  mkdir -p "$ROOT/Vendor"
  git clone --depth 1 --branch "$PIN_WHISPER" https://github.com/ggerganov/whisper.cpp.git "$WHISPER_SRC"
fi
WHISPER_HEAD="$(git -C "$WHISPER_SRC" rev-parse HEAD)"
log "whisper HEAD=$WHISPER_HEAD"

build_whisper() {
  local arch="$1"
  local bld="$BUILD/whisper-worker-build-$arch"
  mkdir -p "$bld"
  # GGML_NATIVE=ON on an M-series host injects -mcpu=apple-m4 into the x86_64 slice.
  local cflags="-arch ${arch} -mmacosx-version-min=${DEPLOY}"
  if [[ "$arch" == "x86_64" ]]; then
    cflags+=" -march=x86-64 -mtune=generic"
  fi
  cmake -S "$ROOT/Native" -B "$bld" \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_C_FLAGS="$cflags" \
    -DCMAKE_CXX_FLAGS="$cflags" \
    -DWHISPER_BUILD_EXAMPLES=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_NATIVE=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON >&2
  cmake --build "$bld" --config Release --target whisper-cli ipta-transcriber -j "$(sysctl -n hw.ncpu)" >&2
  local cli
  cli="$(find "$bld" -name whisper-cli -type f | head -n 1)"
  if [[ -z "$cli" || ! -x "$cli" ]]; then
    echo "whisper-cli missing for $arch" >&2
    exit 1
  fi
  printf '%s\n' "$cli"
}

build_swift() {
  local arch="$1"
  (
    cd "$ROOT"
    swift build -c release --arch "$arch" \
      -Xswiftc -target -Xswiftc "${arch}-apple-macosx${DEPLOY}"
  ) >&2
  local bin
  bin="$(cd "$ROOT" && swift build -c release --arch "$arch" --show-bin-path)/Malgyeol"
  if [[ ! -x "$bin" ]]; then
    echo "swift binary missing for $arch: $bin" >&2
    exit 1
  fi
  printf '%s\n' "$bin"
}

if [[ "$IPTA_ARCH" == "universal" ]]; then
  log "whisper arm64"
  W_ARM="$(build_whisper arm64)"
  log "whisper x86_64"
  W_X86="$(build_whisper x86_64)"
  lipo -create -output "$BUILD/whisper-cli-universal" "$W_ARM" "$W_X86"
  CLI="$BUILD/whisper-cli-universal"
  lipo -create -output "$BUILD/ipta-transcriber-universal" "$BUILD/whisper-worker-build-arm64/ipta-transcriber" "$BUILD/whisper-worker-build-x86_64/ipta-transcriber"
  WORKER="$BUILD/ipta-transcriber-universal"
  log "swift arm64"
  S_ARM="$(build_swift arm64)"
  log "swift x86_64"
  S_X86="$(build_swift x86_64)"
  lipo -create -output "$BUILD/Ipta-universal" "$S_ARM" "$S_X86"
  BIN="$BUILD/Ipta-universal"
else
  CLI="$(build_whisper "$IPTA_ARCH")"
  WORKER="$BUILD/whisper-worker-build-$IPTA_ARCH/ipta-transcriber"
  BIN="$(build_swift "$IPTA_ARCH")"
fi
log "whisper-cli=$CLI"
log "swift-bin=$BIN"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources" "$APP/Contents/Library"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/App/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/App/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
cp "$BIN" "$APP/Contents/MacOS/Ipta"
cp "$CLI" "$APP/Contents/Helpers/whisper-cli"
cp "$WORKER" "$APP/Contents/Helpers/ipta-transcriber"
chmod 755 "$APP/Contents/MacOS/Ipta" "$APP/Contents/Helpers/whisper-cli" "$APP/Contents/Helpers/ipta-transcriber"

assert_metal() {
  local bin="$1"
  local arch="$2"
  if ! otool -arch "$arch" -l "$bin" | grep -q 'sectname __ggml_metallib'; then
    echo "whisper-cli $arch does not embed Metal shaders" >&2
    exit 3
  fi
}
if [[ "$IPTA_ARCH" == "universal" ]]; then
  assert_metal "$APP/Contents/Helpers/whisper-cli" arm64
  assert_metal "$APP/Contents/Helpers/whisper-cli" x86_64
  assert_metal "$APP/Contents/Helpers/ipta-transcriber" arm64
  assert_metal "$APP/Contents/Helpers/ipta-transcriber" x86_64
  for need in arm64 x86_64; do
    lipo -archs "$APP/Contents/MacOS/Ipta" | grep -qw "$need"
    lipo -archs "$APP/Contents/Helpers/whisper-cli" | grep -qw "$need"
    lipo -archs "$APP/Contents/Helpers/ipta-transcriber" | grep -qw "$need"
  done
else
  assert_metal "$APP/Contents/Helpers/whisper-cli" "$IPTA_ARCH"
  assert_metal "$APP/Contents/Helpers/ipta-transcriber" "$IPTA_ARCH"
  lipo -archs "$APP/Contents/MacOS/Ipta" | grep -qw "$IPTA_ARCH"
fi

# Drop build-machine toolchain rpaths. /usr/lib/swift stays.
while IFS= read -r rp; do
  log "delete rpath $rp"
  install_name_tool -delete_rpath "$rp" "$APP/Contents/MacOS/Ipta"
done < <(otool -arch all -l "$APP/Contents/MacOS/Ipta" | awk '/LC_RPATH/{f=1} f&&/path /{print $2; f=0}' | grep -E '^/Applications/Xcode|/Developer/Toolchains|/opt/homebrew|/usr/local|^/Users/' | sort -u || true)

for bin in "$APP/Contents/MacOS/Ipta" "$APP/Contents/Helpers/whisper-cli" "$APP/Contents/Helpers/ipta-transcriber"; do
  if otool -arch all -l "$bin" | awk '/LC_RPATH/{f=1} f&&/path /{print $2; f=0}' | grep -E '^/Applications/Xcode|/Developer/Toolchains|/opt/homebrew|/usr/local|^/Users/'; then
    echo "forbidden rpath in $bin" >&2
    exit 2
  fi
  if otool -arch all -L "$bin" | awk '/^\t/ {print $1}' | grep -E '/opt/homebrew|/usr/local|^/Users/'; then
    echo "forbidden path in $bin" >&2
    otool -arch all -L "$bin" >&2
    exit 2
  fi
done

IDENTITIES_FILE="$OUT/codesign-identities.txt"
security find-identity -v -p codesigning > "$IDENTITIES_FILE"
ID_COUNT="$(awk '/valid identities found/ {print $1}' "$IDENTITIES_FILE" | tail -1)"
ID_COUNT="${ID_COUNT:-0}"
SIGNING_KIND="adhoc"
NOTARIZED="no"
if [[ "$ID_COUNT" != "0" ]]; then
  SIGNING_KIND="developer-id-available-but-unused-adhoc"
fi

log "codesign identities count=$ID_COUNT (keys not printed)"
log "signing=$SIGNING_KIND notarized=$NOTARIZED"

printf '%s\n' "$WHISPER_HEAD" > "$APP/Contents/Resources/whisper-commit.txt"
printf '%s\n' "$PIN_WHISPER" > "$APP/Contents/Resources/whisper-ref.txt"
printf '%s\n' "$SIGNING_KIND" > "$APP/Contents/Resources/signing.txt"
printf '%s\n' "$NOTARIZED" > "$APP/Contents/Resources/notarized.txt"
printf '%s\n' "$IPTA_ARCH" > "$APP/Contents/Resources/arch.txt"

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
  --identifier app.ipta.Ipta \
  --entitlements "$ROOT/App/Malgyeol.entitlements" \
  "$APP"

codesign --verify --verbose=2 "$APP"
codesign --verify --verbose=2 "$APP/Contents/Helpers/whisper-cli"
codesign --verify --verbose=2 "$APP/Contents/MacOS/Ipta"

{
  echo "signing=$SIGNING_KIND"
  echo "notarized=$NOTARIZED"
  echo "arch=$IPTA_ARCH"
  echo "valid_identities=$ID_COUNT"
  echo "developer_id_usable=no"
  echo "reason=no valid codesigning identity in keychain; ad-hoc only. Not notarized."
  echo "--- identities listing (hashes/names only, no private keys) ---"
  cat "$IDENTITIES_FILE"
  echo "--- codesign -dv --verbose=4 (app) ---"
  codesign -dv --verbose=4 "$APP" 2>&1 || true
  echo "--- lipo ---"
  lipo -info "$APP/Contents/MacOS/Ipta" || true
  lipo -info "$APP/Contents/Helpers/whisper-cli" || true
} > "$OUT/codesign-report.txt"

VERIFY_COPY="$(mktemp -d)/Malgyeol.app"
cp -R "$APP" "$VERIFY_COPY"
codesign --verify --deep --strict --verbose=2 "$VERIFY_COPY"
rm -rf "$(dirname "$VERIFY_COPY")"

log "app=$APP"
log "arch=$IPTA_ARCH signing=$SIGNING_KIND notarized=$NOTARIZED"
