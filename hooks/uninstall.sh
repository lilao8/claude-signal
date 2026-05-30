#!/usr/bin/env bash
# Removes claude-signal hook entries from ~/.claude/settings.json.
set -euo pipefail
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
HOOK="$(cd "$(dirname "$0")" && pwd)/on-event.sh"
[ -f "$SETTINGS" ] || { echo "no settings file"; exit 0; }
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
jq --arg hook "$HOOK" '
  if .hooks then
    .hooks |= with_entries(
      .value |= map(select(any(.hooks[]?; .command == $hook) | not))
    )
  else . end
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "Removed claude-signal hooks from $SETTINGS"
