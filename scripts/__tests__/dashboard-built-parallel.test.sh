#!/usr/bin/env bash
# covers: scripts/dashboard.sh scripts/subagent-usage.sh
# dashboard-built-parallel.test.sh -- issue 292: the collector's two slow groups, measures (subagent-usage.sh and two
# ledger reads) and guardBlocks (the hook fire log), run beside the rest of one project's collect instead of after it.
# Pinned: the wall time, the same data as the sequential order gave, a failing group still failing the collect, and the
# subagent ledger's lock still held by the writer. The fixture is dashboard-built.test.sh's.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"
REAL=$SOURCE
NOW=$(date +%s)
ROW='{"timestamp":"2026-10-23T00:00:00Z","hook":"h","event":"PreToolUse","session_id":"s1","decision":"allow"}'
# The scripts the collect runs, copied so one of them can be stubbed.
cp -R "$REAL" "$T/copy" && rm -rf "$T/copy/.git"; SOURCE=$T/copy
stub() { printf '#!/usr/bin/env bash\n%s\n' "$1" > "$T/copy/scripts/subagent-usage.sh"; }
# pdash <fire log>: one dashboard.sh project collect with the hook fire log named.
pdash() { rm -rf "$T/out/run"; timeout 90 env -u COMMANDECK_SCRATCH -u CODEX_HOME COMMANDECK_HOOK_FIRE_LOG="$1" PATH="$BIN:$PATH" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_DASHBOARD_DIR="$T/out" COMMANDECK_MAIN="$MAIN" DASH_NOW="$NOW" bash "$SOURCE/scripts/dashboard.sh" --project "$T/out/run" >"$T/out.log" 2>&1; }
norm() { jq -cS 'first(.[]) | del(.partSeconds) | .sources |= map_values(.status)' "$T/out/run/project.json"; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }

# Order, not wall time (which moves with the load): the github groups run in the main chain and call gh; measures and
# guardBlocks, once they run beside it, start before the chain's last gh call, and sequentially they start after it.
# The stubbed subagent-usage.sh stamps its start, and a python3 in front of the real one stamps the guardBlocks reader's.
REALPY=$(command -v python3)
printf '#!/usr/bin/env bash\ndate +%%s.%%N > "%s/gh.last"\nexit 1\n' "$T" > "$BIN/gh"
printf '#!/usr/bin/env bash\ncase "$*" in *guard-blocks.json*) date +%%s.%%N > "%s/g.start" ;; esac\nexec %q "$@"\n' "$T" "$REALPY" > "$BIN/python3"; chmod +x "$BIN/gh" "$BIN/python3"
FIRE=$T/fire.jsonl; echo "$ROW" > "$FIRE"
stub 'exit 0'; rm -rf "$T/out/cache"; pdash "$FIRE"; BASE=$(norm)
printf '#!/usr/bin/env bash\ndate +%%s.%%N > "%s/m.start"\n' "$T" > "$T/copy/scripts/subagent-usage.sh"
rm -rf "$T/out/cache" "$T/gh.last"
pdash "$FIRE"
before() { awk -v a="$(cat "$1" 2>/dev/null)" -v b="$(cat "$T/gh.last" 2>/dev/null)" 'BEGIN { print (a != "" && b != "" && a < b) ? "yes" : "no " a " " b }'; }
check "measures starts before the chain's last gh call" yes "$(before "$T/m.start")"
check "guardBlocks reads its log before the chain's last gh call" yes "$(before "$T/g.start")"
check "that collect's project object is the one the same fixture gave before, after the clock values are taken out" "$BASE" "$(norm)"
check "and it is a whole object, not an empty one" yes "$([ ${#BASE} -gt 1000 ] && echo yes)"

# A guardBlocks part that fails fails the collect and leaves the last data.js alone. The state file names the log at its
# size and holds a block of a session it does not list, which the part raises KeyError on.
stub 'exit 0'; rm -rf "$T/out3"; mkdir -p "$T/out3"
full() { env -u COMMANDECK_SCRATCH -u CODEX_HOME COMMANDECK_HOOK_FIRE_LOG="$FIRE" PATH="$BIN:$PATH" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_DASHBOARD_DIR="$T/out3" COMMANDECK_MAIN="$MAIN" DASH_NOW="$(date +%s)" bash "$SOURCE/scripts/dashboard.sh" >"$T/out3.log" 2>&1; }
full; check "the fixture's own full collect publishes data.js" yes "$([ -s "$T/out3/data.js" ] && echo yes)"
cp "$T/out3/data.js" "$T/data.before"
jq -cn --arg f "$FIRE" --argjson n "$(wc -c < "$FIRE")" '{version: 1, files: [[$f, $n]], sessions: {}, blocks: [[{}, "s9", null]], blocked: []}' > "$T/out3/cache/demo/guard-blocks.json"
full; RC=$?
check "a guardBlocks part that fails fails the collect" yes "$([ "$RC" != 0 ] && echo yes)"
check "and the last data.js is kept, byte for byte" yes "$(cmp -s "$T/out3/data.js" "$T/data.before" && echo yes)"

# measures still takes the ledger's lock: held by this test for 2 s, the collect's ledger gets no row until it lets go.
SOURCE=$REAL; SLUG=$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$MAIN"); AG=$HOME/.claude/projects/$SLUG/sess1/subagents
mkdir -p "$AG" "$MAIN/.claude/metrics"
jq -cn --arg c "$MAIN" '{type: "assistant", cwd: $c, message: {model: "claude-sonnet-5-5", usage: {input_tokens: 5, output_tokens: 2}}}' > "$AG/agent-a1.jsonl"
touch -d '1 hour ago' "$AG/agent-a1.jsonl"
LEDGER=$MAIN/.claude/metrics/subagent-usage.jsonl; rm -f "$LEDGER"
( exec 9>>"$LEDGER.lock"; flock 9; sleep 2 ) &
sleep 0.5; rm -rf "$T/out/cache"
pdash "$FIRE" &
sleep 1
HELD=$(grep -c . "$LEDGER" 2>/dev/null || true)
wait
check "while the test holds the ledger's lock the collect has appended no row, and after it lets go it has appended one" "0 1" "${HELD:-0} $(grep -c . "$LEDGER" 2>/dev/null)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
