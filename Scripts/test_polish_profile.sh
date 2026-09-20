#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPTA_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$IPTA_TEST_DIR"' EXIT
swiftc "$ROOT/App/Sources/OAuthCLI.swift" "$ROOT/Tests/PolishProfile/main.swift" -o "$IPTA_TEST_DIR/tests"
"$IPTA_TEST_DIR/tests"
