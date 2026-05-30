#!/usr/bin/env bash
# Registers on-event.sh into ~/.claude/settings.json for the events we track.
# Non-destructive: preserves existing settings and other hooks. Idempotent.
set -euo pipefail

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
HOOK="$(cd "$(dirname "$0")" && pwd)/on-event.sh"
EVENTS=(UserPromptSubmit PreToolUse PostToolUse Notification Stop SubagentStop SessionEnd)

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Backup once.
cp "$SETTINGS" "$SETTINGS.claude-signal.bak"

tmp="$(mktemp)"
jq --arg hook "$HOOK" --argjson events "$(printf '%s\n' "${EVENTS[@]}" | jq -R . | jq -s .)" '
  .hooks = (.hooks // {})
  | reduce $events[] as $e (.;
      .hooks[$e] = ((.hooks[$e] // [])
        # drop any prior claude-signal entry for idempotency
        | map(select(any(.hooks[]?; .command == $hook) | not))
        + [{ "hooks": [ { "type": "command", "command": $hook } ] }]
      )
    )
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "Installed claude-signal hooks into $SETTINGS (backup: $SETTINGS.claude-signal.bak)"
