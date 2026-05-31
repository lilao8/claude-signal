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

# Resolve a 12h clock ("1:10am" lowercase OR "12:50 PM" with space+caps) to the NEXT
# occurrence (unix seconds) in timezone $2 ("" = local). Echoes the timestamp, or nothing.
resolve_clock() {
  local clock="$1" tz="$2" h m ampm hh24 today reset_at
  # normalize: strip spaces, lowercase
  clock="$(printf '%s' "$clock" | tr 'A-Z' 'a-z' | tr -d ' ')"   # "12:50pm"
  h="${clock%%:*}"
  m="$(printf '%s' "$clock" | sed -E 's/^[0-9]{1,2}:([0-9]{2})[ap]m$/\1/')"
  ampm="$(printf '%s' "$clock" | grep -oE '[ap]m')"
  [ -z "$h" ] || [ -z "$m" ] || [ -z "$ampm" ] && return 0
  hh24="$h"
  if [ "$ampm" = "pm" ] && [ "$h" != "12" ]; then hh24=$((h + 12)); fi
  if [ "$ampm" = "am" ] && [ "$h" = "12" ]; then hh24=0; fi
  # When tz is empty use the system local timezone (TZ="" means UTC on macOS, so avoid it).
  if [ -n "$tz" ]; then
    today="$(TZ="$tz" date '+%Y-%m-%d')"
    reset_at="$(TZ="$tz" date -j -f '%Y-%m-%d %H:%M:%S' "$today $(printf '%02d' "$hh24"):$m:00" '+%s' 2>/dev/null)"
  else
    today="$(date '+%Y-%m-%d')"
    reset_at="$(date -j -f '%Y-%m-%d %H:%M:%S' "$today $(printf '%02d' "$hh24"):$m:00" '+%s' 2>/dev/null)"
  fi
  [ -z "$reset_at" ] && return 0
  if [ "$reset_at" -le "$(date +%s)" ]; then
    # +86400 is not DST-aware; on the 2 DST-change days/year reset_at may be off by 1h — acceptable.
    reset_at=$((reset_at + 86400))
  fi
  printf '%s' "$reset_at"
}

# Parse a StopFailure rate-limit message into reset_at (unix seconds), trying the most
# reliable format first. Writes ratelimit.json. Sentinel fallback if nothing parses.
# Formats handled (priority order):
#   C) relative: "reset in 45 mins" / "in 45m"   -> now + N*60   (most reliable; no tz/date ambiguity)
#   A) absolute+tz: "resets 1:10am (America/Toronto)" -> next occurrence in that tz
#   B) absolute, no tz: "Resets at 12:50 PM"     -> next occurrence in LOCAL tz
write_ratelimit() {
  local msg="$1" reset_at mins clock tz
  reset_at=""

  # C) relative countdown: "... in <N> min[s]" or "... in <N>m"
  mins="$(printf '%s' "$msg" | grep -oiE 'in [0-9]+ ?m(in)?' | grep -oE '[0-9]+' | head -1)"
  if [ -n "$mins" ]; then
    reset_at=$(( $(date +%s) + mins * 60 ))
  fi

  # A) absolute clock WITH IANA tz in parens
  if [ -z "$reset_at" ]; then
    clock="$(printf '%s' "$msg" | grep -oiE '[0-9]{1,2}:[0-9]{2} ?[ap]m' | head -1)"
    # Matches single-slash IANA zones (America/Toronto). Rare multi-level zones won't match.
    tz="$(printf '%s' "$msg" | grep -oE '\([A-Za-z]+/[A-Za-z_]+\)' | head -1 | tr -d '()')"
    if [ -n "$clock" ] && [ -n "$tz" ]; then
      reset_at="$(resolve_clock "$clock" "$tz")"
    fi
  fi

  # B) absolute clock with NO tz -> local timezone
  if [ -z "$reset_at" ]; then
    clock="$(printf '%s' "$msg" | grep -oiE '[0-9]{1,2}:[0-9]{2} ?[ap]m' | head -1)"
    if [ -n "$clock" ]; then
      reset_at="$(resolve_clock "$clock" "")"
    fi
  fi

  # fallback
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
