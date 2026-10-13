#!/usr/bin/env bash
# A seat whose TURN IS OVER must end its driver's wait now, not at the timeout.
# On 2026-09-15 the wt775 plan-author finished on `PLAN-BLOCKED`, asking main for
# a ruling it could not get itself. Nothing read that: seat.sh wait only knows
# "marker seen" or "timed out", so the driver blocked on a stopped pane for 75
# minutes and the question never reached main at all.
#
# The signal is the Codex log's own `task_complete` event, which carries the
# pane's last words. read-verdict.sh exits 5 on it; seat.sh wait stops and
# prints the message so main gets the question instead of a pointer to a pane.
set -euo pipefail

SOURCE=$(git rev-parse --show-toplevel)
SCRATCH=$(mktemp -d /tmp/seat-wait-finished-pane-test.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

UNIT=fake-unit
ROLE=companion
WT=$SCRATCH/ws/$UNIT
mkdir -p "$WT" "$SCRATCH/bin" "$SCRATCH/codex/sessions"
cat > "$SCRATCH/seat-$UNIT-$ROLE.txt" <<EOF
handle=term_fin
task=task_fake
role=$ROLE
unit=$UNIT
spec=$SCRATCH/spec.md
EOF
echo "print PLAN-DONE on its own final line" > "$SCRATCH/spec.md"

LOG=$SCRATCH/codex/sessions/rollout.jsonl
write_log() { # $1 = with-task-complete | mid-turn
  {
    printf '{"timestamp":"2026-09-15T19:00:00.000Z","type":"session_meta","payload":{"type":"session_meta","cwd":"%s"}}\n' "$WT"
    # The launch prompt names the spec, which is how the reader ties this log to the seat record.
    printf '{"timestamp":"2026-09-15T19:00:30.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Your task spec is the file %s."}]}}\n' "$SCRATCH/spec.md"
    printf '{"timestamp":"2026-09-15T19:01:00.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Reading the manifest."}]}}\n'
    if [ "$1" = with-task-complete ]; then
      printf '{"timestamp":"2026-09-15T19:04:00.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1","last_agent_message":"Stored-row count and the reader-removal ruling still required.\\nPLAN-BLOCKED"}}\n'
    fi
  } > "$LOG"
}

# The pane is alive and idle. `terminal read` returns nothing, so the marker is
# absent from the buffer and only the session log can say what happened.
cat > "$SCRATCH/bin/orca-ide" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = terminal ] && [ "${2:-}" = list ]; then
  case " $* " in
    *--json*) printf '{"result":[{"handle":"term_fin","worktreePath":"%s","agentIdentity":"codex"}]}\n' "$FAKE_WT" ;;
    *) echo "term_fin  the companion pane" ;;
  esac
  exit 0
fi
[ "${1:-}" = terminal ] && [ "${2:-}" = read ] && { echo '{"result":{"terminal":{"tail":[]}}}'; exit 0; }
exit 0
EOF
chmod +x "$SCRATCH/bin/orca-ide"

run_wait() {
  PATH="$SCRATCH/bin:$PATH" COMMANDECK_SCRATCH="$SCRATCH" FAKE_WT="$WT" \
  CODEX_HOME="$SCRATCH/codex" COMMANDECK_WORKSPACES="$SCRATCH/ws" \
  COMMANDECK_LOOP_POLL_SECONDS=1 \
  bash "$SOURCE/scripts/seat.sh" wait "$ROLE" "$UNIT" \
    --marker PLAN-DONE --timeout-s "${1:?}" 2>&1
}
run_verdict() {
  PATH="$SCRATCH/bin:$PATH" COMMANDECK_SCRATCH="$SCRATCH" CODEX_HOME="$SCRATCH/codex" \
  bash "$SOURCE/scripts/read-verdict.sh" term_fin 5 "$WT" codex "$UNIT" "" "" 0 2>&1
}

# 1. read-verdict.sh distinguishes a finished pane from a working one: exit 5,
#    and the pane's last message is in the output, because that message is the
#    only thing that tells main what the seat needs.
write_log with-task-complete
OUT=$(run_verdict) && fail "read-verdict returned success on a pane with no verdict"
RC=$?
[ "$RC" -eq 5 ] || fail "expected exit 5 for a finished pane, got $RC: $OUT"
grep -q 'PANE FINISHED WITH NO VERDICT' <<<"$OUT" \
  || fail "no finished-pane heading; got: $OUT"
grep -q 'PLAN-BLOCKED' <<<"$OUT" \
  || fail "the pane's last message was dropped; got: $OUT"

# 2. seat.sh wait ends on it in one poll instead of sitting out the timeout, and
#    carries the message out so the caller can put it straight into a wake.
START=$(date +%s)
OUT=$(run_wait 300) && fail "wait returned success on a seat that never printed the marker"
ELAPSED=$(( $(date +%s) - START ))
[ "$ELAPSED" -lt 30 ] || fail "took ${ELAPSED}s to notice a finished pane"
grep -q 'finished without PLAN-DONE' <<<"$OUT" \
  || fail "no finished-without-marker message; got: $OUT"
