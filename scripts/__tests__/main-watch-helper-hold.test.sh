#!/usr/bin/env bash
# A Builder that ends its turn to wait on a helper it started is held, not
# posted as stopped (#41). What this pins: only the Builder's own unit marker
# ends the hold, never another line ending -DONE that it quotes (#44), and a
# hold the Builder left by working again does not carry its old clock into
# the next wait, where it would expire at once (#45).
#
# The fake orca-ide answers each pane's state from `agents` and records every
# send; read-verdict.sh answers from `verdict-<handle>`. Each tick is one
# `--once` run, with COMMANDECK_NOW as the clock.
set -euo pipefail

SOURCE=$(git rev-parse --show-toplevel)
# Physical path: main-watch finds main's pane by comparing Orca's worktreePath with it.
T=$(cd "$(mktemp -d)" && pwd -P)
LIVE= ARGV=
trap 'kill $LIVE $ARGV 2>/dev/null; rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; [ ! -s "$T/sends" ] || { echo "sends were:" >&2; cat "$T/sends" >&2; }; exit 1; }

REPO=$T/repo S=$T/scratch F=$T/fake
mkdir -p "$REPO/scripts" "$T/bin" "$S" "$F" "$T/home" "$T/ws"
git -C "$REPO" init -q
cp "$SOURCE/scripts/main-watch.sh" "$SOURCE/scripts/paths.sh" "$SOURCE/scripts/project-main.sh" "$SOURCE/scripts/requirements.sh" \
   "$SOURCE/scripts/host-services.sh" "$SOURCE/scripts/orca-task-create.sh" "$SOURCE/scripts/dashboard_builders.jq" "$REPO/scripts/"
mkdir -p "$REPO/config"; cp "$SOURCE/config/routing.json" "$REPO/config/"
# --state (the latest message's marker) answers from `state-<unit>`; nothing there is no marker.
cat > "$REPO/scripts/read-verdict.sh" <<RV
#!/usr/bin/env bash
[ "\$1" = --state ] && { cat "$F/state-\${3##*/}" 2>/dev/null; exit 0; }
cat "$F/verdict-\$1" 2>/dev/null || exit 3
RV
printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/scripts/close-done-panes.sh"
echo run_test > "$S/current-run"
export COMMANDECK_HOST_OS=Linux
: > "$F/agents"; : > "$F/tasks"; : > "$T/sends"
# No processes: the broker reaper must never see or signal this machine's own.
printf '#!/usr/bin/env bash\ncase "$*" in *lstart=*) exec /bin/ps "$@" ;; esac\nexit 0\n' > "$T/bin/ps"
cat > "$T/bin/orca-ide" <<ORCA
#!/usr/bin/env bash
case "\$1 \$2" in
  "orchestration task-list") jq -Rn '{result:{tasks:[inputs | split(" ") | {id:.[0], status:.[1]}]}}' < "$F/tasks" ;;
  "orchestration task-create")
    n=\$(( \$(wc -l < "$F/tasks") + 1 )); echo "task_new\$n pending" >> "$F/tasks"
    echo "{\"ok\":true,\"result\":{\"task\":{\"id\":\"task_new\$n\"}}}" ;;
  "orchestration send") printf '%s' "\$*" | tr '\n' ' ' >> "$T/sends"; echo >> "$T/sends"; echo '{"ok":true}' ;;
  "terminal send") printf '%s\n' "\$*" >> "$T/typed"; echo '{"ok":true,"result":{"stages":["typed","submitted","turn_started"]}}' ;;
  "terminal read") if [ -e "$F/screen" ]; then jq -Rn '{result:{terminal:{tail:[inputs],latestCursor:"0"}}}' < "$F/screen"
    else echo '{"result":{"terminal":{"tail":[],"latestCursor":"0"}}}'; fi ;;
  "terminal list")
    jq -Rn --arg main "$REPO" '{result:{terminals:[inputs | split(" ") | {handle:.[0], tabId:.[0], leafId:"l",
      worktreePath:(if (.[0] | startswith("term_main")) then \$main else "/elsewhere" end), agentIdentity:"claude"}]}}' < "$F/agents" ;;
  "orchestration inbox") cat "$F/inbox" 2>/dev/null || echo '{"ok":true,"result":{"messages":[]}}' ;;
  "orchestration run-list") echo '{"result":{"runs":[{"id":"run_test","coordinator_handle":"term_main"}]}}' ;;
  "worktree ps") jq -Rn '{result:{worktrees:[{agents:[inputs | split(" ") | {paneKey:(.[0] + ":l"), state:.[1]}]}]}}' < "$F/agents" ;;
  *) echo '{}' ;;
