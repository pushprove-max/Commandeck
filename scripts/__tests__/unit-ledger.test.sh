#!/usr/bin/env bash
# unit-ledger.test.sh -- the unit ledger is append-only: a row that is wrong, doubled or made up stays wrong for
# good, and the dashboard's review panels (issues 271 and 272) read nothing else once a unit's worktree is gone.
# What this pins: a merged unit's row holds its round counts and its tokens; a metric with no source is null with
# its gap named, never 0; an append with no merge sha or verdict is refused; the same unit and sha twice is one row;
# an escape is one row per unit and issue, and only an issue number is taken.
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P)
PASS=0 FAIL=0
trap 'rm -rf "$T"' EXIT
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

# Claude's folder is the fake HOME's: the caller's own profile is never read.
unset CLAUDE_CONFIG_DIR COMMANDECK_SEAT_EVENTS "${!UNIT_LEDGER_@}"
export HOME=$T/home COMMANDECK_MAIN=$T/proj COMMANDECK_WORKSPACES=$T/ws COMMANDECK_SCRATCH=$T/scratch
mkdir -p "$HOME" "$T/ws" "$T/proj/.claude/metrics"
git init -q -b main "$T/proj"
GIT_COMMITTER_DATE=1999-01-01T14:00:00Z git -C "$T/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m merged
SHA=$(git -C "$T/proj" rev-parse HEAD)
LEDGER=$T/proj/.claude/metrics/unit-ledger.jsonl
ul() { (cd "$T/proj" && bash "$SOURCE/scripts/unit-ledger.sh" "$@"); }
lines() { [ -f "$LEDGER" ] && grep -c . "$LEDGER" || echo 0; }

# ship-1999-01-01: launched at 10:00, merged at 14:00, its Builder's seat measured, one transcript in its worktree.
U=ship-1999-01-01
printf '%s\n' '{"event":"worker_done","unit":"ship-1999-01-01","role":"builder","launchedAt":"1999-01-01T10:00:00Z","model":"claude-x","tokens":{"input":1000,"cachedInput":800,"output":100}}' \
  '{"event":"worker_done","unit":"ship-1999-01-02","role":"builder","launchedAt":"1999-01-02T10:00:00Z","model":null,"tokens":null,"tokensReason":"no session log: none found"}' \
  > "$T/proj/.claude/metrics/seat-events.jsonl"
P=$HOME/.claude/projects/$(printf '%s' "$T/ws/$U" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$P"
use() { jq -nc --arg t "$1" --arg id "$2" --argjson i "$3" '{type: "assistant", timestamp: $t, message: {id: $id, model: "claude-x", usage: {input_tokens: $i, cache_read_input_tokens: 500, output_tokens: 50}}}'; }
{ use 1999-01-01T10:05:00.000Z m1 200; use 1999-01-01T11:00:00.000Z m2 300; } > "$P/one.jsonl"
outcome=(UNIT_LEDGER_MERGE_SHA="$SHA" UNIT_LEDGER_VERDICT=CONVERGED-GO UNIT_LEDGER_ROUNDS=4 UNIT_LEDGER_GO_ROUNDS=1
  UNIT_LEDGER_NO_GO_ROUNDS=3 UNIT_LEDGER_MERGE_RULE="closing GO")
merged() { (export "${outcome[@]}"; ul "$U" local "$@"); }

ROW=$(merged); RC=$?
check "without --append the row is printed and nothing is written" "0 0 $U" "$RC $(lines) $(jq -r .unit <<<"$ROW")"

OUT=$(merged --append 2>&1); RC=$?
check "three NO-GO rounds and a closing GO: one row with those counts" "0 1 4|1|3|CONVERGED-GO|closing GO|$SHA" \
  "$RC $(lines) $(jq -r '"\(.rounds)|\(.goRounds)|\(.noGoRounds)|\(.verdict)|\(.mergeRule)|\(.mergeSha)"' "$LEDGER")"
check "and its tokens: the unit's transcripts summed, cached input inside input" "1500|1000|100" \
  "$(jq -r '"\(.tokens.input)|\(.tokens.cachedInput)|\(.tokens.output)"' "$LEDGER")"
check "its seat keeps its measured tokens, input plus output" "builder|1100" "$(jq -r '.seats[] | "\(.role)|\(.tokens)"' "$LEDGER")"
check "its wall time runs from the first launch to the merge commit" "1999-01-01T10:00:00Z|1999-01-01T14:00:00Z|4" \
  "$(jq -r '"\(.firstDispatchAt)|\(.mergedAt)|\(.wallHours)"' "$LEDGER")"
check "a metric the plugin has no source for is null and named, never 0" "null|null|true" \
  "$(jq -r '"\(.findings)|\(.fixRounds)|\(.gaps | index("findings") != null and index("fixRounds") != null)"' "$LEDGER")"

OUT=$(merged --append 2>&1); RC=$?
check "the same unit and sha again appends no duplicate, and says so" "0 1 1" "$RC $(lines) $(grep -c "^already recorded unit=$U" <<<"$OUT")"

# ship-1999-01-02: its seat's session log was never found, and it has no transcript at all.
ROW=$(UNIT_LEDGER_MERGE_SHA=$SHA UNIT_LEDGER_VERDICT=CONVERGED-GO ul ship-1999-01-02 local)
check "a missing seat log is a named gap, not 0" "null|null|true|true" \
  "$(jq -r '"\(.tokens)|\(.seats[0].tokens)|\(.gaps | index("tokens") != null)|\(.gaps | index("seatTokens") != null)"' <<<"$ROW")"
check "round counts nobody passed are null and named, never 0" "null|null|true" \
  "$(jq -r '"\(.goRounds)|\(.noGoRounds)|\(.gaps | index("noGoRounds") != null)"' <<<"$ROW")"

ERR=$(ul ship-1999-01-03 local --append 2>&1 >/dev/null); RC=$?
check "no merge sha and no verdict: --append refuses on one line and writes nothing" "1 1 1" \
  "$([ "$RC" != 0 ] && echo 1) $(grep -c . <<<"$ERR") $(lines)"
ERR=$(UNIT_LEDGER_MERGE_SHA=$SHA ul ship-1999-01-03 local --append 2>&1 >/dev/null); RC=$?
check "a merge sha with no verdict refuses too" "1 1" "$([ "$RC" != 0 ] && echo 1) $(lines)"

# Issue 272: an escape is a row of its own; a unit with no merged row is tagged all the same.
ul --escaped "$U" 41 >/dev/null; RC=$?
check "--escaped appends one row" "0 2 $U|[41]" "$RC $(lines) $(tail -1 "$LEDGER" | jq -r '"\(.unit)|\(.escaped | tojson)"')"
ul --escaped "$U" 41 >/dev/null; RC=$?
check "the same unit and issue again adds nothing" "0 2" "$RC $(lines)"
ul --escaped ship-1999-01-04 41 >/dev/null
check "another unit, with no merged row, is tagged with the same issue" "3 ship-1999-01-04" "$(lines) $(tail -1 "$LEDGER" | jq -r .unit)"
ERR=$(ul --escaped "$U" abc 2>&1 >/dev/null); RC=$?
check "a non-number is refused on one line and writes nothing" "1 1 3" "$([ "$RC" != 0 ] && echo 1) $(grep -c . <<<"$ERR") $(lines)"
check "every line is JSON" 0 "$(jq -e . "$LEDGER" >/dev/null 2>&1; echo $?)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
