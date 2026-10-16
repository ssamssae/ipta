#!/usr/bin/env bash
# 마이크 선택 정책(MicPolicy) 회귀 검사. CoreAudio 없이 순수 Swift 로 컴파일해 돌린다.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPTA_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$IPTA_TEST_DIR"' EXIT
swiftc "$ROOT/App/Sources/MicPolicy.swift" "$ROOT/Tests/MicPolicy/main.swift" -o "$IPTA_TEST_DIR/tests"
"$IPTA_TEST_DIR/tests"
