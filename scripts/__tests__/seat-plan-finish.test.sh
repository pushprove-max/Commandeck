#!/usr/bin/env bash
# timeout: 240
# seat-plan-finish.test.sh -- seat.sh's plan seats (issue 320), on the hand-written commandeck.json of fixtures/seat-setup.sh.
# What this pins: a plan author's turn that ended on a question, a refusal or a failure message is not a finish, however
# much else it left (a commit, a 'Plan revised' message); a live or unknowable background command is not one either;
# collect sends main one report per finish; and an ordinary clean finish of each seat type raises no stall alert.
# Split from seat-plan-marker.test.sh, which holds the earlier cases, to keep both files inside their time budget.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"
printf 'Judge the plan.\nEnd on a line of its own.\n' > "$T/judge-spec.md"

# Issue 320: a planner that finished by its own message or a fresh plan commit, never printing PLAN-DONE, read as
# stalled and kept its pane. Each planner below was prompted 900 s ago and ended its turn 600 s ago, so its wait is at
# the idle limit; what it left (a message, a commit) is dated 700 s ago, inside that turn and before the wait starts:
# the latest prompt bounds the episode, never the wait's own start.
RWT=$HOME/orca/workspaces/proj/pr; git -C "$PROJ" worktree add -q "$RWT" && echo pr > "$(git -C "$RWT" rev-parse --absolute-git-dir)/commandeck-plan-of"
RPS=$HOME/.claude/projects/$(printf '%s' "$RWT" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$RPS"; NOW=$(date +%s)
rrec() { ls "$HOME/.commandeck/scratch/"*/"seat-pr-$1.txt"; }
rlog() { local r; r=$(rrec "$1"); echo "$RPS/s-$1-$(sed -n 's/^tag=//p' "$r").jsonl"; }
at() { jq -rn --argjson t "$1" '$t | todate'; }
idle() { # <role> <last words> [earlier block] -- the seat's session: one turn, prompted 900 s ago, its tool call, its last words, ended 600 s ago;
  # an earlier block is the same reply's first text record (Claude Code writes one record per block, under one message id)
  local r; r=$(rrec "$1"); sed -i "s/^launched=.*/launched=$((NOW - 1000))/" "$r"
  jq -cn --arg p "$(at $((NOW - 900)))" --arg t "$(at $((NOW - 600)))" --arg tag "$(sed -n 's/^tag=//p' "$r")" --arg w "$2" --arg e "${3:-}" '
    {type: "user", timestamp: $p, message: {role: "user", content: "Your task spec. Seat tag \($tag)."}},
    {type: "assistant", timestamp: $t, message: {content: [{type: "tool_use", id: "u1", name: "Read", input: {}}]}},
    if $e == "" then empty else {type: "assistant", timestamp: $t, message: {id: "m1", content: [{type: "text", text: $e}]}} end,
    {type: "assistant", timestamp: $t, message: {id: "m1", content: [{type: "text", text: $w}]}},
    {type: "system", subtype: "turn_duration", timestamp: $t}' > "$(rlog "$1")"; }
followup() { # <role> [ended] -- main types a follow-up 400 s ago; with `ended`, that turn ended 350 s ago with no marker
  jq -cn --arg p "$(at $((NOW - 400)))" --arg t "$(at $((NOW - 350)))" --arg e "${2:-}" '
    {type: "user", timestamp: $p, message: {role: "user", content: "Also cover the rollback in section 4."}},
    if $e == "" then empty else {type: "assistant", timestamp: $t, message: {content: [{type: "text", text: "Looking at section 4."}]}},
    {type: "system", subtype: "turn_duration", timestamp: $t} end' >> "$(rlog "$1")"; }
said() { # <to> <subject> <body> [epoch] [type] [read] -- the seat's one message in Orca's inbox
  jq -nc --arg to "$1" --arg s "$2" --arg b "$3" --argjson at "${4:-$((NOW - 700))}" --arg ty "${5:-worker_done}" --argjson rd "${6:-0}" \
    '{ok: true, result: {messages: [{from_handle: "h1", to_handle: $to, type: $ty, subject: $s, body: $b, read: $rd, created_at: ($at | todate)}]}}' > "$T/inbox.json"; }
rlaunch() { rm -f "$T/pane-up" "$T/inbox.json"; COMMANDECK_SEAT_FORCE=1 srun launch "$1" pr "$2" >"$T/out" 2>&1 || echo "launch $1: $(tail -2 "$T/out")"; }
rwait() { srun wait "$1" pr --marker PLAN-DONE --timeout-s 20 >"$T/out" 2>&1; }
commit_plan() { echo "$1" > "$RWT/.claude/plans/pr.md"; git -C "$RWT" add .claude/plans/pr.md
  GIT_COMMITTER_DATE="@${2:-$((NOW - 700))} +0000" git -C "$RWT" -c user.name=t -c user.email=t@t commit -qm plan; }
printf 'Launch: new unit pr\nPlan the unit.\nEnd on a line of its own.\n' > "$T/pr-spec.md"; mkdir -p "$RWT/.claude/plans"
# A turn that ends on a question or a refusal has not finished, whatever else the seat left: a committed plan and a
# 'Plan revised' message are evidence of work, not of an answer to what it asks. The turn's own last words decide; the
# next turn, with no ask in it, is read afresh (no state: the claim and marker are removed between the two reads).
for w in 'PLAN-BLOCKED'; do
  rlaunch plan-author "$T/pr-spec.md"; idle plan-author "$w"; commit_plan "the plan under '$w'"
  srun collect plan-author pr >"$T/out" 2>&1; check "a committed plan, the turn ending '$w': collect keeps the pane open" 3 $?
  said run:run-1 'Plan revised: pr' 'See the plan file.'; rm -f "$HOME/.commandeck/scratch/"*/waiting-h1; sed -i '/^marker=/d' "$(rrec plan-author)"
  srun collect plan-author pr >"$T/out" 2>&1; check "and with its 'Plan revised' message too: collect keeps the pane open" 3 $?
  idle plan-author 'Plan written.'; rm -f "$HOME/.commandeck/scratch/"*/waiting-h1; sed -i '/^marker=/d' "$(rrec plan-author)"
  srun collect plan-author pr >"$T/out" 2>&1
  check "and once the next turn ends with no ask, the commit and the message close it on PLAN-DONE" '0:1' "$?:$(grep -c 'closed seat=plan-author unit=pr PLAN-DONE' "$T/out")"
done
# The ask may sit in an earlier text block of the same reply, under one message id: the whole reply is read, not its last block.
rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'The draft is committed for your inspection.' 'BLOCKED: rollback needs an owner ruling.'; commit_plan 'the plan under an earlier block'
srun collect plan-author pr >"$T/out" 2>&1; check "a committed plan, the ask in the reply's earlier text block: collect keeps the pane open" 3 $?
rwait plan-author; check "and wait stops stalled" '1:1' "$?:$(grep -c 'route=stalled' "$T/out")"
idle plan-author 'The draft is committed for your inspection.' 'Starting the last section.'; rm -f "$HOME/.commandeck/scratch/"*/waiting-h1; sed -i '/^marker=/d' "$(rrec plan-author)"
srun collect plan-author pr >"$T/out" 2>&1
check "and with no ask in any block, the next collect closes it on PLAN-DONE" '0:1' "$?:$(grep -c 'closed seat=plan-author unit=pr PLAN-DONE' "$T/out")"
# The seat's own message that reports a failure vetoes every branch, the plan commit included, whatever its subject says
# and whatever its last reply reads; an inbox that does not answer finishes nothing. Each read goes again: with the
# failure gone and the inbox answering in full pages, the next collect closes the pane.
rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'See my status message.'; commit_plan 'the plan under a failure message'
for to_body in run:run-1/PLAN-BLOCKED run:run-1/'**VERDICT:  NO-GO**' term_main/PLAN-BLOCKED; do
  said "${to_body%%/*}" 'Plan revised: rollback pending' "${to_body#*/}"
  srun collect plan-author pr >"$T/out" 2>&1; check "a committed plan and a 'Plan revised' message to ${to_body%%/*} with the body '${to_body#*/}': collect keeps the pane open" 3 $?
done
echo '{"ok":false}' > "$T/inbox.json"; srun collect plan-author pr >"$T/out" 2>&1
check "the inbox not answering, the plan committed: collect keeps the pane open" 3 $?
# The inbox is read newest first, 500 at a time: a full page that stops short of the prompt may hide a failure message.
page() { jq -nc --argjson n "$NOW" --argjson old "$1" '{ok: true, result: {messages: [range(0; 500) | {from_handle: "other", to_handle: "run:run-1", type: "status", subject: "x", body: "", read: 1, created_at: (($n - 100 - .) | todate)}] | .[499].created_at = (($n - $old) | todate)}}' > "$T/inbox.json"; }
page 100; srun collect plan-author pr >"$T/out" 2>&1
check "a full inbox page that stops after the prompt, the plan committed: collect keeps the pane open" 3 $?
page 5000; srun collect plan-author pr >"$T/out" 2>&1
check "and a full page that reaches back before the prompt, no failure message in it, closes it on PLAN-DONE" '0:1' "$?:$(grep -c 'closed seat=plan-author unit=pr PLAN-DONE' "$T/out")"
# A turn that ended with its background command still running has not finished: neither its report nor its plan
# commit is its finish. The command's .output is held by a child of a stand-in claude (a copy of bash), as
# read-verdict.sh requires of a live background command; with the holder gone, the same seat is finished.
cp "$(command -v bash)" "$T/claude"; ( "$T/claude" -c 'sleep 60 3>>"$1"; :' _ "$T/b123.output" </dev/null >/dev/null 2>&1 & echo $! > "$T/bgpid" )
rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'Plan written.'; commit_plan 'the background plan'
jq -nc --arg t "$(at $((NOW - 650)))" --arg o "$T/b123.output" '{type: "user", timestamp: $t, toolUseResult: {stdout: "", backgroundTaskId: "b123"},
  message: {role: "user", content: [{type: "tool_result", tool_use_id: "u1", content: "Running in background. Output is being written to: \($o)"}]}}' >> "$(rlog plan-author)"
said run:run-1 'Plan written: pr' 'PLAN-DONE'; echo 'Plan written.' > "$T/screen"; sleep 0.3
srun collect plan-author pr >"$T/out" 2>&1
check "a turn that ended with its background command still held: collect keeps the pane open, though its plan is committed and reported" 3 $?
pkill -P "$(cat "$T/bgpid")"; kill "$(cat "$T/bgpid")" 2>/dev/null; sleep 0.3
rwait plan-author; check "plan author, its background command finished (holder gone), plan committed and reported: wait exits 0, no stall alert" '0:0' "$?:$(grep -c 'route=stalled' "$T/out")"
srun collect plan-author pr >"$T/out" 2>&1; check "and once the command's holder is gone, collect closes it on PLAN-DONE" '0:1' "$?:$(grep -c 'closed seat=plan-author unit=pr PLAN-DONE' "$T/out")"
# When neither lsof nor fuser answers, a live background command cannot be told from a dead one (state=unknown): not
# a finish either. The next read retries from the session log alone: with the wait's claim and marker removed between
# the two collects, the second closes the pane once the tools answer and the command's .output is unheld.
mkdir -p "$T/noholders"; printf '#!/usr/bin/env bash\necho "$0: refused" >&2; exit 2\n' > "$T/noholders/lsof"
cp "$T/noholders/lsof" "$T/noholders/fuser"; chmod +x "$T/noholders/lsof" "$T/noholders/fuser"; : > "$T/b124.output"
rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'Plan written.'; commit_plan 'the unknown-liveness plan'
jq -nc --arg t "$(at $((NOW - 650)))" --arg o "$T/b124.output" '{type: "user", timestamp: $t, toolUseResult: {stdout: "", backgroundTaskId: "b124"},
  message: {role: "user", content: [{type: "tool_result", tool_use_id: "u1", content: "Running in background. Output is being written to: \($o)"}]}}' >> "$(rlog plan-author)"
said run:run-1 'Plan written: pr' 'PLAN-DONE'; echo 'Plan written.' > "$T/screen"
PATH="$T/noholders:$PATH" srun collect plan-author pr >"$T/out" 2>&1
check "neither lsof nor fuser answers for its background command: collect keeps the pane open, though its plan is committed and reported" 3 $?
rm -f "$HOME/.commandeck/scratch/"*/waiting-h1; sed -i '/^marker=/d' "$(rrec plan-author)"
srun collect plan-author pr >"$T/out" 2>&1
check "and with the wait's claim and marker removed, the next collect closes it on PLAN-DONE once the tools answer" '0:1' "$?:$(grep -c 'closed seat=plan-author unit=pr PLAN-DONE' "$T/out")"
# Issue 321: collect sends main one report per finish. main_collect runs as main does, in its own foreground.
main_collect() { (export COMMANDECK_RUN=run-1 CLAUDECODE=1; unset COMMANDECK_FOREGROUND COMMANDECK_DRIVER; seat_sh collect plan-author pr --marker PLAN-DONE) >"$T/out" 2>&1; }
sends() { grep -c 'orchestration send' "$T/wakes" 2>/dev/null || true; }
rlaunch plan-author "$T/pr-spec.md"; echo PLAN-DONE > "$T/screen"; rm -f "$HOME/.commandeck/scratch/"*/waiting-h1; : > "$T/wakes"
main_collect; check "collect sends nothing for a finish no wait claimed" '0:0' "$?:$(sends)"
rlaunch plan-author "$T/pr-spec.md"; echo PLAN-DONE > "$T/screen"; rwait plan-author; : > "$T/wakes"
main_collect; check "a finish a wait claimed is sent once" '0:1' "$?:$(sends)"
rlaunch plan-author "$T/pr-spec.md"; idle plan-author PLAN-DONE; echo PLAN-DONE > "$T/screen"; rwait plan-author; said run:run-1 'Plan written: pr' 'PLAN-DONE' $(($(date +%s) + 1)); : > "$T/wakes"
main_collect; check "collect sends nothing for a finish the seat reported itself" '0:0' "$?:$(sends)"
# A report of a type wakeKinds holds (status), unread, has not reached main: the finish is still owed, and collect
# sends it once. Read, it has reached main, and collect sends nothing.
for rd in 0 1; do
  rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'Plan saved.'; echo 'Plan saved.' > "$T/screen"
  said run:run-1 'Plan revised: pr' 'Plan saved.' $((NOW - 700)) status $rd; rwait plan-author; : > "$T/wakes"; main_collect
  check "a 'Plan revised' status note (read: $rd) and a markerless turn end: collect closes the pane and sends $((1 - rd))" "0:$((1 - rd))" "$?:$(sends)"
done
# A final reply that is failure text (a verdict line here) outweighs every earlier sign of a finish, a message the seat sent
# before it and a plan commit alike: the turn's own last words decide. Its last reply benign again, the same seat is finished.
rlaunch plan-author "$T/pr-spec.md"; idle plan-author $'Revision rejected.\nVERDICT: NO-GO'; said run:run-1 'Plan revised: pr' 'Plan saved.' $((NOW - 750))
srun collect plan-author pr >"$T/out" 2>&1; check "an earlier 'Plan revised' message and a final reply ending VERDICT: NO-GO: collect keeps the pane open" 3 $?
rm -f "$T/inbox.json"; commit_plan 'the plan under a final NO-GO'
srun collect plan-author pr >"$T/out" 2>&1; check "a plan commit and a final reply ending VERDICT: NO-GO: collect keeps the pane open" 3 $?
idle plan-author 'Plan saved.'
srun collect plan-author pr >"$T/out" 2>&1; check "and with the final reply benign, the next collect closes it on PLAN-DONE" '0:1' "$?:$(grep -c 'closed seat=plan-author unit=pr PLAN-DONE' "$T/out")"
# A finish sent to main's own pane (to-main.sh's address, which differs from the run's coordinator) is a finish: main's
# pane is looked up at the time of asking. With main's pane not listed the message is to an unknown address and the seat
# stays unfinished; with it listed, the next collect closes the pane (nothing else between the two reads changes).
rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'Plan saved.'; echo 'Plan saved.' > "$T/screen"; rm -f "$T/extra"
said term_main 'Plan revised: pr' 'Plan saved.' '' status 1
srun collect plan-author pr >"$T/out" 2>&1; check "a read 'Plan revised' note to term_main, main's pane not listed: collect keeps the pane open" 3 $?
printf '{"handle":"term_main","agentIdentity":"claude","connected":true,"worktreePath":"%s"}' "$PROJ" > "$T/extra"
srun collect plan-author pr >"$T/out" 2>&1; check "and with main's pane listed, the next collect closes it on PLAN-DONE" '0:1' "$?:$(grep -c 'closed seat=plan-author unit=pr PLAN-DONE' "$T/out")"
rm -f "$T/extra"
# A judge's own message never stands in for its VERDICT line.
rlaunch plan-judge-sol "$T/judge-spec.md"; idle plan-judge-sol 'Judging the plan.'; said run:run-1 'Plan revised: judged' 'VERDICT: GO'
srun wait plan-judge-sol pr --marker 'VERDICT: GO' --timeout-s 20 >"$T/out" 2>&1
check "a judge's own message does not stand in for its verdict" '1:1' "$?:$(grep -c 'route=stalled' "$T/out")"
# Main's ruling 1: an ordinary clean finish of each seat type raises no stall alert, whatever else these cases make strict.
rlaunch plan-author "$T/pr-spec.md"; idle plan-author $'Plan complete.\nPLAN-DONE'; echo PLAN-DONE > "$T/screen"; rwait plan-author
check "plan author, a plain PLAN-DONE ending with no commit or message: wait exits 0, no stall alert" '0:0' "$?:$(grep -c 'route=stalled' "$T/out")"
rlaunch plan-author "$T/pr-spec.md"; commit_plan 'a clean plan'; idle plan-author 'Plan written.'; echo 'Plan written.' > "$T/screen"; rwait plan-author
check "plan author, the plan committed and clean, no marker or message, nothing running: wait exits 0, no stall alert" '0:0' "$?:$(grep -c 'route=stalled' "$T/out")"
rlaunch plan-judge-sol "$T/judge-spec.md"; idle plan-judge-sol $'Judged.\nVERDICT: GO'; echo 'VERDICT: GO' > "$T/screen"
srun wait plan-judge-sol pr --marker 'VERDICT: GO' --timeout-s 20 >"$T/out" 2>&1
check "plan judge, a plain VERDICT: GO ending: wait exits 0, no stall alert" '0:0' "$?:$(grep -c 'route=stalled' "$T/out")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
