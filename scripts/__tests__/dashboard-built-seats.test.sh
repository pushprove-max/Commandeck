#!/usr/bin/env bash
# dashboard-built-seats.test.sh -- main's and the relay's own cards, and the answers from the page that wait on
# a failed send or main's picker. The fixture is dashboard-built.test.sh's.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"
NOW=$(date +%s); iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
printf '#!/usr/bin/env bash\ncase "$*" in "terminal list"*) echo %q ;; "orchestration inbox"*) echo %s ;; *) exit 1 ;; esac\n' \
  "$(jq -cn --arg p "$WS/Chief-of-Staff" '{result: {terminals: [{handle: "h-cos", worktreePath: $p}]}}')" \
  "'{\"result\":{\"messages\":[]}}'" > "$BIN/orca-ide"

# Issue 224: main's and the relay's own cards. Main's sessions are the main checkout's projects folder (the one a
# Builder's cost leaves out), the relay's the Chief-of-Staff worktree's. Haiku rows of 100,000 tokens are $0.01 each.
# Main ran one request today and one 3 days ago; it restarted twice today, a minute apart. A restart of a session
# that is not main's, and a failed restart, count for nothing. The relay is no restarting seat and has no clear line.
seatf() { echo "$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$1")"; }
mkdir -p "$(seatf "$MAIN")" "$(seatf "$WS/Chief-of-Staff")" "$HOME/.claude/checkpoints"
hrow() { jq -cn --arg t "$(iso "$2")" --arg id "$1" '{type: "assistant", timestamp: $t, requestId: $id,
  message: {id: $id, model: "claude-haiku-5-5", usage: {input_tokens: 100000, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0}}}'; }
{ hrow m0 $((NOW - 3 * 86400)); hrow m1 $((NOW - 60)); } > "$(seatf "$MAIN")/m1.jsonl"
hrow c1 $((NOW - 30)) > "$(seatf "$WS/Chief-of-Staff")/c1.jsonl"
lt() { date -d "@$1" +%FT%T; }
CPD=$HOME/.claude/checkpoints
printf '%s\n' "$(lt $((NOW - 120))) restart: new pane h2 resumed from $CPD/m1.md; closing h1" \
  "$(lt $((NOW - 90))) restart: terminal create failed; old pane h2 left up, next stop retries" \
  "$(lt $((NOW - 80))) restart: new pane h9 resumed from $CPD/other.md; closing h8" \
  "$(lt $((NOW - 60))) restart: new pane h3 resumed from $CPD/m1.md; closing h2" > "$CPD/clear-hook.log"
echo '{"builder": {"clearLine": "160000"}, "chiefOfStaff": {"name": "Relay"}}' > "$MAIN/.claude/commandeck.json"
dash
check "main's card: context against its line, today's tokens and cost, the 7-day daily average, two restarts a minute apart" \
  '[100000,200000,100000,0.01,28571,0.0029,2,60]' \
  "$(jq -c 'first(.[]) | .seats.main | [.context, .line, .today.tokens, .today.usd, .avg7.tokens, .avg7.usd, .restarts, .restartGapSec]' "$T/out/run/project.json" 2>&1)"
check "main's restart times are today's two" 2 "$(jq -c 'first(.[]) | .seats.main.restartTimes | length' "$T/out/run/project.json" 2>&1)"
check "the relay's card: its own session today, no line, no restarts" '[100000,null,100000,0.01,0,null]' \
  "$(jq -c 'first(.[]) | .seats.relay | [.context, .line, .today.tokens, .today.usd, .restarts, .restartGapSec]' "$T/out/run/project.json" 2>&1)"
echo '{"builder": {"clearLine": "160000"}}' > "$MAIN/.claude/commandeck.json"
# Issue 240: an answer from the page whose send failed is kept by the host, and listed on this project's card only.
jq -cn --arg m "$MAIN" '[{main: $m, id: "ship-1999-01-01", to: "relay", args: []}, {main: "/elsewhere", id: "x-1999-01-01", to: "main", args: []}]' > "$T/out/answer-retry.json"
dash
check "an answer whose send failed is listed on its own project's card" '[{"id":"ship-1999-01-01","to":"relay"}]' \
  "$(jq -c 'first(.[]) | .needsOwner.unsent' "$T/out/run/project.json" 2>&1)"
check "and none is said to wait on main's picker with no record" '[]' "$(jq -c 'first(.[]) | .needsOwner.picker' "$T/out/run/project.json" 2>&1)"
# An answer delivered while main's own picker was open waits on that picker: the host records it, and this
# project's card names it until a delivery to main finds no picker.
jq -cn --arg m "$MAIN" '[{main: $m, id: "ship-1999-01-01"}, {main: "/elsewhere", id: "x-1999-01-01"}]' > "$T/out/answer-picker.json"
dash
check "an answer waiting on main's open picker is named on its own project's card" '["ship-1999-01-01"]' \
  "$(jq -c 'first(.[]) | .needsOwner.picker' "$T/out/run/project.json" 2>&1)"
check "with no relay configured there is no relay card" '[true,false]' \
  "$(jq -c 'first(.[]) | [(.seats.main | type == "object"), (.seats | has("relay"))]' "$T/out/run/project.json" 2>&1)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
