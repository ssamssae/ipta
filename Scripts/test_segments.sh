#!/usr/bin/env bash
# 긴 녹음 미리 받아적기 구간 규칙(SegmentPlanner) 회귀 검사. Foundation 만으로 컴파일해 돌린다.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPTA_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$IPTA_TEST_DIR"' EXIT
swiftc "$ROOT/App/Sources/Segments.swift" "$ROOT/Tests/Segments/main.swift" -o "$IPTA_TEST_DIR/tests"
"$IPTA_TEST_DIR/tests"
