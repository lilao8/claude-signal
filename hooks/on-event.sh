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
RATELIMIT_FILE="$BASE/ratelimit.json"
SENTINEL=99999999999

input="$(cat)"
event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty')"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"

# Parse "resets 1:10am (America/Toronto)" from a StopFailure message and write
# ratelimit.json with reset_at = the NEXT occurrence of that clock time in that tz.
# Falls back to a far-future sentinel if it can't be parsed (red persists until activity).
write_ratelimit() {
  local msg="$1" clock tz reset_at h m ampm hh24 today
  clock="$(printf '%s' "$msg" | grep -oE '[0-9]{1,2}:[0-9]{2}[ap]m' | head -1)"
  tz="$(printf '%s' "$msg" | grep -oE '\([A-Za-z]+/[A-Za-z_]+\)' | head -1 | tr -d '()')"

  if [ -n "$clock" ] && [ -n "$tz" ]; then
    today="$(TZ="$tz" date '+%Y-%m-%d')"
    h="${clock%%:*}"
    m="$(printf '%s' "$clock" | sed -E 's/^[0-9]{1,2}:([0-9]{2})[ap]m/\1/')"
    ampm="$(printf '%s' "$clock" | grep -oE '[ap]m')"
    hh24="$h"
    if [ "$ampm" = "pm" ] && [ "$h" != "12" ]; then hh24=$((h + 12)); fi
    if [ "$ampm" = "am" ] && [ "$h" = "12" ]; then hh24=0; fi
    reset_at="$(TZ="$tz" date -j -f '%Y-%m-%d %H:%M:%S' "$today $(printf '%02d' "$hh24"):$m:00" '+%s' 2>/dev/null)"
    if [ -n "$reset_at" ] && [ "$reset_at" -le "$(date +%s)" ]; then
      reset_at=$((reset_at + 86400))
    fi
  fi

  [ -z "${reset_at:-}" ] && reset_at="$SENTINEL"

  jq -n --argjson r "$reset_at" --arg raw "$msg" '{reset_at:$r, raw:$raw}' \
    > "$RATELIMIT_FILE.tmp" && mv "$RATELIMIT_FILE.tmp" "$RATELIMIT_FILE" || rm -f "$RATELIMIT_FILE.tmp"
}

# StopFailure is account-level (rate limit) — handle BEFORE the session_id guard,
# since it doesn't need a session id.
if [ "$event" = "StopFailure" ]; then
  err="$(printf '%s' "$input" | jq -r '.error // empty')"
  if [ "$err" = "rate_limit" ]; then
    msg="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty')"
    write_ratelimit "$msg"
  fi
  exit 0
fi

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
    rm -f "$RATELIMIT_FILE"
    write_state "working" ;;
  Notification)
    msg="$(printf '%s' "$input" | jq -r '.message // empty')"
    case "$msg" in
      *permission*|*"needs your permission"*) write_state "permission" ;;
      *)                           write_state "working" ;;
    esac ;;
  Stop)
    rm -f "$RATELIMIT_FILE"
    write_state "done" ;;
  SessionEnd)
    rm -f "$file" ;;
  *)
    : ;;  # SessionStart and anything else: no-op (no file => off)
esac
exit 0
