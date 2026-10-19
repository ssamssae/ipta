#!/usr/bin/env bash
# 자체검사(--selftest)가 끝난 뒤 시험 흔적이 남지 않는지 밖에서 확인한다(T-261017-030).
# 화면이 있는 맥에서만 돈다. 실붙여넣기 시험이 TextEdit 을 열지 못했으면(손쉬운 사용 허용 없음 등) SKIP, 종료 3.
# 화면이 잠겨 있어도 돈다(TextEdit 이 다시 꺼졌는지·임시 파일이 지워졌는지로 판정).
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

before="$(observe)"
files_before="$(test_files)"
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
"$BIN" --selftest >"$OUT" 2>&1 || true
grep -E '^(PASS|FAIL|BLOCKED|SKIP|REAL) real' "$OUT" || true
if grep -qE '^SKIP real textedit|real paste not attempted|TextEdit not found' "$OUT"; then
  echo "SKIP real paste did not open TextEdit"
  exit 3
fi
sleep 1
after="$(observe)"
files_after="$(test_files)"

failed=0
check() {
  if [[ "$2" == ok ]]; then
    echo "PASS $1"
  else
    echo "FAIL $1"
    failed=$((failed + 1))
  fi
}
check "TextEdit running state restored (before: $before / after: $after)" \
  "$([[ "$(field running "$after")" == "$(field running "$before")" ]] && echo ok || echo no)"
check "no test document window left" \
  "$([[ "$(field test_windows "$after")" -le "$(field test_windows "$before")" ]] && echo ok || echo no)"
check "test file removed (files before=$files_before after=$files_after)" \
  "$([[ "$files_after" -le "$files_before" ]] && echo ok || echo no)"
echo "failed=$failed"
[[ $failed -eq 0 ]]
