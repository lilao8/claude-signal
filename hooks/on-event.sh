#!/usr/bin/env bash
# Reads a Claude Code hook payload (JSON on stdin) and updates this session's
# state file under $CLAUDE_SIGNAL_DIR/sessions/<session_id>.json.
set -uo pipefail
# Note: intentionally NOT `set -e`. Malformed/empty stdin makes jq exit non-zero
# inside command substitution; we want that to become an empty string and a clean
# no-op exit, not abort the hook (which Claude Code would log as an error).

BASE="${CLAUDE_SIGNAL_DIR:-$HOME/.claude-signal}"
DIR="$BASE/sessions"
mkdir -p "$DIR"

input="$(cat)"
event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty')"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -z "$sid" ] && exit 0

file="$DIR/$sid.json"
now="$(date +%s)"

write_state() {
  local state="$1"
  jq -n --arg sid "$sid" --arg st "$state" --arg cwd "$cwd" --argjson now "$now" \
    '{session_id:$sid, state:$st, updated_at:$now, cwd:($cwd | if . == "" then null else . end), source:"claude"}' \
    > "$file.tmp" && mv "$file.tmp" "$file" || rm -f "$file.tmp"
}

case "$event" in
  UserPromptSubmit|PreToolUse|PostToolUse|SubagentStop)
    write_state "working" ;;
  Notification)
    msg="$(printf '%s' "$input" | jq -r '.message // empty')"
    case "$msg" in
      *permission*|*"needs your permission"*) write_state "permission" ;;
      *)                           write_state "working" ;;
    esac ;;
  Stop)
    write_state "done" ;;
  SessionEnd)
    rm -f "$file" ;;
  *)
    : ;;  # SessionStart and anything else: no-op (no file => off)
esac
exit 0