esac
ORCA
chmod +x "$T/bin/orca-ide" "$T/bin/ps"

mw() { (cd "$REPO" && PATH=$T/bin:$PATH HOME=$T/home COMMANDECK_SCRATCH=$S COMMANDECK_WORKSPACES=$T/ws bash scripts/main-watch.sh "$@"); }
tick() { COMMANDECK_NOW=$1 mw --once 2>>"$T/stderr" || fail "main-watch exited non-zero at $1"; }
state() { sed -i "/^$1 /d" "$F/agents"; echo "$1 $2" >> "$F/agents"; }
posts() { grep -c -- "$1" "$T/sends" || true; }
bseat() { mkdir -p "$T/ws/$1/.claude"; printf 'handle=%s\ntask=%s\nrole=builder\nunit=%s\nlaunched=%s\n' "$2" "$3" "$1" "$4" > "$S/seat-$1-builder.txt"; echo "$3 running" >> "$F/tasks"; }
hrow() { # <epoch> <event> <agent> -- one helper row as the Builder's hooks log it
  jq -nc --argjson t "$1" --arg e "$2" --arg a "$3" '{ts: ($t | todate), event: $e} + if $e == "tool-start"
  then {use: "h\($t)", agent: $a, tool: "Grep", kind: "tool", call: "h"} else {agent_id: $a, type: "Explore"} end'; }
state term_main idle
# The watcher posts only what finished after its first tick.
tick 5000

# #45: the issue's timeline. The hold starts at 10000; the Builder works again
# at 10100; at 13700 it ends its turn on a helper it has just started. wt-h6,
# held from 10000 too, gets its helper back at 13600 and works only between two
# ticks, so no tick sees it `working`: its new helper's start is the only sign.
for u in wt-h5 wt-h6; do bseat $u term_$u task_$u 8000; state term_$u working; done; tick 9900
for u in wt-h5 wt-h6; do hrow 9990 subagent-start a1 > "$T/ws/$u/.claude/builder-events.jsonl"; state term_$u "done"; done; tick 10000
[ "$(posts 'wt-h[56]')" = 0 ] || fail "a Builder waiting on its first helper was posted"
hrow 10050 subagent-stop a1 >> "$T/ws/wt-h5/.claude/builder-events.jsonl"
state term_wt-h5 working; tick 10100
hrow 13600 subagent-stop a1 >> "$T/ws/wt-h6/.claude/builder-events.jsonl"
for u in wt-h5 wt-h6; do { hrow 13650 subagent-start a2; hrow 13680 tool-start a2; } >> "$T/ws/$u/.claude/builder-events.jsonl"; done
state term_wt-h5 "done"; tick 13700
[ "$(posts wt-h5)" = 0 ] || fail "a Builder that worked again and now waits on a new helper was posted on the old hold's clock: $(grep wt-h5 "$T/sends")"
[ "$(posts wt-h6)" = 0 ] || fail "a Builder that worked between two ticks and now waits on a new helper was posted on the old hold's clock: $(grep wt-h6 "$T/sends")"

# #44: the issue's input. wt-h1 quotes its design pane's marker and waits on a
# fresh Explore helper; wt-h3 printed its own marker with a helper out.
H=20000
for u in wt-h1 wt-h3; do bseat $u term_$u task_$u $((H - 2000)); state term_$u working; done
{ hrow $((H - 120)) subagent-start a1; hrow $((H - 30)) tool-start a1; } > "$T/ws/wt-h1/.claude/builder-events.jsonl"
printf 'Design coauthor replied:\nDESIGN-DONE\nWaiting on Explore.\n' > "$F/verdict-term_wt-h1"
hrow $((H - 120)) subagent-start a1 > "$T/ws/wt-h3/.claude/builder-events.jsonl"; echo 'WT-H3-DONE' > "$F/verdict-term_wt-h3"
tick $H; for u in wt-h1 wt-h3; do state term_$u "done"; done; tick $((H + 60))
[ "$(posts wt-h1)" = 0 ] || fail "a Builder quoting another pane's DONE marker, with a helper out, was posted: $(grep wt-h1 "$T/sends")"
grep -q 'seat builder on wt-h3 finished' "$T/sends" || fail "a Builder that printed its own unit marker with a helper out was not posted as finished"

# Mail from another pane that sits unread while main is idle wakes main: two orders once sat
# 13 minutes with main idle, because only this watcher's own posts ever typed a wake. A heads-up
# note and main's own send are not news to main.
msg() { jq -nc --arg f "$1" --arg s "$2" '{to_handle: "run:run_test", from_handle: $f, read: 0, type: "status", subject: $s}'; }
inbox() { jq -sc '{ok: true, result: {messages: .}}' > "$F/inbox"; }
typed() { grep -c 'items are waiting in your Orca inbox' "$T/typed" 2>/dev/null || true; }
# The seats above are done with and their tasks closed, so nothing of theirs is pending.
rm -f "$S"/seat-*.txt "$S/main-watch/wake"; sed -i 's/ .*/ completed/' "$F/tasks"
M=30000; : > "$T/typed"
{ msg term_main "main's own note"; msg term_x "heads-up: 2 notes"; } | inbox
tick $M; tick $((M + 200))
[ "$(typed)" = 0 ] || fail "main was woken for a heads-up note or its own send"
{ msg term_main "main's own note"; msg term_x "heads-up: 2 notes"; msg term_wt-h1 "order from a Builder"; } | inbox
tick $((M + 300)); tick $((M + 360))
[ "$(typed)" = 0 ] || fail "main was woken for mail unread under 2 minutes"
tick $((M + 420))
[ "$(typed)" = 1 ] || fail "mail unread 2 minutes with main idle did not wake main (typed $(typed))"
tick $((M + 480))
[ "$(typed)" = 1 ] || fail "an unanswered main was woken again inside 2 minutes"
rm -f "$F/inbox"

# Issue 198: main idle with its own question open reads nothing, and main-watch gave up on it without a word. The
# relay hears once per wake episode, through main's run under main's handle: the service has no pane of its own.
unset ORCA_TERMINAL_HANDLE
rm -f "$S/main-watch/wake" "$S/main-watch/unread-since"; : > "$T/typed"; W=35000
printf 'Which release?\n> 1. 0.18.0\nEnter to select, Esc to cancel\n' > "$F/screen"
msg term_x "order from the relay" | inbox
tick $W; tick $((W + 120))
[ "$(typed)" = 0 ] || fail "main was typed into while its screen showed an open question"
[ "$(posts 'cos: main-watch')" = 0 ] || fail "the relay was told with no Chief-of-Staff worktree"
mkdir -p "$T/ws/Chief-of-Staff"; tick $((W + 180)); tick $((W + 240))
[ "$(posts 'cos: main-watch: main has not read finished work')" = 1 ] || fail "main blocked on a prompt with work unread: the relay was told $(posts 'cos: main-watch') times, not once"
grep 'cos: main-watch' "$T/sends" | grep -q -- '--to run:run_test.*--from term_main' || fail "the relay's note did not go to main's run under main's handle"
grep 'cos: main-watch' "$T/sends" | grep -q 'answer the prompt in main' || fail "the relay's note does not name the fix"
[ "$(typed)" = 0 ] || fail "main was typed into while its screen showed an open question"
rm -rf "$F/screen" "$F/inbox" "$T/ws/Chief-of-Staff" "$S/main-watch/wake" "$S/main-watch/unread-since"

# Sol r3: a planner runs in <unit>-plan before its unit has a worktree, and a seat was watched only in <unit>.
mkdir -p "$T/ws/pu-plan"; printf 'handle=term_pu\ntask=task_pu\nrole=plan-author\nunit=pu\nlaunched=40000\nworktree=pu-plan\n' > "$S/seat-pu-plan-author.txt"
echo "task_pu running" >> "$F/tasks"; state term_pu working; tick 40100
echo PLAN-DONE > "$F/verdict-term_pu"; state term_pu "done"; tick 40160; tick 40220
grep -q 'seat plan-author on pu finished' "$T/sends" || fail "a planner that finished in its planning worktree was not posted"

# Issue 158: a Builder that ends its turn on a review pass it started is waiting, not stopped. A pass logs only
# its start and end rows, so it is held from its start for HOLD_S (1 h), and a finished pass holds nothing.
crow() { jq -nc --argjson t "$1" --arg e "$2" '{ts: ($t | todate), event: $e, pass: "review", round: 2}'; }
for u in wt-c1 wt-c2; do bseat $u term_$u task_$u 48000; state term_$u working; crow 49400 codex-start > "$T/ws/$u/.claude/builder-events.jsonl"; done
crow 49500 codex-end >> "$T/ws/wt-c2/.claude/builder-events.jsonl"
tick 49900; for u in wt-c1 wt-c2; do state term_$u "done"; done; tick 50000
[ "$(posts 'wt-c1 builder stopped without reporting')" = 0 ] || fail "a Builder waiting on a review pass started 10 minutes ago was posted as stopped"
[ "$(posts 'wt-c2 builder stopped without reporting')" = 1 ] || fail "a Builder whose pass had ended was not posted as stopped at once"
tick $((49400 + 3660))
[ "$(posts 'wt-c1 builder stopped without reporting')" = 1 ] || fail "a Builder held on a pass started 61 minutes ago was not posted"

# Issue 167: a project that runs its own watcher posts the same heads-up notes from the same store. A live claim
# from it for this checkout stands this watcher down, and says so once; anything short of one is no claim.
mkdir -p "$T/home/.claude/plugins/store" "$T/home/.claude/projects/p"
offer() { # <name> <shownAt s>: the store shows one offer, from a session that ran in this checkout
  jq -nc --arg id "sess-$1" --argjson at "$2" --arg l "LINE-$1" '{sessions: [{id: $id, view: {kind: "offer", shownAt: ($at * 1000), line: $l, explanation: "why"}}]}' \
    > "$T/home/.claude/plugins/store/cc-plugin-you-should-know_builtin-t.json"
  jq -nc --arg c "$REPO" '{cwd: $c}' > "$T/home/.claude/projects/p/sess-$1.jsonl"; }
claim() { printf 'pid=%s\nmain=%s\nat=%s\n' "$1" "$2" "$3" > "$S/heads-up-owner"; }
yields() { grep -c 'nothing is posted (finished, stopped, stalled, heads-up)' "$T/stderr" || true; }
sleep 30 & LIVE=$!
N=60000; offer a $N; claim "$LIVE" "$REPO" $N; tick $N; tick $((N + 60))
[ "$(posts LINE-a)" = 0 ] || fail "a heads-up note was posted while a live claim for this checkout names another watcher"
[ "$(yields)" = 1 ] || fail "the stand-down was not said exactly once ($(yields) times)"
rm -f "$S/heads-up-owner"; N=$((N + 120)); offer b $N; tick $N
[ "$(posts LINE-b)" = 1 ] || fail "with no claim (the project's watcher stood down) the note was not posted"
[ "$(posts LINE-a)" = 0 ] || fail "a note captured under the claim was posted when it ended"
sleep 0 & DEAD=$!; wait $DEAD
for c in "stale:$LIVE:$REPO:-301" "dead:$DEAD:$REPO:0" "nested:$LIVE:$REPO/nested:0" "other:$LIVE:$T/other:0"; do
  IFS=: read -r name pid main age <<<"$c"
  N=$((N + 60)); offer "$name" $N; claim "$pid" "$main" $((N + age)); tick $N
  [ "$(posts "LINE-$name")" = 1 ] || fail "a $name claim stood the watcher down"
done
rm -f "$S/heads-up-owner"
bash -c 'sleep 30' "$REPO/ops/main-watch.sh" & ARGV=$!
N=$((N + 60)); offer argv $N; tick $N
[ "$(posts LINE-argv)" = 1 ] || fail "a process that only names a watcher script in its arguments stood the watcher down"
[ "$(yields)" = 1 ] || fail "a claim that ended did not reset the stand-down line, or said it again: $(yields)"
# A claim stands down only for notes its owner must have seen: shown before its last cycle (at=) and still shown.
# "old" is newer than the owner's at= on the first tick and gone from the store by the second; it waits, and
# posts once the claim ends. "seen" is shown before at= and still shown: the owner posted it.
kill "$LIVE" 2>/dev/null || true; sleep 60 & LIVE=$!
N=$((N + 60)); offer old $N; claim "$LIVE" "$REPO" $((N - 1)); tick $N
offer seen $((N + 30)); N=$((N + 60)); claim "$LIVE" "$REPO" $N; tick $N
[ "$(posts LINE-old)$(posts LINE-seen)" = 00 ] || fail "a heads-up note was posted while a live claim for this checkout names another watcher"
rm -f "$S/heads-up-owner"; N=$((N + 60)); tick $N
[ "$(posts LINE-old)" = 1 ] || fail "a note the claim owner never saw (shown after its last cycle, then gone) was lost"
[ "$(posts LINE-seen)" = 0 ] || fail "a note the claim owner saw was posted when the claim ended"

# Issue 167, reopened: the project's watcher posts every item, so a live claim stands this watcher down for its
# finished, stopped and stalled items too, not only heads-up notes, and says so once. An item first seen under the
# claim that the owner has run no cycle past (its at= not after the sighting) is posted once the claim ends.
kill "$LIVE" 2>/dev/null || true; sleep 300 & LIVE=$!
B=100000; Y0=$(yields)
mkdir -p "$T/ws/pf-plan"; printf 'handle=term_pf\ntask=task_pf\nrole=plan-author\nunit=pf\nlaunched=%s\nworktree=pf-plan\n' $((B - 1400)) > "$S/seat-pf-plan-author.txt"
echo "task_pf running" >> "$F/tasks"
for u in wt-s1 wt-st; do bseat $u term_$u task_$u $((B - 1400)); done
for u in pf wt-s1 wt-st; do state term_$u working; done; tick $((B - 1300))
echo PLAN-DONE > "$F/verdict-term_pf"; state term_pf "done"; state term_wt-s1 "done"
claim "$LIVE" "$REPO" $B; for d in 0 60 120; do tick $((B + d)); done
ITEMS=('seat plan-author on pf finished' 'wt-s1 builder stopped without reporting' 'wt-st builder stalled; inspect')
for p in "${ITEMS[@]}"; do [ "$(posts "$p")" = 0 ] || fail "main-watch posted '$p' while a live claim for this checkout names another watcher"; done
[ "$(yields)" = $((Y0 + 1)) ] || fail "the stand-down for every item was not said exactly once ($(( $(yields) - Y0 )) times)"
rm -f "$S/heads-up-owner"; tick $((B + 180)); tick $((B + 240))
for p in "${ITEMS[@]}"; do [ "$(posts "$p")" = 1 ] || fail "'$p', which the claim owner never saw, was posted $(posts "$p") times once the claim ended, not once"; done
# The crash window: an item first seen under a claim whose owner then stops (at= ages past 300 s) is posted on the
# next tick. One first seen under a claim whose owner then ran another cycle (a later at=) was posted there: never here.
C=$((B + 1000))
for u in wt-x1 wt-x2; do bseat $u term_$u task_$u $((C - 200)); state term_$u working; done; tick $((C - 100))
state term_wt-x1 "done"; claim "$LIVE" "$REPO" $C; tick $C
[ "$(posts 'wt-x1 builder stopped')" = 0 ] || fail "a stopped seat was posted under a live claim"
tick $((C + 301))
[ "$(posts 'wt-x1 builder stopped')" = 1 ] || fail "an item first seen under a claim that then went stale was not posted"
D=$((C + 400)); state term_wt-x2 "done"; claim "$LIVE" "$REPO" $D; tick $D
claim "$LIVE" "$REPO" $((D + 60)); tick $((D + 60))
[ "$(posts 'wt-x2 builder stopped')" = 0 ] || fail "a stopped seat was posted under a live claim"
rm -f "$S/heads-up-owner"; tick $((D + 120))
[ "$(posts 'wt-x2 builder stopped')" = 0 ] || fail "an item the claim owner ran a cycle past was posted when the claim ended"
# The owner posting an item is not main handling it: once the claim ends, an item whose task is still open is
# reminded every 5 minutes from the owner's last cycle (at=), and settles only when main closes its task.
tick $((D + 400))
[ "$(posts 'wt-x2 builder stopped')" = 1 ] || fail "an open item the claim owner posted was never reminded once the claim ended"
sed -i 's/^task_wt-x2 .*/task_wt-x2 completed/' "$F/tasks"; tick $((D + 800))
[ "$(posts 'wt-x2 builder stopped')" = 1 ] || fail "an item main closed was re-posted"

# Issue 203, WARM: a 5-minute Builder at its prompt waiting on a background job gets one "." line just before its own
# cache lapses, up to a cost-bound budget. Orca reads such a pane working or done, so the gate is the session record's
# end_turn marker, not the label. A ping never posts to main and never counts as an episode toward the third-episode post.
rm -f "$S"/seat-*.txt; : > "$T/sends"; : > "$T/typed"
W=90000
bts() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
wfile() { printf '%s' "$T/home/.claude/projects/$(printf '%s' "$T/ws/$1" | sed 's/[^a-zA-Z0-9]/-/g')/s.jsonl"; }
wlog() { # unit epoch stop [read write] -- one main-thread request and its reply in the unit's session record, its mtime following
  local f; f=$(wfile "$1"); mkdir -p "${f%/*}"
  printf '{"type":"user","isSidechain":false,"timestamp":"%s","message":{}}\n' "$(bts "$2")" >> "$f"
  printf '{"type":"assistant","isSidechain":false,"timestamp":"%s","message":{"stop_reason":"%s","usage":{"input_tokens":2,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":0}}}}\n' \
    "$(bts "$2")" "$3" "${4:-95000}" "${5:-5000}" "${5:-5000}" >> "$f"
  touch -d "@$2" "$f"
}
wseat() { # unit handle state [read write last-stop] -- a Builder whose last reply, 230 s before W, left a background job running
  bseat "$1" "$2" "t_$1" $((W - 4000)); state "$2" "$3"
  printf '{"ts":"%s","event":"tool-start","use":"o1","tool":"Bash","kind":"shell","call":"o1"}\n{"ts":"%s","event":"tool-end","use":"o1","ok":true}\n' \
    "$(bts $((W - 3000)))" "$(bts $((W - 2999)))" > "$T/ws/$1/.claude/builder-events.jsonl"
  wlog "$1" $((W - 400)) tool_use "${4:-95000}" "${5:-5000}"
  printf '{"type":"user","toolUseResult":{"stdout":"","backgroundTaskId":"bW"}}\n' >> "$(wfile "$1")"
  wlog "$1" $((W - 230)) "${6:-end_turn}" "${4:-95000}" "${5:-5000}"
}
warms() { grep -c -- "--terminal $1 --text Signal WARM: keep-alive while you wait. Reply with one . and end your turn." "$T/typed" || true; }
wseat wt-w1 term_w1 working
wseat wt-w2 term_w2 done
wseat wt-w3 term_w3 working 95000 5000 tool_use
wseat wt-w5 term_w5 waiting
wseat wt-w7 term_w7 working 500 498
tick $W
[ "$(warms term_w1)" = 1 ] || fail "warm: a Builder reading working, its log ending on end_turn with a job open, got $(warms term_w1) WARM lines, not one"
[ "$(warms term_w2)" = 1 ] || fail "warm: the same Builder reading done did not get its first WARM"
[ "$(warms term_w3)" = 0 ] || fail "warm: a Builder whose newest reply is a tool_use (blocked inside a call) was pinged"
[ "$(warms term_w5)" = 0 ] || fail "warm: a pane reading waiting was pinged"
[ "$(posts wt-w)" = 0 ] || fail "warm: a ping posted to main"
tick $((W + 10))
[ "$(warms term_w1)" = 1 ] || fail "warm: the next tick in the same window sent a second ping"
wlog wt-w1 $((W + 30)) end_turn; wlog wt-w7 $((W + 30)) end_turn 500 498
tick $((W + 260))
[ "$(warms term_w1)" = 2 ] || fail "warm: after the Builder's own . reply the next window did not get a ping (got $(warms term_w1))"
[ "$(warms term_w7)" = 2 ] || fail "warm: a 1000-token context should have pinged twice by now (got $(warms term_w7))"
wlog wt-w7 $((W + 290)) end_turn 500 498; tick $((W + 520))
[ "$(warms term_w7)" = 2 ] || fail "warm: a third ping went past the budget of 2 for one anchor"
# After two WARMs the Builder's first QUIET is still its first episode: WARM keeps its own history.
H1=$S/main-watch/builder-wt-w1-term_w1
[ "$(grep -c . "$H1.warm")" = 2 ] && ! grep -q WARM "$H1" 2>/dev/null || fail "warm: the pings were not kept apart from the episode history"
# The job ends (its notification row), so the idle Builder is QUIET.
printf '{"type":"queue-operation","content":"<task-notification>\\n<task-id>bW</task-id>\\n</task-notification>"}\n' >> "$(wfile wt-w1)"
touch -d "@$((W + 30))" "$(wfile wt-w1)"; tick $((W + 560))
[ "$(grep -c '^QUIET ' "$H1")" = 1 ] && [ "$(posts 'wt-w1 is QUIET')" = 0 ] || fail "warm: after two WARMs the first QUIET was not episode 1, or was posted"

echo "PASS main-watch-helper-hold.test.sh"
