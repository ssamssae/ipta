#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPTA_GROK_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$IPTA_GROK_TEST_DIR"' EXIT
swiftc -swift-version 5 "$ROOT/App/Sources/OAuthCLI.swift" "$ROOT/Tests/GrokCompletion/main.swift" -o "$IPTA_GROK_TEST_DIR/tests"
"$IPTA_GROK_TEST_DIR/tests" "$ROOT/Tests/GrokCompletion/fixture.py" "$IPTA_GROK_TEST_DIR"
