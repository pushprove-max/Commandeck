#!/usr/bin/env bash
# covers: scripts/dashboard_limit.py scripts/dashboard.sh
# dashboard-built-seat-figures.test.sh -- issue 292: the figures beside main's and the relay's cards: working now, what a
# restart costs to rebuild, the last twelve hours in tokens, the week's sessions and tokens, and the relay's sub-agent
# runs today. Haiku rows of 100,000 tokens are $0.01 each. The fixture is dashboard-built.test.sh's.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"
NOW=$(date +%s); iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
MID=$(date -d 'today 00:00' +%s)
printf '#!/usr/bin/env bash\ncase "$*" in "terminal list"*) echo %q ;; "orchestration inbox"*) echo %s ;; *) exit 1 ;; esac\n' \
  "$(jq -cn --arg p "$WS/Chief-of-Staff" '{result: {terminals: [{handle: "h-cos", worktreePath: $p}]}}')" "'{\"result\":{\"messages\":[]}}'" > "$BIN/orca-ide"
seatf() { echo "$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$1")"; }
M=$(seatf "$MAIN"); R=$(seatf "$WS/Chief-of-Staff"); mkdir -p "$M/s2/subagents" "$R/r1/subagents"
hrow() { jq -cn --arg t "$(iso "$2")" --arg id "$1" '{type: "assistant", timestamp: $t, requestId: $id,
  message: {id: $id, model: "claude-haiku-5-5", usage: {input_tokens: 100000, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0}}}'; }
# Main: session s1 began 3 days ago and ran a minute ago; session s2 began earlier today (a restart), and a sub-agent of
# s2 ran a few seconds ago. The relay: one session r1 with two sub-agent runs today.
E=$((MID + (NOW - MID) / 3))
{ hrow a $((NOW - 3 * 86400)); hrow b $((NOW - 60)); } > "$M/s1.jsonl"
hrow c "$E" > "$M/s2.jsonl"; hrow d $((NOW - 20)) > "$M/s2/subagents/a.jsonl"
hrow r $((NOW - 30)) > "$R/r1.jsonl"; hrow x $((NOW - 20)) > "$R/r1/subagents/x.jsonl"; hrow y $((NOW - 10)) > "$R/r1/subagents/y.jsonl"
echo '{"builder": {"clearLine": "160000"}, "chiefOfStaff": {"name": "Relay"}}' > "$MAIN/.claude/commandeck.json"
dash
bins() { jq -nc --argjson n "$NOW" --argjson ts "$1" '[range(0; 12) as $i | [$ts[] | select(. >= $n - (12 - $i) * 3600 and . < $n - (11 - $i) * 3600)] | length * 100000]'; }
seat() { jq -c "first(.[]) | .seats.$1 | $2" "$T/out/run/project.json" 2>&1; }
check "main: working now, the first call of a session begun today as the rebuild cost, and a week of two sessions" '[true,0.01,2,0,400000,0,0]' \
  "$(seat main '[.live, .rebuildUsd, .week.sessions, .week.unmeasuredSessions, .week.input, .week.cachedInput, .week.output]')"
check "main: twelve hourly token sums, the last hour holding the newest calls" "$(bins "[$((NOW - 60)), $E, $((NOW - 20))]")" "$(seat main .hourly)"
check "the relay: working now, twelve hourly sums, and two sub-agent runs today at \$0.02" "[true,$(bins "[$((NOW - 30)), $((NOW - 20)), $((NOW - 10))]"),{\"count\":2,\"usd\":0.02},1]" \
  "$(seat relay '[.live, .hourly, .sideRuns, .week.sessions]')"
# s2's transcript deleted, its rows still cached: when it began cannot be read, so the rebuild cost is unknown, not $0.01.
mv "$M/s2.jsonl" "$T/s2.jsonl"; dash; mv "$T/s2.jsonl" "$M/s2.jsonl"
check "a session begun today whose transcript is gone leaves the rebuild cost unknown" 'null' "$(seat main .rebuildUsd)"
# The request cache keeps a deleted transcript's rows, so the next collect starts from none.
rm -f "$M"/*.jsonl "$M"/s2/subagents/*.jsonl "$T"/out/cache/limit-requests.json; hrow old $((NOW - 3 * 3600 * 24)) > "$M/s1.jsonl"; dash
check "a main with no call in 10 minutes is not working now, and no session begun today has no rebuild cost" '[false,null]' "$(seat main '[.live, .rebuildUsd]')"
# A session begun nine days ago, before the requests read, and resumed today: its first call today is no restart.
{ hrow o9 $((NOW - 9 * 86400)); hrow t9 $((NOW - 120)); } > "$M/s3.jsonl"; dash
check "a session begun before the week and resumed today has no rebuild cost" 'null' "$(seat main .rebuildUsd)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
