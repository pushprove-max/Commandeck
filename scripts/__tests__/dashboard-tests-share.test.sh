#!/usr/bin/env bash
# covers: scripts/dashboard_limit.py scripts/dashboard.sh
# dashboard-tests-share.test.sh -- issue 292: the Tests card's share of the Builders' clock that went to tests: test
# seconds today run in a Builder worktree over the span of the Builder sessions today. The fixture is dashboard-built.test.sh's.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"
MID=$(date -d 'today 00:00' +%s)
# The collect's clock is two hours into the day whatever the real time, so the rows below are always today and past.
DNOW=$((MID + 7200)); E=$((MID + 3000))
BW=$WS/bw; mkdir -p "$BW/.claude" && touch "$BW/.git" && echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$BW/.claude/settings.local.json"
BF=$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$BW"); mkdir -p "$BF"
tl() { jq -cn --arg ts "$(date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.000Z)" --arg cwd "$BW" --argjson c "$2" --arg ty "$3" '{type:$ty,timestamp:$ts,cwd:$cwd,message:{content:[$c]}}'; }
# The session starts at E, runs one 60 s test command, and last wrote 600 s after it began.
{ tl "$E" '{"type":"text","text":"start"}' assistant
  tl $((E + 10)) '{"type":"tool_use","name":"Bash","id":"a1","input":{"command":"bash scripts/run-shell-tests.sh x.test.sh"}}' assistant
  tl $((E + 70)) '{"type":"tool_result","tool_use_id":"a1","content":"1 passed, 0 failed, 0 parked"}' user
  tl $((E + 600)) '{"type":"text","text":"done"}' assistant; } > "$BF/s.jsonl"
dash
q() { jq -c "first(.[]) | .tests | $1" "$T/out/run/project.json" 2>&1; }
check "a Builder worktree's 60 s of tests in a 600 s Builder span give builderShare 0.1, and 60 s of test time today" '[0.1,60]' "$(q '[.builderShare, .testSecToday]')"
echo '{}' > "$BW/.claude/settings.local.json"; dash
check "no Builder session today gives builderShare null; the test time stays" '[null,60]' "$(q '[.builderShare, .testSecToday]')"
# A second session runs a test from 600 s before midnight to 600 s after, its last line: only today's 600 s are today's,
# on the clock (600 + 600 s) and in the tests (60 + 600 s). Counted whole, the share would pass 100%.
echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$BW/.claude/settings.local.json"
{ tl $((MID - 600)) '{"type":"tool_use","name":"Bash","id":"b1","input":{"command":"npm test"}}' assistant
  tl $((MID + 600)) '{"type":"tool_result","tool_use_id":"b1","content":"1 passed, 0 failed"}' user; } > "$BF/s2.jsonl"
dash
check "a test across midnight counts its seconds after midnight only: builderShare 0.55, 660 s of test time today" '[0.55,660]' "$(q '[.builderShare, .testSecToday]')"
# The first session again, its timestamps without milliseconds: the Builder clock still reads them.
rm -f "$BF/s2.jsonl" "$T/out/cache/test-runs.json"
sed 's/\.000Z"/Z"/' "$BF/s.jsonl" > "$BF/s.tmp" && mv "$BF/s.tmp" "$BF/s.jsonl"
dash
check "timestamps with no milliseconds give the same builderShare 0.1 and 60 s" '[0.1,60]' "$(q '[.builderShare, .testSecToday]')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
