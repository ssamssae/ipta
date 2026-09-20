#!/usr/bin/env bash
# Intel / universal build surface. Does not compile whisper.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/Scripts/build.sh"
SIGN="$ROOT/Scripts/sign_release.sh"
PKG="$ROOT/Scripts/package_dmg.sh"
PKGSWIFT="$ROOT/Package.swift"
README="$ROOT/README.md"
fail=0

ok() { echo "PASS: $*"; }
bad() { echo "FAIL: $*" >&2; fail=1; }

grep -q 'IPTA_ARCH' "$BUILD" || bad "build.sh missing IPTA_ARCH"
grep -Eq 'arm64\|x86_64\|universal' "$BUILD" || bad "build.sh missing arch cases"
if grep -n 'supports Apple Silicon arm64 only' "$BUILD"; then
  bad "build.sh still refuses non-arm64 hosts"
else
  ok "no arm64-only host guard"
fi
grep -q 'build_whisper' "$BUILD" || bad "build.sh missing per-arch whisper"
grep -q 'lipo -create' "$BUILD" || bad "build.sh missing lipo"
grep -q 'GGML_NATIVE=OFF' "$BUILD" || bad "build.sh must disable GGML_NATIVE for Intel cross-compile"
grep -q 'otool -arch all -L' "$ROOT/Scripts/check_rpath.sh" || bad "check_rpath.sh must ignore fat-header paths"
grep -q 'x86_64' "$SIGN" || bad "sign_release.sh missing x86_64 dmg name"
grep -q 'macos.dmg' "$SIGN" || bad "sign_release.sh missing universal dmg name"
grep -q 'macos.dmg' "$PKG" || bad "package_dmg.sh missing universal dmg name"
grep -q 'weak_framework' "$PKGSWIFT" || bad "Package.swift must weak-link FoundationModels"
if grep -q 'linkedFramework("FoundationModels")' "$PKGSWIFT"; then
  bad "FoundationModels is still a required link"
else
  ok "FoundationModels is weak"
fi
grep -Eq 'Intel|x86_64|유니버설|인텔' "$README" || bad "README does not mention Intel"
bash -n "$BUILD" && bash -n "$SIGN" && bash -n "$PKG" && ok "bash -n scripts"

# Reject unknown arch without compiling.
if IPTA_ARCH=sparc bash "$BUILD" >/tmp/ipta-arch-bad.out 2>/tmp/ipta-arch-bad.err; then
  bad "unknown IPTA_ARCH should fail"
else
  grep -q 'IPTA_ARCH must be' /tmp/ipta-arch-bad.err && ok "unknown arch rejected" || bad "unknown arch message missing"
fi

[[ "$fail" -eq 0 ]] || exit 1
echo "intel arch tests passed"
