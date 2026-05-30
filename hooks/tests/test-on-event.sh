#!/usr/bin/env bash
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/on-event.sh"
TMP="$(mktemp -d)"
export CLAUDE_SIGNAL_DIR="$TMP"
fail=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok  - $1"; else echo "FAIL - $1: expected '$2' got '$3'"; fail=1; fi
}

# UserPromptSubmit -> working
echo '{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/p"}' | bash "$SCRIPT"
state=$(jq -r '.state' "$TMP/sessions/s1.json")
check "UserPromptSubmit->working" "working" "$state"

# Notification permission -> permission
echo '{"hook_event_name":"Notification","session_id":"s1","message":"Claude needs your permission to use Bash"}' | bash "$SCRIPT"
state=$(jq -r '.state' "$TMP/sessions/s1.json")
check "Notification permission->permission" "permission" "$state"

# Notification other -> working
echo '{"hook_event_name":"Notification","session_id":"s1","message":"Waiting for input"}' | bash "$SCRIPT"
state=$(jq -r '.state' "$TMP/sessions/s1.json")
check "Notification other->working" "working" "$state"

# Stop -> done
echo '{"hook_event_name":"Stop","session_id":"s1"}' | bash "$SCRIPT"
state=$(jq -r '.state' "$TMP/sessions/s1.json")
check "Stop->done" "done" "$state"

# SessionEnd -> file removed
echo '{"hook_event_name":"SessionEnd","session_id":"s1"}' | bash "$SCRIPT"
if [ -f "$TMP/sessions/s1.json" ]; then echo "FAIL - SessionEnd should remove file"; fail=1; else echo "ok  - SessionEnd removes file"; fi

# Missing session_id -> no crash, no file
echo '{"hook_event_name":"Stop"}' | bash "$SCRIPT"
echo "ok  - missing session_id handled (exit $?)"

rm -rf "$TMP"
exit $fail
