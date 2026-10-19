#!/usr/bin/env bash
# unit-cost.sh is the one measure of what a unit's worker panes cost. A reply
# that comes after the session's cache has lapsed rewrites the whole cache, so
# it is counted as cold; a helper that repeats an earlier helper's search, runs
# past 20 tool calls or answers in more than 15 lines costs the parent session
# its tokens again (issue 203). What this pins: a 400 s gap whose reply writes
# more than it reads is cold, a 200 s gap is not, and the helper line counts
# the overruns and a shared rg pattern; the TOTAL line sums both.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
D=$T/home/.claude/projects/$(printf %s "$T/ws" | tr -c 'A-Za-z0-9' '-')-u; mkdir -p "$D"
user() { printf '{"type":"user","timestamp":"2026-10-10T%s.000Z","message":{"content":"go"}}\n' "$1"; }
# reply <time> <message id> <content> <usage>
reply() { jq -cn --arg t "2026-10-10T$1.000Z" --arg id "$2" --argjson c "$3" --argjson u "$4" \
  '{type: "assistant", timestamp: $t, message: {id: $id, content: $c, usage: $u}}'; }
TXT='[{"type":"text","text":"done"}]'
WRITE='{"cache_creation_input_tokens":5000,"cache_read_input_tokens":1000}'
# session <name> <seconds between the first and second request>: the second reply writes more than it reads.
session() { { user 12:00:00; reply 12:00:01 m1 "$TXT" '{"cache_creation_input_tokens":1000}'
  user "12:0$(($2 / 60)):$(printf %02d $(($2 % 60)))"; reply 12:09:59 m2 "$TXT" "$WRITE"; } > "$D/$1.jsonl"; }
session gap400ss 400
session gap200ss 200
# Two helpers of gap400ss: the first makes 21 tool calls, one an rg the second repeats; the second answers in 16 lines.
H=$D/gap400ss/subagents; mkdir -p "$H"
RG='{"type":"tool_use","name":"Bash","input":{"command":"rg -n \"needle\" src"}}'
{ user 12:01:00; reply 12:01:01 a1 "$(jq -cn --argjson rg "$RG" '[range(20) | {type: "tool_use", name: "Read", input: {file_path: "/f\(.)"}}] + [$rg]')" '{}'
  reply 12:01:02 a2 "$TXT" '{}'; } > "$H/agent-a.jsonl"
{ user 12:02:00; reply 12:02:01 b1 "[$RG]" '{}'
  reply 12:02:02 b2 "$(jq -cn '[{type: "text", text: ([range(16) | "line \(.)"] | join("\n"))}]')" '{}'; } > "$H/agent-b.jsonl"

OUT=$(cd "$REAL" && HOME=$T/home COMMANDECK_WORKSPACES=$T/ws bash scripts/unit-cost.sh u '2000-01-01 00:00' 2>&1)
col() { awk -v s="$1" -v c="$2" '$1 == s { print $c }' <<<"$OUT"; }
check "a reply 400 s after the one before, writing more than it reads, is cold" "1 5" "$(col gap400ss 14) $(col gap400ss 15)"
check "a reply 200 s after the one before is not" "0 0" "$(col gap200ss 14) $(col gap200ss 15)"
HL=$(grep -A1 '^gap400ss' <<<"$OUT" | tail -1 | xargs)
check "two helpers sharing one rg pattern: one repeat" "repeats 1" "$(grep -o 'repeats [0-9]*' <<<"$HL")"
check "a helper with 21 tool calls is over 20" "over20 1" "$(grep -o 'over20 [0-9]*' <<<"$HL")"
check "a 16-line answer is over 15" "over15 1" "$(grep -o 'over15 [0-9]*' <<<"$HL")"
check "a session with no helpers prints no helper line" "" "$(grep -A1 '^gap200ss' <<<"$OUT" | tail -n +2 | grep helpers)"
check "the TOTAL line sums both" "1 cold rewrites (5k tokens), 2 helpers (1 over 20 calls, 1 answers over 15 lines, 1 repeated searches)" \
  "$(grep '^TOTAL' <<<"$OUT" | grep -o '[0-9]* cold rewrites.*')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
