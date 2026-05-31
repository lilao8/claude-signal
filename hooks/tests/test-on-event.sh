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

# Missing session_id -> no crash, no file written
before="$(find "$TMP/sessions" -type f 2>/dev/null | wc -l | tr -d ' ')"
echo '{"hook_event_name":"Stop"}' | bash "$SCRIPT"; rc=$?
after="$(find "$TMP/sessions" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$rc" -eq 0 ] && [ "$before" = "$after" ]; then
  echo "ok  - missing session_id handled (no file, exit 0)"
else
  echo "FAIL - missing session_id: exit=$rc files before=$before after=$after"; fail=1
fi

# ---- usage-limit (StopFailure / rate_limit) ----

# rate_limit StopFailure writes ratelimit.json with a future reset_at + preserved raw
rm -f "$TMP/ratelimit.json"
echo '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit","last_assistant_message":"You'"'"'ve hit your session limit · resets 1:10am (America/Toronto)"}' | bash "$SCRIPT"
if [ -f "$TMP/ratelimit.json" ]; then
  reset_at=$(jq -r '.reset_at' "$TMP/ratelimit.json")
  raw=$(jq -r '.raw' "$TMP/ratelimit.json")
  nowts=$(date +%s)
  if [ "$reset_at" -gt "$nowts" ]; then echo "ok  - rate_limit writes future reset_at"; else echo "FAIL - reset_at not future: $reset_at vs $nowts"; fail=1; fi
  case "$raw" in *"1:10am"*) echo "ok  - raw preserved" ;; *) echo "FAIL - raw not preserved: $raw"; fail=1 ;; esac
else
  echo "FAIL - ratelimit.json not written"; fail=1
fi

# non-rate_limit StopFailure does NOT write ratelimit.json
rm -f "$TMP/ratelimit.json"
echo '{"hook_event_name":"StopFailure","session_id":"s1","error":"max_output_tokens","last_assistant_message":"too long"}' | bash "$SCRIPT"
if [ -f "$TMP/ratelimit.json" ]; then echo "FAIL - non-rate_limit should not write ratelimit.json"; fail=1; else echo "ok  - non-rate_limit ignored"; fi

# normal activity deletes an existing ratelimit.json (extinguish ②)
echo '{"reset_at":99999999999,"raw":"x"}' > "$TMP/ratelimit.json"
echo '{"hook_event_name":"UserPromptSubmit","session_id":"s1"}' | bash "$SCRIPT"
if [ -f "$TMP/ratelimit.json" ]; then echo "FAIL - activity should delete ratelimit.json"; fail=1; else echo "ok  - activity clears ratelimit"; fi

# Stop also deletes ratelimit.json (extinguish ②)
echo '{"reset_at":99999999999,"raw":"x"}' > "$TMP/ratelimit.json"
echo '{"hook_event_name":"Stop","session_id":"s1"}' | bash "$SCRIPT"
if [ -f "$TMP/ratelimit.json" ]; then echo "FAIL - Stop should delete ratelimit.json"; fail=1; else echo "ok  - Stop clears ratelimit"; fi

# fallback: rate_limit with unparseable message uses sentinel reset_at
rm -f "$TMP/ratelimit.json"
echo '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit","last_assistant_message":"limit reached, try later"}' | bash "$SCRIPT"
if [ -f "$TMP/ratelimit.json" ]; then
  reset_at=$(jq -r '.reset_at' "$TMP/ratelimit.json")
  if [ "$reset_at" -ge 99999999999 ]; then echo "ok  - unparseable rate_limit uses sentinel"; else echo "FAIL - expected sentinel, got $reset_at"; fail=1; fi
else
  echo "FAIL - fallback should still write ratelimit.json"; fail=1
fi

# 12:00am (midnight) edge case — must map to 00:00, not 12:00
rm -f "$TMP/ratelimit.json"
echo '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit","last_assistant_message":"resets 12:00am (America/Toronto)"}' | bash "$SCRIPT"
reset_at=$(jq -r '.reset_at' "$TMP/ratelimit.json")
# the resolved instant, formatted as hour in Toronto, must be 00
hh=$(TZ=America/Toronto date -r "$reset_at" '+%H')
check "12:00am maps to 00:xx Toronto" "00" "$hh"

# 12:00pm (noon) edge case — must map to 12:00
rm -f "$TMP/ratelimit.json"
echo '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit","last_assistant_message":"resets 12:00pm (America/Toronto)"}' | bash "$SCRIPT"
reset_at=$(jq -r '.reset_at' "$TMP/ratelimit.json")
hh=$(TZ=America/Toronto date -r "$reset_at" '+%H')
check "12:00pm maps to 12:xx Toronto" "12" "$hh"

# ---- multi-format reset parsing ----

# Format A still works: "resets 1:10am (America/Toronto)"
rm -f "$TMP/ratelimit.json"
echo '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit","last_assistant_message":"resets 1:10am (America/Toronto)"}' | bash "$SCRIPT"
hh=$(TZ=America/Toronto date -r "$(jq -r .reset_at "$TMP/ratelimit.json")" '+%H:%M')
check "format A (tz) -> 01:10 Toronto" "01:10" "$hh"

# Format B: "Resets at 12:50 PM" (no tz) -> local time 12:50
rm -f "$TMP/ratelimit.json"
echo '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit","last_assistant_message":"Usage limit reached · Resets at 12:50 PM"}' | bash "$SCRIPT"
hh=$(date -r "$(jq -r .reset_at "$TMP/ratelimit.json")" '+%H:%M')
check "format B (no tz) -> 12:50 local" "12:50" "$hh"

# Format C: "reset in 45 mins" -> now + 45*60 (allow ±2s slack)
rm -f "$TMP/ratelimit.json"
nowts=$(date +%s)
echo '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit","last_assistant_message":"Usage limit reached, reset in 45 mins"}' | bash "$SCRIPT"
got=$(jq -r .reset_at "$TMP/ratelimit.json")
exp=$(( nowts + 45*60 ))
diff=$(( got - exp )); diff=${diff#-}
if [ "$diff" -le 2 ]; then echo "ok  - format C (relative) -> now+45m"; else echo "FAIL - format C: got $got exp ~$exp"; fail=1; fi

# Format C variant: "in 30m"
rm -f "$TMP/ratelimit.json"
nowts=$(date +%s)
echo '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit","last_assistant_message":"try again in 30m"}' | bash "$SCRIPT"
got=$(jq -r .reset_at "$TMP/ratelimit.json")
exp=$(( nowts + 30*60 ))
diff=$(( got - exp )); diff=${diff#-}
if [ "$diff" -le 2 ]; then echo "ok  - format C variant (30m)"; else echo "FAIL - format C variant: got $got exp ~$exp"; fail=1; fi

# Unparseable still -> sentinel
rm -f "$TMP/ratelimit.json"
echo '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit","last_assistant_message":"limit reached, sorry"}' | bash "$SCRIPT"
got=$(jq -r .reset_at "$TMP/ratelimit.json")
[ "$got" -ge 99999999999 ] && echo "ok  - unparseable -> sentinel" || { echo "FAIL - sentinel: got $got"; fail=1; }

rm -rf "$TMP"
exit $fail
