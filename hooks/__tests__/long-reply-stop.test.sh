#!/usr/bin/env bash
# Self-test for long-reply-stop.sh (issue 552): a closing reply past 3,000 characters that names no file is sent back
# once, to be written to a file and answered with the path and a short summary. A long reply costs every later turn
# its replay; a reply that already points at a file is the shape being asked for.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/long-reply-stop.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi; }
unset COMMANDECK_REVIEWER
# stop <reply> [stop_hook_active] -> held or passed; the payload is built by jq so the reply is data
stop() {
  local rc
  jq -cn --arg m "$1" --argjson a "${2:-false}" '{hook_event_name: "Stop", stop_hook_active: $a, last_assistant_message: $m}' \
    | bash "$HOOK" >/dev/null 2>&1; rc=$?
  case "$rc" in 2) echo held ;; 0) echo passed ;; *) echo "rc=$rc" ;; esac
}
words() { local s='' i; for ((i = 0; i < $1; i++)); do s+='word '; done; printf '%s' "$s"; }
LONG=$(words 800)   # 4,000 characters, no path
check "a reply past 3,000 characters naming no file is sent back once" held "$(stop "$LONG")"
check "a short reply passes" passed "$(stop "done, all tests pass")"
check "a long reply naming a path passes" passed "$(stop "$LONG see .claude/briefs/report.md")"
check "the hook's own second stop passes" passed "$(stop "$LONG" true)"
# The bounds: exactly 3,000 characters is not past it, 3,001 is. A slash with no extension is not a path.
check "exactly 3,000 characters passes" passed "$(stop "$(printf '%3000s' '' | tr ' ' x)")"
check "3,001 characters is held" held "$(stop "$(printf '%3001s' '' | tr ' ' x)")"
check "a slash word with no extension is not a path" held "$(stop "$LONG and/or")"
# Bad input passes: an absent message, junk JSON, an empty reply.
check "an absent message passes" passed "$(echo '{"hook_event_name":"Stop"}' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && echo passed || echo held)"
check "junk JSON passes" passed "$(echo 'not json' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && echo passed || echo held)"
check "an empty reply passes" passed "$(stop "")"
check "a reviewer pane passes" passed "$(COMMANDECK_REVIEWER=1 stop "$LONG")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
