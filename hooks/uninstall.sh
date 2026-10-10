#!/usr/bin/env bash
# Removes claude-signal hook entries from ~/.claude/settings.json.
set -euo pipefail
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
[ -f "$SETTINGS" ] || { echo "no settings file"; exit 0; }
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
jq '
  if .hooks then
    .hooks |= with_entries(
      # Any claude-signal hook, including ones registered from an older install folder.
      .value |= map(select(any(.hooks[]?; (.command // "") | test("claude-signal[^/]*/hooks/on-event\\.sh$")) | not))
    )
  else . end
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "Removed claude-signal hooks from $SETTINGS"
