#!/usr/bin/env bash
# Builds a release binary, installs it, and loads a per-user LaunchAgent
# so claude-signal starts at login.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

swift build -c release --package-path "$ROOT"
BIN_SRC="$ROOT/.build/release/ClaudeSignal"
BIN_DST="$HOME/.local/bin/claude-signal"
mkdir -p "$(dirname "$BIN_DST")"
cp "$BIN_SRC" "$BIN_DST"

PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST="$PLIST_DIR/com.claudesignal.agent.plist"
mkdir -p "$PLIST_DIR"
# Escape & (special in sed replacement) for safety; # is already our delimiter.
ESCAPED_DST="${BIN_DST//&/\\&}"
sed "s#__BINARY__#$ESCAPED_DST#" "$ROOT/LaunchAgents/com.claudesignal.agent.plist.template" > "$PLIST"

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Loaded LaunchAgent. Binary: $BIN_DST  Plist: $PLIST"
echo "To stop: launchctl unload \"$PLIST\""