grep -q 'PLAN-BLOCKED' <<<"$OUT" \
  || fail "the wait did not carry the pane's last message; got: $OUT"

# 3. A pane STILL MID-TURN must not trip it. This is the expensive mistake in
#    the other direction: ending a healthy seat's wait kills a live unit, so the
#    absence of `task_complete` has to keep the wait running to its timeout.
write_log mid-turn
OUT=$(run_wait 2) && fail "wait returned success with no marker"
grep -q 'finished without' <<<"$OUT" \
  && fail "a pane still mid-turn was read as finished; got: $OUT"
grep -q 'no PLAN-DONE on term_fin within 2s' <<<"$OUT" \
  || fail "expected the normal timeout message on a working pane; got: $OUT"

n=8

# 4. WORKER STATE MODE (read-verdict.sh --state). One reader decides "turn over,
#    nothing left running" for every waiter, so a completed worker is released
#    and an idle one is reported, while a running turn or a background command
#    is never read as either. Record shapes are the real producers': Claude
#    turn_duration closes a turn (a Stop-hook reply after end_turn is a new
#    turn); backgroundTaskId opens a command that a <task-notification> or a
#    TaskStop result retires; Codex task_started/task_complete bracket a turn and
#    item_completed CommandExecution retires a "Process running" session.
check() { n=$((n + 1)); [ "$2" = "$3" ] || fail "$1: expected [$2], got [$3]"; }
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.000Z; }
T=1789650000
SWT=$SCRATCH/ws/state-unit
mkdir -p "$SWT"
CPROJ=$SCRATCH/home/.claude/projects/$(printf '%s' "$SWT" | tr -c 'A-Za-z0-9' '-')
mkdir -p "$CPROJ"
c_prompt() { jq -nc --arg ts "$(iso "$1")" --arg t "$2" '{type:"user",timestamp:$ts,message:{role:"user",content:$t}}'; }
c_meta() { jq -nc --arg ts "$(iso "$1")" --arg t "$2" '{type:"user",isMeta:true,timestamp:$ts,message:{role:"user",content:$t}}'; }
c_compact() { jq -nc --arg ts "$(iso "$1")" --arg t "$2" '{type:"user",isCompactSummary:true,timestamp:$ts,message:{role:"user",content:$t}}'; }
c_say() { jq -nc --arg ts "$(iso "$1")" --arg t "$2" '{type:"assistant",timestamp:$ts,message:{role:"assistant",stop_reason:"end_turn",content:[{type:"text",text:$t}]}}'; }
c_tool() { jq -nc --arg ts "$(iso "$1")" --arg t "$2" --arg bg "${3:-}" '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_1",content:$t}]},toolUseResult:(if $bg == "" then {interrupted:false} else {interrupted:false,backgroundTaskId:$bg} end)}'; }
c_taskstop() { jq -nc --arg ts "$(iso "$1")" --arg id "$2" '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_2",content:("{\"message\":\"Successfully stopped task: " + $id + "\"}")}]},toolUseResult:{task_id:$id,task_type:"local_bash"}}'; }
c_notify() { c_prompt "$1" "<task-notification>
<task-id>$2</task-id>
<status>completed</status>
</task-notification>"; }
# A seat that started work: one tool call, so it is past its first turn.
c_use() { jq -nc --arg ts "$(iso "$1")" '{type:"assistant",timestamp:$ts,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_1",name:"Read",input:{}}]}}'; }
c_done() { jq -nc --arg ts "$(iso "$1")" '{type:"system",subtype:"turn_duration",timestamp:$ts,durationMs:1000}'; }
state() { # now agent task [launched]
  COMMANDECK_NOW=$1 HOME=$SCRATCH/home CODEX_HOME=$SCRATCH/codex PATH="$SCRATCH/bin:$PATH" \
    bash "$SOURCE/scripts/read-verdict.sh" --state --worktree "$SWT" --agent "$2" \
      ${3:+--task "$3"} --launched "${4:-0}" --marker TEST-DONE 2>&1 || true
}
kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }
SESSION=$CPROJ/warm.jsonl

