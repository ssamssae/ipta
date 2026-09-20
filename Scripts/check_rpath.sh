#!/usr/bin/env bash
set -euo pipefail
APP="${1:?app path}"
fail=0
audit() {
  local bin="$1"
  echo "== $bin"
  echo "-- otool -L --"
  otool -L "$bin"
  echo "-- LC_RPATH --"
  otool -l "$bin" | awk '/LC_RPATH/,/path/ {print}'
  if otool -arch all -L "$bin" | awk '/^\t/ {print $1}' | grep -E '/opt/homebrew|/usr/local|^/Users/'; then
    echo "FAIL: forbidden dylib path in $bin" >&2
    fail=1
  fi
  if otool -l "$bin" | grep -E 'path (/opt/homebrew|/usr/local|/Users/|/Applications/Xcode|.*/Developer/Toolchains)'; then
    echo "FAIL: forbidden rpath in $bin" >&2
    fail=1
  fi
}
while IFS= read -r bin; do
  if file "$bin" | grep -q 'Mach-O'; then
    audit "$bin"
  fi
done < <(find "$APP" -type f -perm +111)
exit "$fail"
