#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOOK="$ROOT/hooks/no-poll-loops.sh"
BOX=$(mktemp -d)
trap 'rm -rf -- "$BOX"' EXIT
git -C "$BOX" init -q
PASS=0; FAIL=0

refused() { # label, command, run_in_background
  local payload rc
  payload=$(jq -cn --arg cmd "$2" --argjson bg "$3" '{tool_name:"Bash",tool_input:{command:$cmd,run_in_background:$bg}}')
  (cd "$BOX" && printf '%s\n' "$payload" | "$HOOK" >/dev/null 2>&1)
  rc=$?
  if [ "$rc" -eq 2 ]; then PASS=$((PASS+1)); echo "ok   $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 should be refused with rc=2, got rc=$rc"; fi
}

refused "multiline inbox-wait loop" $'while true\ndo\n  bash scripts/orca-wait.sh\ndone' true
# A loop is one command whatever its line breaks; grep reading line by line saw
# no line with both the loop and the sleep.
refused "multiline sleep loop" $'while true; do\n  sleep 60\n  gh pr view 1\ndone' false
refused "multiline sleep loop with do on its own line" $'while true\ndo\n  gh pr view 1\n  sleep 60\ndone' false

refused "a sleep behind a command wrapper" $'while true; do\n  date\n  command sleep 60\ndone' false
refused "a sleep behind timeout and an assignment" 'while true; do X=1 timeout 70 sleep 60; done' false
refused "nested loop polling after an inner loop" $'while true; do\n  for f in a b; do echo "$f"; done\n  sleep 60\ndone' false

# One sleep after a finished loop runs once; it is not a poll.
passes() { # label, command
  local payload rc
  payload=$(jq -cn --arg cmd "$2" '{tool_name:"Bash",tool_input:{command:$cmd}}')
  (cd "$BOX" && printf '%s\n' "$payload" | "$HOOK" >/dev/null 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "ok   $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 should pass, got rc=$rc"; fi
}
passes "a sleep after a finished loop" $'for f in a b; do echo "$f"; done\nsleep 1\necho finished'
passes "a sleep after a finished loop, then echo done" $'for f in a b; do echo "$f"; done\nsleep 1\necho done'
passes "one sleep between two finite loops" $'for a in 1; do echo; done\nsleep 1\nfor b in 2; do echo; done'

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