# The u1218 incident shape: a warm session carrying an older assignment and its
# old marker, the new assignment by task id, a compaction summary quoting that
# id, a Stop-hook reply after the first end_turn, and the real turn_duration.
{
  c_prompt "$((T - 900))" "old assignment task_old00000 print TEST-DONE last"
  c_say "$((T - 890))" "old work
TEST-DONE"
  c_done "$((T - 889))"
  c_prompt "$((T - 600))" "Your task ID is: task_new00001. When done print the line TEST-DONE last."
  c_tool "$((T - 590))" "grep hit: TEST-DONE"
  c_compact "$((T - 500))" "Summary: working task_new00001"
  c_say "$((T - 20))" "fixed both
**TEST-DONE**"
  c_meta "$((T - 15))" "Stop hook feedback: tier 1 hit its deadline"
  c_say "$((T - 5))" "Pre-existing deadline, not mine.
TEST-DONE"
  c_done "$T"
} > "$SESSION"
OUT=$(state "$((T + 10))" claude task_new00001)
check "incident: completed turn" complete "$(kv "$OUT" state)"
check "incident: current response ends in the marker" 1 "$(kv "$OUT" marker)"
check "incident: bound to the warm session" "$SESSION" "$(kv "$OUT" session)"
check "incident: idle since the turn_duration" "$T" "$(kv "$OUT" idle_since)"

# Without the final turn_duration the Stop-hook turn is still running.
head -n -1 "$SESSION" > "$SESSION.tmp" && mv "$SESSION.tmp" "$SESSION"
OUT=$(state "$((T + 900))" claude task_new00001)
check "a turn with no turn_duration is running" running "$(kv "$OUT" state)"
check "a running turn is never stalled" 0 "$(kv "$OUT" stalled)"
c_done "$T" >> "$SESSION"

# The old marker, the prompt echo and the tool-output quote are not completion.
{
  c_prompt "$((T - 900))" "old assignment task_old00000"
  c_say "$((T - 890))" "TEST-DONE"
  c_done "$((T - 889))"
  c_prompt "$((T - 600))" "Your task ID is: task_new00002. print TEST-DONE last"
  c_tool "$((T - 590))" "TEST-DONE"
  c_say "$((T - 5))" "Still reading the brief."
  c_done "$T"
} > "$CPROJ/echo.jsonl"
OUT=$(state "$((T + 10))" claude task_new00002)
check "echoed and old markers are not a completion marker" 0 "$(kv "$OUT" marker)"
check "a markerless turn is still complete" complete "$(kv "$OUT" state)"

# The same task id bound in two sessions is ambiguous, never a guess; a task id
# no session holds is unknown.
cp "$CPROJ/echo.jsonl" "$CPROJ/echo-copy.jsonl"
check "a task in two sessions is unknown" unknown "$(kv "$(state "$((T + 10))" claude task_new00002)" state)"
rm -f "$CPROJ/echo-copy.jsonl"
check "a task no session holds is unknown" unknown "$(kv "$(state "$((T + 10))" claude task_absent0)" state)"

# The five-minute line, on a pinned clock: 299 and 300 idle seconds are not a
# stall, 301 is.
check "299s idle is not stalled" 0 "$(kv "$(state "$((T + 299))" claude task_new00002)" stalled)"
check "300s idle is not stalled" 0 "$(kv "$(state "$((T + 300))" claude task_new00002)" stalled)"
OUT=$(state "$((T + 301))" claude task_new00002)
check "301s idle is stalled" 1 "$(kv "$OUT" stalled)"
check "idle seconds are reported" 301 "$(kv "$OUT" idle_seconds)"
# A new turn resets it, however long the session had been idle before.
c_prompt "$((T + 350))" "main: please finish" >> "$CPROJ/echo.jsonl"
check "a new turn resets idle" 0 "$(kv "$(state "$((T + 900))" claude task_new00002)" stalled)"

# A background launch names the file its output goes to; a live command's shell
# holds that file open under the claude process that launched it, which is what
# the reader checks. The fake claude makes that ancestry independent of whether
# this test itself runs under a real claude.
TASKS=$SCRATCH/tasks
mkdir -p "$TASKS" "$SCRATCH/fake"
c_bg() { c_tool "$1" "Command running in background with ID: $2. Output is being written to: $TASKS/$2.output. You will be notified when it completes." "$2"; }
HOLDERS=$SCRATCH/holders
# A copy of bash named claude, not a script: on macOS a script's comm is its
# interpreter's, so the reader's ancestor walk would never find claude.
cp "$(command -v bash)" "$SCRATCH/fake/claude"
unhold() { kill $(cat "$HOLDERS" 2>/dev/null) 2>/dev/null || true; : > "$HOLDERS"; }
trap 'unhold; rm -rf "$SCRATCH"' EXIT
hold() { # id [orphan] -- a process with the id's .output open, under claude unless orphaned
  if [ "${2:-}" = orphan ]; then ( sleep 300 >> "$TASKS/$1.output" & echo $! >> "$HOLDERS" )
  else "$SCRATCH/fake/claude" -c 'sleep 300 >> "$1" & echo $! >> "$2"; wait' claude "$TASKS/$1.output" "$HOLDERS" & fi
  local i; for i in $(seq 50); do { lsof -t "$TASKS/$1.output" || fuser "$TASKS/$1.output"; } >/dev/null 2>&1 && return; sleep 0.1; done
  fail "holder for $1 never opened its output"
}

