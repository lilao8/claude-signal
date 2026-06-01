#!/usr/bin/env bash
# Install claude-signal from a prebuilt release (no Xcode needed).
# Run this from inside the unzipped folder.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

BIN_SRC="$HERE/ClaudeSignal"
[ -f "$BIN_SRC" ] || { echo "error: ClaudeSignal binary not found next to this script" >&2; exit 1; }

# 1) install the binary
BIN_DST="$HOME/.local/bin/claude-signal"
mkdir -p "$(dirname "$BIN_DST")"
cp "$BIN_SRC" "$BIN_DST"
chmod +x "$BIN_DST"
# strip the quarantine attribute so Gatekeeper doesn't block the unsigned binary
xattr -d com.apple.quarantine "$BIN_DST" 2>/dev/null || true

# 2) register Claude Code hooks (non-destructive)
bash "$HERE/hooks/install.sh"

# 3) install + load the LaunchAgent (auto-start at login)
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST="$PLIST_DIR/com.claudesignal.agent.plist"
mkdir -p "$PLIST_DIR"
TEMPLATE="$HERE/com.claudesignal.agent.plist.template"
if [ -f "$TEMPLATE" ]; then
  sed "s#__BINARY__#$BIN_DST#" "$TEMPLATE" > "$PLIST"
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  echo "Loaded LaunchAgent — claude-signal will auto-start at login."
else
  echo "warning: LaunchAgent template missing; binary installed but not auto-started." >&2
fi

echo "Done. The light should appear in your menu bar (and, on a notch Mac, around the notch)."
echo "If macOS blocked the app, right-click ~/.local/bin/claude-signal in Finder -> Open once."
