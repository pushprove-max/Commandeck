#!/usr/bin/env bash
# dashboard-built-seats.test.sh -- main's and the relay's own cards, and the answers from the page that wait on
# a failed send or main's picker; the collector reading the profile main recorded (issue 291) and only what grew
# since the last collect (issue 299). The fixture is dashboard-built.test.sh's.
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
# Issue 295: each with its key, state, reason, tries, first try and last error, as the host keeps them.
jq -cn --arg m "$MAIN" '[{main: $m, id: "ship-1999-01-01", to: "relay", args: [], key: "k1", state: "gave-up", reason: "its main folder /x is gone",
    tries: 2, firstAt: "1999-01-01T00:00:00Z", lastExit: 1, lastError: "boom"}, {main: "/elsewhere", id: "x-1999-01-01", to: "main", args: []}]' > "$T/out/answer-retry.json"
dash
check "an answer whose send failed is listed on its own project's card, with why and how often it failed" \
  '[{"id":"ship-1999-01-01","to":"relay","key":"k1","state":"gave-up","reason":"its main folder /x is gone","tries":2,"firstAt":"1999-01-01T00:00:00Z","lastError":"boom"}]' \
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

# Issue 291: a main run under another Claude config folder records it, and the collector reads that folder's
# transcripts and task lists, never the home folder's.
SCR=$(cd "$MAIN" && env -u COMMANDECK_SCRATCH COMMANDECK_MAIN="$MAIN" bash -c '. "$0" && echo "$PP_SCRATCH"' "$SOURCE/scripts/paths.sh"); mkdir -p "$SCR"
mkdir -p "$T/profile"; echo "$T/profile" > "$SCR/claude-config-dir"
dash
check "issue 291: the collector reads the config folder main recorded" "not-measured no main session task list under $T/profile/tasks" \
  "$(jq -r 'first(.[]).sources.todos | "\(.status) \(.error)"' "$T/out/run/project.json" 2>&1)"
rm -f "$SCR/claude-config-dir"

# Issue 299: a collect reads only what changed since the last one, and shows what a collect with no reading state
# shows. Between two collects a minute apart, a Builder's session, main's transcript and the hook fire log grow; the
# second collect equals one run on the same files at the same time from the first's cache without that state.
HL=$HOME/.claude/hook-fire-log; mkdir -p "$HL"
blk() { jq -cn --arg t "$(iso "$1")" --arg s "$2" '{timestamp: $t, hook: "h", decision: "block", session_id: "s1", agent: "claude", event: "PreToolUse", use: "u\($s)", call: "c\($s)", summary: $s}'; }
blk $((NOW - 300)) 1 > "$HL/demo.$(date -u +%F).jsonl"
BS=$(seatf "$WS/u-verdicts")/s.jsonl
W=$(date +%s); DNOW=$W dash; cp -a "$T/out/cache" "$T/cache-1"
blk $((NOW - 200)) 2 >> "$HL/demo.$(date -u +%F).jsonl"
hrow m2 $((NOW - 20)) >> "$(seatf "$MAIN")/m1.jsonl"
printf '%s\n' '{"type":"user","toolUseResult":{"backgroundTaskId":"b1"}}' \
  '{"type":"assistant","message":{"id":"m9","usage":{"cache_read_input_tokens":160000,"input_tokens":20,"cache_creation_input_tokens":5,"cache_creation":{"ephemeral_5m_input_tokens":5}}}}' >> "$BS"
# The blocks' hourly mean is over the hours since the day file's start by the wall clock: a sample time.
DNOW=$((W + 60)) dash; warm=$(jq -S 'first(.[]) | del(.guardBlocks.perHour)' "$T/out/run/project.json" 2>&1)
rm -rf "$T/out/cache"; mv "$T/cache-1" "$T/out/cache"
rm -f "$T/out/cache"/{limit-requests,codex-requests,codex-requests-review}.json "$T/out/cache/demo"/{guard-blocks,session-summary}.json
DNOW=$((W + 60)) dash; cold=$(jq -S 'first(.[]) | del(.guardBlocks.perHour)' "$T/out/run/project.json" 2>&1)
check "issue 299: the warm collect read what grew: two blocks, main's new request, the Builder's new context" '[2,200000,160025]' \
  "$(jq -c '[.guardBlocks.blocks, .seats.main.today.tokens, (.units.inFlight[] | select(.unit == "u-verdicts") | .builder.context)]' <<<"$warm")"
check "issue 299: a warm collect shows what one with no reading state shows" "$cold" "$warm"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