# Background work outlives end_turn: the turn completes with the command still
# outstanding, so it is neither idle nor stalled until its own completion.
hold bgaaa
hold bgbbb
{
  c_prompt "$((T - 600))" "Your task ID is: task_bg000003"
  c_bg "$((T - 590))" bgaaa
  c_bg "$((T - 580))" bgbbb
  c_say "$((T - 10))" "Waiting on the replay."
  c_done "$T"
} > "$CPROJ/bg.jsonl"
# Read at T+500: past the stall line, and still under the configured age limit.
OUT=$(state "$((T + 500))" claude task_bg000003)
check "background commands survive a completed turn" "bgaaa,bgbbb" "$(kv "$OUT" outstanding)"
check "outstanding background work is not stalled" 0 "$(kv "$OUT" stalled)"
c_taskstop "$((T + 100))" bgaaa >> "$CPROJ/bg.jsonl"
check "TaskStop retires only its own id" bgbbb "$(kv "$(state "$((T + 500))" claude task_bg000003)" outstanding)"
c_notify "$((T + 600))" bgbbb >> "$CPROJ/bg.jsonl"
check "a task-notification opens a new turn" running "$(kv "$(state "$((T + 1000))" claude task_bg000003)" state)"
{ c_say "$((T + 610))" "Replay done."; c_done "$((T + 620))"; } >> "$CPROJ/bg.jsonl"
OUT=$(state "$((T + 1000))" claude task_bg000003)
check "the matching completion clears the last command" "" "$(kv "$OUT" outstanding)"
check "idle starts after both the turn and the last command" "$((T + 620))" "$(kv "$OUT" idle_since)"

