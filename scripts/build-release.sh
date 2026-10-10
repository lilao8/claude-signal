#!/usr/bin/env bash
# Build a universal (Intel + Apple Silicon) release binary and package a zip
# that a user can install WITHOUT Xcode. Output: dist/claude-signal-macos.zip
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building universal release binary (x86_64 + arm64)…"
ARCH_FLAGS=(-c release --arch arm64 --arch x86_64)
swift build "${ARCH_FLAGS[@]}"

# Ask SwiftPM where it put the product instead of hard-coding a path: the location changed
# between SwiftPM versions (.build/apple/... -> .build/out/...), and a stale binary left in
# the old location once got packaged as if it were fresh.
BIN="$(swift build "${ARCH_FLAGS[@]}" --show-bin-path 2>/dev/null | tail -1)/ClaudeSignal"
[ -f "$BIN" ] || { echo "error: universal binary not found at $BIN" >&2; exit 1; }
ARCHS="$(lipo -archs "$BIN")"
case " $ARCHS " in *" arm64 "*) ;; *) echo "error: $BIN lacks arm64 (has: $ARCHS)" >&2; exit 1 ;; esac
case " $ARCHS " in *" x86_64 "*) ;; *) echo "error: $BIN lacks x86_64 (has: $ARCHS)" >&2; exit 1 ;; esac
# Guard against packaging a stale binary: it must match the current sources' behaviour.
"$BIN" --simulate working@PreToolUse:15 present | grep -q "display=permission" \
  || { echo "error: $BIN does not behave like the current sources (stale build?)" >&2; exit 1; }
echo "Built: $BIN"
echo "       $(file "$BIN" | sed 's/^[^:]*: //')"

STAGE_ROOT="$(mktemp -d)"
trap 'rm -rf "$STAGE_ROOT"' EXIT
STAGE="$STAGE_ROOT/claude-signal"
mkdir -p "$STAGE/hooks/tests"
cp "$BIN" "$STAGE/ClaudeSignal"
cp hooks/on-event.sh hooks/install.sh hooks/uninstall.sh "$STAGE/hooks/"
cp LaunchAgents/com.claudesignal.agent.plist.template "$STAGE/" 2>/dev/null || true
cp scripts/install-from-release.sh "$STAGE/install.sh"
chmod +x "$STAGE/ClaudeSignal" "$STAGE/hooks/"*.sh "$STAGE/install.sh"

mkdir -p "$ROOT/dist"
( cd "$STAGE_ROOT" && zip -r -q "$ROOT/dist/claude-signal-macos.zip" "claude-signal" )
echo "Packaged: dist/claude-signal-macos.zip"
echo "Upload that zip to a GitHub Release. Users run ./install.sh after unzipping."
