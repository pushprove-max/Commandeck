#!/usr/bin/env bash
# dashboard-builders-helper-wait.test.sh -- a helper can log a stop and go on
# working: in real Builder logs one Explore helper logs subagent-stop, then a
# tool call of its own, then a second stop (#41). Most other stop rows carry an
# id that never logged a start and has no transcript: not a helper. What this
# pins: a helper is running until a stop that none of its calls follows, so
# the card does not read a waiting Builder as idle, and the stop the card
# shows is the finishing one.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
NOW=1790000000
iso() { date -u -d "@$((NOW - $1))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$((NOW - $1))" +%Y-%m-%dT%H:%M:%SZ; }
card() { jq -cs --argjson now "$NOW" -f "$ROOT/scripts/dashboard_builders.jq" | jq -c "$1"; }
# The row shapes builder-event-log.sh writes, as in the sample logs (ids and paths replaced).
start() { printf '{"ts":"%s","event":"subagent-start","agent_id":"a1","type":"Explore"}\n' "$(iso "$1")"; }
stop() { printf '{"ts":"%s","event":"subagent-stop","agent_id":"a1","type":"Explore","model":"claude-haiku-5-5","tokens":{"input":%s,"cachedInput":1,"output":30}}\n' "$(iso "$1")" "$2"; }
orphan() { printf '{"ts":"%s","event":"subagent-stop","agent_id":"o%s","type":null,"model":null,"tokens":null,"reason":"no file at /tmp/agent-o%s.jsonl"}\n' "$(iso "$1")" "$1" "$1"; }
call() { printf '{"ts":"%s","event":"tool-start","use":"u%s","agent":"a1","tool":"Grep","kind":"tool","call":"%s","timeoutSec":null}\n{"ts":"%s","event":"tool-end","use":"u%s","ok":true}\n' "$(iso "$1")" "$1" "$1" "$(iso "$1")" "$1"; }
paused() { start 900; call 890; orphan 880; stop 870 100; call 860; }
running='[.waiting[] | select(.kind == "subagent") | .what]'

check "a helper that logged a stop and then a call of its own is running" '["Explore"]' "$(paused | card "$running")"
check "so the Builder waiting on it is not quiet" 0 "$(paused | card '[.signals[] | select(.kind == "quiet")] | length')"
check "and its step has no stop yet" '[null]' "$(paused | card '[.steps[] | .stop]')"
check "after a stop no call follows, it is done" '[]' "$({ paused; stop 850 200; } | card "$running")"
check "its step shows the finishing stop and its tokens" "[\"$(iso 850)\",200]" "$({ paused; stop 850 200; } | card '[.steps[0] | .stop, .tokens.input]')"
check "a stop row with no start is no helper" '[]' "$({ orphan 880; orphan 870; } | card "$running")"
check "a helper with one stop and nothing after is done, as before" '[]' "$({ start 900; call 890; stop 870 100; } | card "$running")"
# A stop the helper went on from still ends the calls it began before it: one cut off there logs no end.
open() { printf '{"ts":"%s","event":"tool-start","use":"o%s","agent":"a1","tool":"Bash","kind":"shell","call":"o","timeoutSec":null}\n' "$(iso "$1")" "$1"; }
check "a call cut off at a stop the helper went on from is not pending" '[[],[]]' \
  "$({ start 900; open 890; stop 880 100; call 20; } | card '[[.waiting[] | select(.kind == "tool")], [.signals[] | select(.kind == "stuck")]]')"
check "a call begun after the helper's last stop is still pending until it ends" '["Bash"]' \
  "$({ start 900; stop 880 100; open 400; } | card '[.waiting[] | select(.kind == "tool") | .what]')"
# An end row names no agent; the helper was at work when its call ended.
check "the helper's newest row counts the end of its own call" "\"$(iso 10)\"" \
  "$({ start 900; open 890; printf '{"ts":"%s","event":"tool-end","use":"o890","ok":true}\n' "$(iso 10)"; } | card '.waiting[] | select(.kind == "subagent") | .seenAt')"

# A big log must not take a whole-list scan per row (DASH-PERF-47): 300 helpers with ten calls each,
# a third left running, ran one cycle past 10 s of CPU before the lookups, under 1 s after. 5 s is the
# bound, far from both. The counts are what the card said before.
big() { jq -n -c '[range(300) as $h | ("a\($h)") as $a
  | {ts: "2026-10-01T00:00:00Z", event: "subagent-start", agent_id: $a, type: "Explore"},
    (range(10) as $c | {ts: "2026-10-01T00:00:01Z", event: "tool-start", use: "u\($h)-\($c)", agent: $a, tool: "Grep", kind: "tool", call: "c\($h)-\($c)", timeoutSec: null},
      {ts: "2026-10-01T00:00:02Z", event: "tool-end", use: "u\($h)-\($c)", ok: true}),
    (select($h % 3 != 0) | {ts: "2026-10-01T00:00:03Z", event: "subagent-stop", agent_id: $a, type: "Explore", model: "m", tokens: {input: 1, cachedInput: 1, output: 1}})] | .[]'; }
BIGLOG=$(mktemp); big > "$BIGLOG"
T0=$SECONDS; BIGOUT=$(card '[([.waiting[] | select(.kind == "subagent")] | length), ([.waiting[] | select(.kind == "tool")] | length)]' < "$BIGLOG"); T1=$((SECONDS - T0))
rm -f "$BIGLOG"
check "300 helpers and 6000 call rows give the card: 100 helpers running, no call pending" "[100,0]" "$BIGOUT"
check "and the card is built in under 5 seconds (took ${T1}s)" 1 "$([ "$T1" -lt 5 ] && echo 1 || echo 0)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
