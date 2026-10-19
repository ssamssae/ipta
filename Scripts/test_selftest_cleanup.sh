#!/usr/bin/env bash
# 자체검사(--selftest)가 끝난 뒤 시험 흔적이 남지 않는지 밖에서 확인한다(T-261017-030).
# 화면이 있는 맥에서만 돈다. 실붙여넣기 시험이 TextEdit 을 열지 못했으면(손쉬운 사용 허용 없음 등) SKIP, 종료 3.
# 화면이 잠겨 있으면 TextEdit 을 아예 띄우지 않았는지 본다.
# IPTA_SELFTEST_BIN 으로 시험할 실행 파일을 고른다(기본 .build/debug/Malgyeol).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${IPTA_SELFTEST_BIN:-$ROOT/.build/debug/Malgyeol}"
DOC_DIR="${TMPDIR:-/tmp/}"
DOC_DIR="${DOC_DIR%/}/malgyeol-r4-textedit"
if [[ ! -x "$BIN" ]]; then
  echo "selftest binary missing: $BIN" >&2
  exit 1
fi

# running=0|1 test_windows=N — AX 로 보므로 자동화 허용 질문 창을 띄우지 않는다.
observe() {
  swift "$ROOT/Scripts/textedit_test_windows.swift" 2>/dev/null
}
field() {
  sed -n "s/.*$1=\\([0-9]*\\).*/\\1/p" <<<"$2"
}
test_files() {
  [[ -d "$DOC_DIR" ]] || { echo 0; return; }
  find "$DOC_DIR" -maxdepth 1 -name 'r4-malgyeol-r4-*.txt' | awk 'END{print NR+0}'
}

screen_locked() {
  ioreg -n Root -d1 -a 2>/dev/null | grep -A1 CGSSessionScreenIsLocked | grep -q true
}
# 클립보드는 읽기만 한다(내용 대신 해시).
clip_sha() {
  pbpaste 2>/dev/null | shasum -a 256 | cut -c1-16
}

before="$(observe)"
files_before="$(test_files)"
clip_before="$(clip_sha)"
locked=no
if screen_locked; then locked=yes; fi
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
# 시험 중에 TextEdit 이 새로 떴는지 0.2초마다 본다(시험이 끝나면 다시 꺼지므로 끝난 뒤에는 알 수 없다).
"$BIN" --selftest >"$OUT" 2>&1 &
selftest_pid=$!
launched=no
while kill -0 "$selftest_pid" 2>/dev/null; do
  if [[ "$(field running "$before")" == 0 ]] && pgrep -x TextEdit >/dev/null; then launched=yes; fi
  sleep 0.2
done
wait "$selftest_pid" || true
grep -E '^(PASS|FAIL|BLOCKED|SKIP|REAL) real' "$OUT" || true

failed=0
checks=0
check() {
  checks=$((checks + 1))
  if [[ "$2" == ok ]]; then
    echo "PASS $1"
  else
    echo "FAIL $1"
    failed=$((failed + 1))
  fi
}
# 합성 시험이 클립보드를 덮어써도 끝나면 사용자 것으로 돌아와야 한다.
check "clipboard text restored" "$([[ "$(clip_sha)" == "$clip_before" ]] && echo ok || echo no)"
# 잠긴 화면에서는 TextEdit 이 앞으로 못 나와 붙여넣기를 못 한다 — 띄우지도 말아야 한다.
if [[ $locked == yes ]]; then
  check "TextEdit not launched while the screen is locked" "$([[ $launched == no ]] && echo ok || echo no)"
fi
if grep -qE '^SKIP real textedit|real paste not attempted|TextEdit not found' "$OUT"; then
  echo "SKIP real paste did not open TextEdit"
  if [[ $checks -eq 0 ]]; then exit 3; fi
  echo "failed=$failed"
  [[ $failed -eq 0 ]]
  exit
fi
sleep 1
after="$(observe)"
files_after="$(test_files)"
check "TextEdit running state restored (before: $before / after: $after)" \
  "$([[ "$(field running "$after")" == "$(field running "$before")" ]] && echo ok || echo no)"
check "no test document window left" \
  "$([[ "$(field test_windows "$after")" -le "$(field test_windows "$before")" ]] && echo ok || echo no)"
check "test file removed (files before=$files_before after=$files_after)" \
  "$([[ "$files_after" -le "$files_before" ]] && echo ok || echo no)"
echo "failed=$failed"
[[ $failed -eq 0 ]]