# Claude Code also records a completion that lands MID-TURN as a queued_command
# attachment plus queue-operation rows, never as a user prompt. Reading only the
# prompt shape left all four 2026-09-17 builders "outstanding" forever after
# they printed their marker, and their drivers never moved on.
c_queued() { jq -nc --arg ts "$(iso "$1")" --arg id "$2" '("<task-notification>\n<task-id>" + $id + "</task-id>\n<status>completed</status>\n</task-notification>") as $p
  | {type:"queue-operation",operation:"enqueue",timestamp:$ts,content:$p},
    {type:"attachment",timestamp:$ts,attachment:{type:"queued_command",prompt:$p,commandMode:"task-notification"}}'; }
{
  c_prompt "$((T - 600))" "Your task ID is: task_bg000004"
  c_tool "$((T - 590))" "Command did not complete within its 600s timeout and was moved to the background (ID: bgccc)" bgccc
  c_queued "$((T - 300))" bgccc
  c_say "$((T - 10))" "All green.
TEST-DONE"
  c_done "$T"
} > "$CPROJ/bgq.jsonl"
OUT=$(state "$((T + 1000))" claude task_bg000004)
check "a mid-turn queued completion retires its command" "" "$(kv "$OUT" outstanding)"
check "a mid-turn queued completion leaves the marker releasable" 1 "$(kv "$OUT" marker)"

# A background command the log never saw finish is busy only while a process
# under a running claude holds its .output open and it is younger than
# seat-liveness.backgroundMaxMinutes. On 2026-09-22 a spinning test and the loop
# polling its log kept a spent builder "busy" for 42 minutes and vetoed the stall
# and handover paths; both outlived their session as orphans.
MAXMIN=$(jq -r '.["seat-liveness"].backgroundMaxMinutes' "$SOURCE/config/routing.json")
bgdead() { # launch-epoch -- one timed-out call moved to the background, then the turn ends at T
  {
    c_prompt "$(($1 - 10))" "Your task ID is: task_bg000005"
    c_tool "$1" "Command did not complete within its 400s timeout and was moved to the background (ID: bgdead). Output is being written to: $TASKS/bgdead.output. You will be notified when it completes." bgdead
    c_say "$((T - 10))" "Budget spent; handoff written."
    c_done "$T"
  } > "$CPROJ/bgdead.jsonl"
}
bgdead "$((T - 590))"
: > "$TASKS/bgdead.output"
OUT=$(state "$((T + 301))" claude task_bg000005)
check "an unheld .output is not outstanding" "" "$(kv "$OUT" outstanding)"
check "a dead background command does not veto the stall" 1 "$(kv "$OUT" stalled)"
check "idle runs from the turn end" "$T" "$(kv "$OUT" idle_since)"
hold bgdead orphan
OUT=$(state "$((T + 301))" claude task_bg000005)
check "an orphan holder is not outstanding" "" "$(kv "$OUT" outstanding)"
check "an orphan holder does not veto the stall" 1 "$(kv "$OUT" stalled)"
unhold
hold bgdead
OUT=$(state "$((T + 301))" claude task_bg000005)
check "a young command held under claude stays outstanding" bgdead "$(kv "$OUT" outstanding)"
check "a young live command is not stalled" 0 "$(kv "$OUT" stalled)"
check "a young live command is not overdue" "" "$(kv "$OUT" overdue)"
bgdead "$((T - MAXMIN * 60 - 600))"
OUT=$(state "$((T + 301))" claude task_bg000005)
check "a command past the maximum age is overdue" "bgdead:$((MAXMIN + 15))m" "$(kv "$OUT" overdue)"
check "an overdue command is not outstanding" "" "$(kv "$OUT" outstanding)"
check "an overdue command does not veto the stall" 1 "$(kv "$OUT" stalled)"
unhold
rm -f "$TASKS/bgdead.output"
bgdead "$((T - 590))"
check "a missing .output is not outstanding" "" "$(kv "$(state "$((T + 301))" claude task_bg000005)" outstanding)"
check "a missing age limit fails loud" "unknown" "$(kv "$(COMMANDECK_ROUTING=/dev/null state "$((T + 301))" claude task_bg000005)" state)"

# A torn trailing record is unknown, never idle.
printf '{"type":"system","subtype":"turn_dur' >> "$CPROJ/bg.jsonl"
check "a partial record is unknown" unknown "$(kv "$(state "$((T + 1000))" claude task_bg000003)" state)"
check "no session log at all is unknown" unknown "$(kv "$(COMMANDECK_NOW=$T HOME=$SCRATCH/empty bash "$SOURCE/scripts/read-verdict.sh" --state --worktree "$SCRATCH/ws/none" --agent claude --task task_x --marker TEST-DONE || true)" state)"

# Codex: a "Process running" session survives task_complete and is retired by
# its own item_completed; a new task_started is an active turn again.
CX=$SCRATCH/codex/sessions/state-rollout.jsonl
x() { jq -nc --arg ts "$(iso "$1")" --arg cwd "$SWT" --arg v "${3:-}" "$2"; }
{
  x "$((T - 700))" '{timestamp:$ts,type:"session_meta",payload:{type:"session_meta",cwd:$cwd}}'
  x "$((T - 600))" '{timestamp:$ts,type:"event_msg",payload:{type:"task_started",turn_id:"t9"}}'
  x "$((T - 599))" '{timestamp:$ts,type:"response_item",payload:{type:"message",role:"user",content:[{type:"input_text",text:"Your task ID is: task_cx000004"}]}}'
  x "$((T - 500))" '{timestamp:$ts,type:"response_item",payload:{type:"function_call_output",call_id:"c1",output:"Process running with session ID 4242"}}'
  x "$((T - 10))" '{timestamp:$ts,type:"response_item",payload:{type:"message",role:"assistant",content:[{type:"output_text",text:"done\nTEST-DONE"}]}}'
  x "$T" '{timestamp:$ts,type:"event_msg",payload:{type:"task_complete",turn_id:"t9",last_agent_message:"done\nTEST-DONE"}}'
} > "$CX"
OUT=$(state "$((T + 1000))" codex task_cx000004)
check "codex: completed turn with the marker" "complete 1" "$(kv "$OUT" state) $(kv "$OUT" marker)"
check "codex: the running session is outstanding" 4242 "$(kv "$OUT" outstanding)"
x "$((T + 50))" '{timestamp:$ts,type:"event_msg",payload:{type:"item_completed",item:{type:"CommandExecution",process_id:"4242",status:"completed",exit_code:0}}}' >> "$CX"
OUT=$(state "$((T + 351))" codex task_cx000004)
check "codex: completion after the final turn retires the session" "" "$(kv "$OUT" outstanding)"
check "codex: idle from that completion" "1 $((T + 50))" "$(kv "$OUT" stalled) $(kv "$OUT" idle_since)"
x "$((T + 400))" '{timestamp:$ts,type:"event_msg",payload:{type:"task_started",turn_id:"t10"}}' >> "$CX"
check "codex: a new task_started is running" running "$(kv "$(state "$((T + 1000))" codex task_cx000004)" state)"

# A seat binds by its launch record: the first session to start after launch.
rm -f "$CPROJ"/*.jsonl
{ c_prompt "$((T - 100))" "reviewer seat A"; c_say "$((T - 90))" "VERDICT: GO"; c_done "$((T - 89))"; } > "$CPROJ/a.jsonl"
{ c_prompt "$((T + 5))" "reviewer seat B"; c_say "$((T + 20))" "Reading."; c_done "$((T + 30))"; } > "$CPROJ/b.jsonl"
OUT=$(state "$((T + 40))" claude "" "$T")
check "a seat binds to the session that started after its launch" "$CPROJ/b.jsonl" "$(kv "$OUT" session)"
check "no launch and no task binds nothing" unknown "$(kv "$(state "$((T + 40))" claude "" 0)" state)"

# 5. seat.sh wait uses the same state. A Claude seat that completed with its
#    marker is released from the log alone; one idle past five minutes without
#    it stops with route=stalled, its full pane and task ids and a resume.
# Any read-only role the real routing.json runs on claude.
CROLE=certifier
cat > "$SCRATCH/seat-$UNIT-$CROLE.txt" <<EOF
handle=term_fin
task=task_seat00005
role=$CROLE
unit=$UNIT
launched=$T
spec=$SCRATCH/spec.md
EOF
rm -f "$CPROJ"/*.jsonl
run_seat_wait() { # now timeout
  PATH="$SCRATCH/bin:$PATH" COMMANDECK_SCRATCH="$SCRATCH" FAKE_WT="$SWT" HOME="$SCRATCH/home" \
  CODEX_HOME="$SCRATCH/codex" COMMANDECK_WORKSPACES="$SCRATCH/ws" COMMANDECK_NOW="$1" \
  COMMANDECK_LOOP_POLL_SECONDS=1 \
  bash "$SOURCE/scripts/seat.sh" wait "$CROLE" state-unit --marker PLAN-DONE --timeout-s "$2" 2>&1
}
mkdir -p "$SCRATCH/ws/state-unit"
cp "$SCRATCH/seat-$UNIT-$CROLE.txt" "$SCRATCH/seat-state-unit-$CROLE.txt"
{ c_prompt "$((T + 5))" "Your task spec is the file $SCRATCH/spec.md. review; print PLAN-DONE last"; c_say "$((T + 20))" "All read.
PLAN-DONE"; c_done "$((T + 30))"; } > "$CPROJ/seat.jsonl"
OUT=$(run_seat_wait "$((T + 40))" 5) || fail "a seat whose log holds its completed marker was not released: $OUT"
n=$((n + 1))
{ c_prompt "$((T + 5))" "Your task spec is the file $SCRATCH/spec.md. review; print PLAN-DONE last"; c_use "$((T + 10))"; c_say "$((T + 20))" "I need a ruling first."; c_done "$((T + 30))"; } > "$CPROJ/seat.jsonl"
OUT=$(run_seat_wait "$((T + 331))" 2) && fail "a stalled seat was released"
n=$((n + 1))
grep -q "route=stalled" <<<"$OUT" || fail "no stalled STOP line; got: $OUT"
grep -q "pane=term_fin task=task_seat00005" <<<"$OUT" || fail "the STOP line lost the pane or task id; got: $OUT"
grep -q "seat.sh collect $CROLE state-unit" <<<"$OUT" || fail "the STOP line has no resume command; got: $OUT"
n=$((n + 3))
OUT=$(run_seat_wait "$((T + 330))" 2) && fail "wait returned success at exactly 300s idle"
grep -q "route=stalled" <<<"$OUT" && fail "300s idle stopped as stalled; got: $OUT"
n=$((n + 1))

# ORCA 1.4.220 (2026-10-04). Its terminals export CODEX_HOME as Orca's own
# runtime home -- a path with a space -- and every driver inherits it, while the
# seats still write to ~/.codex. The reader narrowed its search to that home,
# found no session, and both plan-author waits hung on finished panes. Its pane
# reads keep no history either: `--cursor 0` returns one empty line and only the
# screen has text. Captured shapes, contents trimmed.
cat > "$SCRATCH/bin/orca-ide" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = terminal ] && [ "${2:-}" = list ]; then echo "term_fin  the companion pane"; exit 0; fi
if [ "${1:-}" = terminal ] && [ "${2:-}" = read ]; then
  case " $* " in
    *" --screen "*) jq -nc --arg s "$FAKE_SCREEN" '{id:"r1",ok:true,result:{terminal:{handle:"term_fin",status:"running",tail:($s | split("\n")),truncated:false,limited:false,oldestCursor:"0",nextCursor:"1",latestCursor:"1",returnedLineCount:($s | split("\n") | length),source:"screen"}},_meta:{runtimeId:"rt"}}' ;;
    *) echo '{"id":"r2","ok":true,"result":{"terminal":{"handle":"term_fin","status":"running","tail":[""],"truncated":false,"limited":false,"oldestCursor":"0","nextCursor":"1","latestCursor":"1","returnedLineCount":1,"source":"stream"}},"_meta":{"runtimeId":"rt"}}' ;;
  esac
  exit 0
fi
exit 0
EOF
chmod +x "$SCRATCH/bin/orca-ide"
U220=fake-220 L220=$T ORCA_HOME="$SCRATCH/Application Support/orca/codex-runtime-home/home"
mkdir -p "$SCRATCH/ws/$U220" "$ORCA_HOME/sessions" "$SCRATCH/home/.codex/sessions"
printf 'handle=term_fin\ntask=task_220\nrole=companion\nunit=%s\nlaunched=%s\nspec=%s\nprompt=%s\n' \
  "$U220" "$L220" "$SCRATCH/spec.md" "$SCRATCH/spec.md" > "$SCRATCH/seat-$U220-companion.txt"
SPEC_LINE="› Your task spec is the file $SCRATCH/spec.md. print PLAN-DONE on its own final line"
# The plan author was a Codex seat then; it later moved to Claude, so pin it.
jq "$(cat "$SOURCE/scripts/__tests__/fixtures/routing-seats.jq")"' | .roles["companion"] = {agent: "codex", model: "gpt-6.1-sol", effort: "high", sandbox: "workspace-write", edits: true}' \
  "$SOURCE/config/routing.json" > "$SCRATCH/routing-220.json"
run_220() { # timeout
  PATH="$SCRATCH/bin:$PATH" COMMANDECK_SCRATCH="$SCRATCH" HOME="$SCRATCH/home" CODEX_HOME="$ORCA_HOME" COMMANDECK_ROUTING="$SCRATCH/routing-220.json" \
  COMMANDECK_WORKSPACES="$SCRATCH/ws" COMMANDECK_LOOP_POLL_SECONDS=1 \
  bash "$SOURCE/scripts/seat.sh" wait companion "$U220" --marker PLAN-DONE --timeout-s "$1" 2>&1
}
# a. The finished seat's log is in ~/.codex while CODEX_HOME names Orca's home.
{
  printf '{"timestamp":"%s","type":"session_meta","payload":{"type":"session_meta","cwd":"%s"}}\n' "$(iso "$((L220 + 4))")" "$SCRATCH/ws/$U220"
  printf '{"timestamp":"%s","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Your task spec is the file %s."}]}}\n' "$(iso "$((L220 + 4))")" "$SCRATCH/spec.md"
  printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}\n' "$(iso "$((L220 + 5))")"
  printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1","last_agent_message":"Created the brief and the map.\\nPLAN-DONE"}}\n' "$(iso "$((L220 + 600))")"
} > "$SCRATCH/home/.codex/sessions/rollout-220.jsonl"
OUT=$(FAKE_SCREEN="$SPEC_LINE" run_220 5) \
  || fail "1.4.220: a finished seat whose log is in ~/.codex was not seen under Orca's CODEX_HOME: $OUT"
grep -q "marker PLAN-DONE up on term_fin (session log)" <<<"$OUT" || fail "1.4.220: not released from the session log; got: $OUT"
n=$((n + 2))
# b. No session log at all: the marker on the rendered screen, with the agent's
#    gutter, releases the wait once the pane idles; the spec's prose never does.
rm -f "$SCRATCH/home/.codex/sessions/rollout-220.jsonl"
OUT=$(FAKE_SCREEN="$SPEC_LINE" run_220 4) && fail "1.4.220: the spec's prose naming the marker released the wait: $OUT"
n=$((n + 1))
SCREEN_DONE="$(printf '%s\n' "  >_ OpenAI Codex (v0.160.0)" "$SPEC_LINE" "• Created the brief and the map." "  PLAN-DONE" "› Ask Codex to do anything" "  GPT-6.1-Sol high fast · $U220 · Context 95% left")"
OUT=$(FAKE_SCREEN="$SCREEN_DONE" run_220 15) || fail "1.4.220: PLAN-DONE on the screen did not release the wait: $OUT"
grep -q "marker PLAN-DONE up on term_fin" <<<"$OUT" || fail "1.4.220: no release line; got: $OUT"
n=$((n + 2))
# c. A pane that echoes its prompt shows the prompt's own marker line. While the
#    echo is up that line is not the answer; once the echo has scrolled away the
#    one marker left on the screen is, and the wait must not sit on it.
REC220=$SCRATCH/seat-$U220-companion.txt
printf 'Write the plan.\nWhen it is written, print:\nPLAN-DONE\n' > "$SCRATCH/echoed.md"
sed -i "s|^prompt=.*|prompt=$SCRATCH/echoed.md|" "$REC220"
SCREEN_ECHO="$(printf '%s\n' "  Write the plan." "  When it is written, print:" "  PLAN-DONE" "• Reading the code." "› Ask Codex to do anything")"
OUT=$(FAKE_SCREEN="$SCREEN_ECHO" run_220 4) && fail "the prompt's echoed marker released the wait: $OUT"
# An answer may repeat the prompt's own closing block, line above included. The
# echo accounts for one such marker; the second is the answer.
SCREEN_REPEAT="$(printf '%s\n' "  Write the plan." "  When it is written, print:" "  PLAN-DONE" "• Wrote the plan." "  When it is written, print:" "  PLAN-DONE" "› Ask Codex to do anything")"
OUT=$(FAKE_SCREEN="$SCREEN_REPEAT" run_220 15) || fail "an answer repeating the prompt's closing block did not release the wait: $OUT"
n=$((n + 1))
SCREEN_SCROLLED="$(printf '%s\n' "• Created the brief and the map." "  PLAN-DONE" "› Ask Codex to do anything")"
OUT=$(FAKE_SCREEN="$SCREEN_SCROLLED" run_220 15) || fail "the final marker did not release the wait once the echoed prompt had scrolled away: $OUT"
sed -i "s|^prompt=.*|prompt=$SCRATCH/spec.md|" "$REC220"
# d. Another repo's unit of the same name and role is another seat: it must not
#    read (and then close) this repo's record.
OUT=$(COMMANDECK_SEAT_REPO=other-repo FAKE_SCREEN="$SCREEN_SCROLLED" run_220 4) && fail "another repo's unit was served this repo's seat record: $OUT"
# A unit of THIS repo may be named "<that repo>.<unit>": its record is not the other repo's either.
cp "$REC220" "$SCRATCH/seat-other-repo.$U220-companion.txt"
OUT=$(COMMANDECK_SEAT_REPO=other-repo FAKE_SCREEN="$SCREEN_SCROLLED" run_220 4) && fail "another repo's unit was served the record of this repo's unit other-repo.$U220: $OUT"
grep -q "no seat record at $SCRATCH/seat-other-repo@$U220-companion.txt" <<<"$OUT" || fail "another repo's seat record is not kept apart; got: $OUT"
rm -f "$SCRATCH/seat-other-repo.$U220-companion.txt"
OUT=$(PATH="$SCRATCH/bin:$PATH" COMMANDECK_SCRATCH="$SCRATCH" COMMANDECK_WORKSPACES="$SCRATCH/ws" bash "$SOURCE/scripts/seat.sh" wait companion "other-repo@$U220" --marker PLAN-DONE 2>&1) \
  && fail "a unit name holding the repo separator was accepted: $OUT"
grep -q "unit name" <<<"$OUT" || fail "the refusal of a unit name with @ does not say so; got: $OUT"
n=$((n + 4))
# e. WORKER STATE is the seat's own session's. Two seats share a worktree; the
#    sibling started first after this seat's launch and has finished. The seat
#    is still working, and a driver told "complete" would collect it mid-turn.
SWT2=$SCRATCH/ws/state-two; CPROJ2=$SCRATCH/home/.claude/projects/$(printf '%s' "$SWT2" | tr -c 'A-Za-z0-9' '-')
mkdir -p "$SWT2" "$CPROJ2"
{ c_prompt "$((T + 2))" "Your task spec is the file $SCRATCH/sibling.md."; c_say "$((T + 20))" "done
TEST-DONE"; c_done "$((T + 21))"; } > "$CPROJ2/sibling.jsonl"
{ c_prompt "$((T + 4))" "Your task spec is the file $SCRATCH/own.md."; c_use "$((T + 30))"; } > "$CPROJ2/own.jsonl"
ST2=$(COMMANDECK_NOW=$((T + 40)) HOME=$SCRATCH/home PATH="$SCRATCH/bin:$PATH" bash "$SOURCE/scripts/read-verdict.sh" --state \
  --worktree "$SWT2" --agent claude --launched "$T" --marker TEST-DONE --spec "$SCRATCH/own.md" 2>&1 || true)
[ "$(kv "$ST2" state)" = running ] || fail "a sibling's finished session answered for a seat still working; got: $ST2"
n=$((n + 1))

# 6. THE RECORD NAMES WHAT THE WAIT SAW (wake-dedup). A finished wait leaves
#    waiting-<handle> so the turn-complete hooks and main-watch do not wake main
#    again for the same turn (pp_waited_on matches the line). A wait for
#    PLAN-DONE that the pane answers only with a verdict is released by that
#    verdict, so the record must name the verdict, or the hook reading
#    `VERDICT: NO-GO` within five minutes cannot match it and wakes main twice.
grep -qE '^seen [0-9]+ PLAN-DONE$' "$SCRATCH/waiting-term_fin" \
  || fail "a wait released by PLAN-DONE did not record it; got: $(cat "$SCRATCH/waiting-term_fin" 2>&1)"
SCREEN_VERDICT="$(printf '%s\n' "$SPEC_LINE" "• Findings above." "  VERDICT: NO-GO" "› Ask Codex to do anything")"
OUT=$(FAKE_SCREEN="$SCREEN_VERDICT" run_220 15) || fail "a verdict on the screen did not release the wait: $OUT"
grep -qE '^seen [0-9]+ VERDICT: NO-GO$' "$SCRATCH/waiting-term_fin" \
  || fail "a wait released by a verdict recorded another line; got: $(cat "$SCRATCH/waiting-term_fin" 2>&1)"
( COMMANDECK_SCRATCH=$SCRATCH; . "$SOURCE/scripts/paths.sh" >/dev/null 2>&1
  pp_waited_on term_fin "" "$(printf 'Findings above.\nVERDICT: NO-GO')" ) \
  || fail "the hook's turn text cannot match the verdict the wait saw"
n=$((n + 4))

echo "PASS seat-wait-finished-pane: $n assertions"
