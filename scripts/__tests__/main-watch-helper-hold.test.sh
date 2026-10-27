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
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
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

# Sol r3: a planner runs in <unit>-plan before its unit has a worktree, and a seat was watched only in <unit>.
mkdir -p "$T/ws/pu-plan"; printf 'handle=term_pu\ntask=task_pu\nrole=plan-author\nunit=pu\nlaunched=40000\nworktree=pu-plan\n' > "$S/seat-pu-plan-author.txt"
echo "task_pu running" >> "$F/tasks"; state term_pu working; tick 40100
echo PLAN-DONE > "$F/verdict-term_pu"; state term_pu "done"; tick 40160; tick 40220
grep -q 'seat plan-author on pu finished' "$T/sends" || fail "a planner that finished in its planning worktree was not posted"
# Done with these seats: each one left watched costs every later tick its reads (issue 218).
rm -f "$S"/seat-*.txt; sed -i 's/ .*/ completed/' "$F/tasks"

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

# Issue 238: a seat Orca read idle for one tick while still at work was posted stopped. A second reading at the
# moment of posting (the flip below runs mid-tick, after the tick's first reading) that reads the pane working,
# or the seat's session log written since, posts nothing.
rm -f "$S"/seat-*.txt; sed -i 's/ .*/ completed/' "$F/tasks"; R=120000
for u in wt-r1 wt-r2 wt-r3; do bseat $u term_$u task_$u $((R - 1000)); state term_$u working; done
RLOG=$T/home/.claude/projects/$(printf '%s' "$T/ws/wt-r3" | sed 's/[^a-zA-Z0-9]/-/g')/s.jsonl
mkdir -p "${RLOG%/*}"; echo '{}' > "$RLOG"; touch -d "@$((R - 500))" "$RLOG"
tick $R
for u in wt-r1 wt-r2 wt-r3; do state term_$u "done"; done
printf 'sed -i "/^term_wt-r1 /d" "%s"; echo "term_wt-r1 working" >> "%s"; touch -d @%s "%s"\n' "$F/agents" "$F/agents" $((R + 61)) "$RLOG" > "$F/flip"
tick $((R + 60))
[ "$(posts 'wt-r1 builder stopped without reporting')" = 0 ] || fail "stopped: a seat that read working at the second reading was posted stopped"
[ "$(posts 'wt-r3 builder stopped without reporting')" = 0 ] || fail "stopped: a seat whose session log was written after the tick read it was posted stopped"
[ "$(posts 'wt-r2 builder stopped without reporting')" = 1 ] || fail "stopped: a seat idle at both readings was not posted"

# Issue 402: a Builder that ends its turn while its own background shell job runs is waiting on it, not stopped. The
# job's <task-notification> in its session record releases the hold; a job that never reports holds for HOLD_S (1 h)
# from the record's last write, so a real stop is still posted. No event log: the hold reads the session record alone.
rm -f "$S"/seat-*.txt; sed -i 's/ .*/ completed/' "$F/tasks"; B=200000
jlog() { printf '%s' "$T/home/.claude/projects/$(printf '%s' "$T/ws/$1" | sed 's/[^a-zA-Z0-9]/-/g')/s.jsonl"; }
for u in wt-j1 wt-j2 wt-j3; do
  bseat $u term_$u task_$u $((B - 1000)); state term_$u working; L=$(jlog $u); mkdir -p "${L%/*}"
  jq -nc --arg id "bg-$u" '{type: "user", message: {content: "started"}, toolUseResult: {backgroundTaskId: $id}}' > "$L"
done
for u in wt-j1 wt-j2; do touch -d "@$((B - 50))" "$(jlog $u)"; done
touch -d "@$((B - 3700))" "$(jlog wt-j3)"
tick $((B - 100)); for u in wt-j1 wt-j2 wt-j3; do state term_$u "done"; done; tick $B
[ "$(posts 'wt-j1 builder stopped without reporting')" = 0 ] || fail "bg job: a Builder waiting on its open background job was posted as stopped"
[ "$(posts 'wt-j3 builder stopped without reporting')" = 1 ] || fail "bg job: a Builder whose job stayed open past HOLD_S was not posted"
jq -nc '{type: "user", message: {content: "<task-notification><task-id>bg-wt-j2</task-id><status>completed</status></task-notification>"}}' >> "$(jlog wt-j2)"
touch -d "@$((B + 30))" "$(jlog wt-j2)"; tick $((B + 60))
[ "$(posts 'wt-j2 builder stopped without reporting')" = 1 ] || fail "bg job: a Builder still stopped after its job's notification landed was not posted"
[ "$(posts 'wt-j1 builder stopped without reporting')" = 0 ] || fail "bg job: a Builder whose job is still open was posted after another's notification"

echo "PASS main-watch-helper-hold.test.sh"
