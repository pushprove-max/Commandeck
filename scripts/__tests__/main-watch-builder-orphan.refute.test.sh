#!/usr/bin/env bash
# A working Builder was nudged and then escalated to main for a call that was
# denied before it ran and so never logged an end.
set -euo pipefail
MAIN_WATCH_TEST_HALF=setup source "$(dirname "$0")/main-watch.test.sh"

: > "$T/sends"; : > "$T/nudges"
O=90000
bts() { jq -rn --argjson t "$1" '$t | todate'; }
bstart() { printf '{"ts":"%s","event":"tool-start","use":"%s","tool":"Bash","kind":"%s","call":"%s"}
' "$(bts "$1")" "$2" "$3" "$2"; }
bend() { printf '{"ts":"%s","event":"tool-end","use":"%s"}
' "$(bts "$1")" "$2"; }
bbatch() { local at=$1; shift; jq -cn --arg ts "$(bts "$at")" '{ts: $ts, event: "batch-end", uses: $ARGS.positional}' --args "$@"; }
bseat wt-orphan term_orphan task_orphan 1000; state term_orphan working
# a is denied beside b, which runs: only the batch's end row names a.
{ bstart "$O" a shell; bstart $((O + 4)) b shell; bend $((O + 5)) b; bbatch $((O + 5)) a b; } > "$T/ws/wt-orphan/.claude/builder-events.jsonl"
# 200 s is past the shell limit; 700 s is past three times it, where a real STUCK wakes main.
for at in 200 250 700; do
  { bstart $((O + at - 20)) "w$at" shell; bend $((O + at - 10)) "w$at"; bbatch $((O + at - 10)) "w$at"; } >> "$T/ws/wt-orphan/.claude/builder-events.jsonl"
  tick $((O + at))
done
[ "$(nudges term_orphan)" = 0 ] || fail "a working Builder was nudged for a denied call: $(cat "$T/nudges")"
[ "$(posts 'Builder wt-orphan')" = 0 ] || fail "a denied call was escalated to main"
# The same pane with a call that really is open still gets its nudge and its wake.
bstart $((O + 800)) real shell >> "$T/ws/wt-orphan/.claude/builder-events.jsonl"
tick $((O + 1000))
[ "$(nudges term_orphan)" = 1 ] || fail "a real stuck call after a denied one got $(nudges term_orphan) nudges"
tick $((O + 1400))
[ "$(posts 'Builder wt-orphan is STUCK')" = 1 ] || fail "a real stuck call past 3x its limit did not wake main"
echo "PASS: main-watch sends nothing for a denied call and still nudges and escalates a real stuck call"
