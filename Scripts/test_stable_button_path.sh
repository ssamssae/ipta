#!/usr/bin/env bash
# @mutate-why SwiftUI ButtonGesture를 다시 쓰면 macOS 26 MainActor 클릭 크래시 경로가 되살아난다
# @mutate malgyeol-mac/App/Sources/ResultView.swift | AppKitActionButton( | Button(
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/App/Sources/ResultView.swift"
WRAPPER="$ROOT/App/Sources/AppKitActionButton.swift"

if grep -Eq '(^|[^[:alnum:]_])Button[[:space:]]*\(' "$VIEW"; then
  echo "SwiftUI Button call remains in ResultView" >&2
  exit 1
fi
grep -q 'struct AppKitActionButton: NSViewRepresentable' "$WRAPPER"
grep -q 'NSButton(' "$WRAPPER"
grep -q 'AppKitActionButton(' "$VIEW"

(
  cd "$ROOT"
  swift build -c release --arch arm64 \
    -Xswiftc -target -Xswiftc arm64-apple-macosx14.0
)

echo "PASS: AppKit target/action button path"
