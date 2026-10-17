#!/usr/bin/env bash
# 고친 말 배우기(CorrectionLearning) 회귀 검사. Foundation 만으로 컴파일해 돌린다.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPTA_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$IPTA_TEST_DIR"' EXIT
swiftc "$ROOT/App/Sources/Personalization.swift" "$ROOT/App/Sources/CorrectionLearning.swift" "$ROOT/Tests/CorrectionLearning/main.swift" -o "$IPTA_TEST_DIR/tests"
"$IPTA_TEST_DIR/tests"
