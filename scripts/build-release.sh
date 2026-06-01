#!/usr/bin/env bash
# Build a universal (Intel + Apple Silicon) release binary and package a zip
# that a user can install WITHOUT Xcode. Output: dist/claude-signal-macos.zip
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building universal release binary (x86_64 + arm64)…"
swift build -c release --arch arm64 --arch x86_64

BIN=".build/apple/Products/Release/ClaudeSignal"
[ -f "$BIN" ] || { echo "error: universal binary not found at $BIN" >&2; exit 1; }
echo "Built: $(file "$BIN" | sed 's/^[^:]*: //')"

STAGE="$(mktemp -d)/claude-signal"
mkdir -p "$STAGE/hooks/tests"
cp "$BIN" "$STAGE/ClaudeSignal"
cp hooks/on-event.sh hooks/install.sh hooks/uninstall.sh "$STAGE/hooks/"
cp LaunchAgents/com.claudesignal.agent.plist.template "$STAGE/" 2>/dev/null || true
cp scripts/install-from-release.sh "$STAGE/install.sh"
chmod +x "$STAGE/ClaudeSignal" "$STAGE/hooks/"*.sh "$STAGE/install.sh"

mkdir -p "$ROOT/dist"
( cd "$(dirname "$STAGE")" && zip -r -q "$ROOT/dist/claude-signal-macos.zip" "claude-signal" )
rm -rf "$(dirname "$STAGE")"
echo "Packaged: dist/claude-signal-macos.zip"
echo "Upload that zip to a GitHub Release. Users run ./install.sh after unzipping."
