#!/usr/bin/env bash
# seat-settle.test.sh -- seat.sh collect settles a seat's task once its report holds the verdict, whatever the pane's
# live state (issue 631: a finished seat's pane can still read working, and refusing it stopped unit-drive.sh). It still
# refuses while a question the seat asked since its launch is unanswered in the question's own thread (host issue 2998),
# and while that check cannot be read: collect closes no pane, writes no verdict=, and exits 4 with the rerun line; the
# rerun that finds the question answered settles the task once. No verdict in the report settles nothing (exit 3). The
# setup is fixtures/seat-setup.sh (ps-working makes Orca report the pane mid-turn; inbox.json is the inbox).
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"

unset COMMANDECK_DRIVER CLAUDECODE
col() { touch "$T/pane-up"; COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run collect builder seat-builder >"$T/out" 2>&1; RC=$?; }
closes() { grep -c '^orchestration task-update' "$T/updates" 2>/dev/null || echo 0; }
COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch builder seat-builder "$T/spec.md" >"$T/out" 2>&1
REC=$(ls "$HOME/.commandeck/scratch/"*/seat-seat-builder-builder.txt)
printf 'Done.\nVERDICT: GO\n' > "$T/screen"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ask() { jq -nc --arg at "$NOW" '{messages: [{id: "msg_q1", type: "question", from_handle: "h1", thread_id: null, created_at: $at}]}'; }
inbox() { jq -c '{ok: true, result: .}' > "$T/inbox.json"; }

# The pane reads working throughout: only the report and the open question decide.
touch "$T/ps-working"
printf 'Working on it.\n' > "$T/screen"; col
check "no verdict in the report: exit 3, no task closed, the pane kept, no verdict=" "3:0:yes:0" \
  "$RC:$(closes):$([ -e "$T/pane-up" ] && echo yes || echo no):$(grep -c '^verdict=' "$REC")"
printf 'Done.\nVERDICT: GO\n' > "$T/screen"

ask | inbox; col
check "a working pane with an open question is refused: exit 4, the rerun line, the pane kept" "4:1:0:yes:0" \
  "$RC:$(grep -c 'Rerun:' "$T/out"):$(closes):$([ -e "$T/pane-up" ] && echo yes || echo no):$(grep -c '^verdict=' "$REC")"
check "settle refused while its question has no reply in its thread: exit 4, the answer command names the question" "4:1:0:0" \
  "$RC:$(grep -c 'answer-worker.sh h1 .* msg_q1' "$T/out"):$(closes):$(grep -c '^verdict=' "$REC")"

echo 'not json' > "$T/inbox.json"; col
check "an unreadable inbox refuses" "4:0:0" "$RC:$(closes):$(grep -c '^verdict=' "$REC")"

# A reply in the question's own thread answers it; a message elsewhere does not.
jq -nc --arg at "$NOW" '{messages: [{id: "msg_q1", type: "question", from_handle: "h1", thread_id: null, created_at: $at},
  {id: "msg_s1", type: "status", from_handle: "term_main", thread_id: null, created_at: $at}]}' | inbox; col
check "a message outside the question's thread leaves it open" "4:0" "$RC:$(closes)"
jq -nc --arg at "$NOW" '{messages: [{id: "msg_q1", type: "question", from_handle: "h1", thread_id: null, created_at: $at},
  {id: "msg_r1", type: "status", from_handle: "term_main", thread_id: "msg_q1", created_at: $at}]}' | inbox; col
check "a reply in the thread lets the working pane's verdict settle: exit 0, the task closed once, the pane closed, the verdict recorded" "0:1:no:1" \
  "$RC:$(closes):$([ -e "$T/pane-up" ] && echo yes || echo no):$(grep -c '^verdict=VERDICT: GO' "$REC")"
check "the record says the task is settled" "1" "$(grep -c '^settled=task_1$' "$REC")"
col
check "a rerun closes no task a second time" "1" "$(closes)"
# Issue 647: a finding written as `**F2 (P2):**` reaches collect's summary, as `[P2]` does.
printf '**F2 (P2):** cite the bold line\nVERDICT: GO\n' > "$T/screen"; col
check "collect summary shows bold P2 finding" 1 "$(grep -c 'F2 (P2):\*\* cite the bold line' "$T/out")"
printf 'Done.\nVERDICT: GO\n' > "$T/screen"
# Issues 637 and 636, on pp_task_close itself: a seat record for task_cb on pane h1, launched before the inbox's rows.
ptc() { touch "$T/pane-up"; (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH PATH="$BIN:$PATH" \
  bash -c '. "$1/scripts/paths.sh" && pp_task_close task_cb completed' _ "$REAL" 2>"$T/ptc.err"); echo $?; }
printf 'handle=h1\ntask=task_cb\nrole=builder\nunit=cb\nlaunched=%s\n' "$(( $(date +%s) - 120 ))" > "${REC%/*}/seat-cb-builder.txt"
tc() { jq -nc --arg at "$NOW" --arg s "$1" '{messages: [{id: "msg_t1", type: "question", from_handle: "h1", thread_id: null, created_at: $at, subject: $s}]}' | inbox; }
rm -f "$T/ps-working"; tc "claude turn complete (cb)"
check "issue 637: turn-complete question settles a finished seat" 0 "$(ptc)"
tc "claude turn complete: QUESTION (cb)"
check "issue 637: a turn-complete QUESTION note still holds the settle" "1 1" "$(ptc) $(grep -c 'open question msg_t1' "$T/ptc.err")"
# Issue 660: a row whose text holds a lone surrogate escape made jq refuse the whole inbox, so every settle read
# "cannot tell" and refused a finished seat. The row is cleaned, not dropped: the turn-complete note still reads.
printf '%s\n' '{"ok":true,"result":{"messages":[{"id":"msg_t1","type":"question","from_handle":"h1","thread_id":null,"created_at":"'"$NOW"'","subject":"claude turn complete (cb)","body":"done \ud83d cut"}]}}' > "$T/inbox.json"
check "settle reads an inbox with lone surrogate" 0 "$(ptc)"
echo '{"ok":true,"result":{"messages":[]}}' > "$T/inbox.json"; touch "$T/ps-working"
check "issue 636: working pane refusal names the pane" "1 1 0" \
  "$(ptc) $(grep -c 'its pane h1 is working, or its state could not be read' "$T/ptc.err") $(grep -c 'inbox' "$T/ptc.err")"
rm -f "$T/ps-working"; echo 'not json' > "$T/inbox.json"
check "issue 636: an unreadable open-question check is named apart from the pane" "1 1 0" \
  "$(ptc) $(grep -c 'the open-question check for pane h1 could not be read' "$T/ptc.err") $(grep -c 'is working' "$T/ptc.err")"
echo '{"ok":true,"result":{"messages":[]}}' > "$T/inbox.json"; touch "$T/ps-working"; rm -f "${REC%/*}/seat-cb-builder.txt"

# Issue 598: main revises a plan author whose pane still reads working once its latest answer holds its finish. The
# author's record is on the same pane; the Builder's record is gone, so every read is the author's own.
# author [revised] -- a fresh plan-author record (its last wait kept marker=PLAN-DONE), revised to task_2 when asked.
PREC=${REC%/*}/seat-seat-builder-plan-author.txt; rm -f "$REC"; LA=$(( $(date +%s) - 120 ))
author() { printf 'handle=h1\ntask=%s\nrole=plan-author\nunit=seat-builder\nworktree=seat-builder\nlaunched=%s\nmarker=PLAN-DONE\nphase=dispatched\n%s' \
  "${1:-task_1}" "$LA" "${1:+revised=$1$'\n'}" > "$PREC"; rm -f "$T/updates" "$T/sent"; touch "$T/pane-up"; }
sent() { cat "$T/sent" 2>/dev/null | grep -c .; }
rev() { run revise plan-author seat-builder "Change section 2." >"$T/out" 2>&1; RC=$?; }
echo '{"ok":true,"result":{"messages":[]}}' > "$T/inbox.json"; touch "$T/ps-working"
author; printf 'Plan written.\nPLAN-DONE\n' > "$T/screen"; rev
check "seat.sh revise on a seat whose latest answer ends on its marker sends the revision though its pane reads working" "0:1:1" \
  "$RC:$(closes):$(grep -c '^revised=' "$PREC")"
author; cp "$PREC" "$T/before"; printf 'Still writing section 3.\n' > "$T/screen"; rev
check "seat.sh revise on a seat whose pane reads working with no finish in its latest answer is still refused" "2:1:0:same" \
  "$RC:$(grep -c 'no finish in its latest answer' "$T/out"):$(closes):$(cmp -s "$PREC" "$T/before" && echo same || echo changed)"
author; cp "$PREC" "$T/before"; printf 'Plan written.\nPLAN-DONE\n' > "$T/screen"
jq -nc --arg at "$NOW" '{messages: [{id: "msg_q2", type: "question", from_handle: "h1", thread_id: null, created_at: $at}]}' | inbox; rev
check "seat.sh revise on a finished seat with an open question is still refused and sends nothing" "1:0:0:same" \
  "$RC:$(closes):$(sent):$(cmp -s "$PREC" "$T/before" && echo same || echo changed)"
echo '{"ok":true,"result":{"messages":[]}}' > "$T/inbox.json"
# A revised seat: its session log's latest answer is the previous task's PLAN-DONE until the prompt naming task_2 lands.
LOGD=$HOME/.claude/projects/$(printf '%s' "$SWT" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$LOGD"
row() { jq -cn --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg k "$1" --arg x "$2" \
  'if $k == "user" then {type: "user", timestamp: $t, message: {content: $x}} else {type: "assistant", timestamp: $t, message: {content: [{type: "text", text: $x}]}} end'; }
{ row user 'Your task spec is the file p. Task id task_1.'; row assistant $'Plan written.\nPLAN-DONE'; } > "$LOGD/s1.jsonl"
printf 'Working.\n' > "$T/screen"; author task_2; cp "$PREC" "$T/before"; rev
check "seat.sh revise on a revised seat whose revised prompt has not landed is refused though the old answer ends on PLAN-DONE" "2:1:0:0:same" \
  "$RC:$(grep -c 'revised prompt not landed' "$T/out"):$(closes):$(sent):$(cmp -s "$PREC" "$T/before" && echo same || echo changed)"
{ row user 'Change section 1. When you have done this, send worker_done. Task id task_2.'; row assistant $'Revised.\nPLAN-DONE'; } >> "$LOGD/s1.jsonl"
author task_2; rev
check "seat.sh revise on a revised seat whose revised prompt landed and whose answer ends on PLAN-DONE sends the revision" "0:1" "$RC:$(closes)"
rm -f "$T/ps-working" "$LOGD/s1.jsonl"

# Issue 630: seat.sh close ends a collected seat whose pane stayed open: its open task settles and its pane closes.
author; printf 'verdict=PLAN-DONE\n' >> "$PREC"; run close plan-author seat-builder >"$T/out" 2>&1; RC=$?
check "seat.sh close settles a collected seat's open task and closes its live pane" "0:1:gone:1:1" \
  "$RC:$(closes):$([ -e "$T/pane-up" ] && echo live || echo gone):$(grep -c '^settled=task_1$' "$PREC"):$(grep -cx 'closed seat=plan-author unit=seat-builder PLAN-DONE' "$T/out")"
author; printf 'verdict=PLAN-DONE\nrevised=task_1\n' >> "$PREC"; run close plan-author seat-builder >"$T/out" 2>&1; RC=$?
check "seat.sh close on a seat with no recorded verdict closes nothing and names collect" "3:0:live:1" \
  "$RC:$(closes):$([ -e "$T/pane-up" ] && echo live || echo gone):$(grep -c 'seat.sh collect plan-author seat-builder' "$T/out")"

# Pass 7: Orca refusing a pane close (it can answer ok:false with exit 0) is no closed seat. close-refuses wraps the
# fixture's stand-in so `terminal close` is refused and the pane stays up; every other call reaches the stand-in.
mv "$BIN/orca-ide" "$BIN/orca-ide-stand-in"
printf '#!/usr/bin/env bash\nif [ -e %q ] && [ "$1 $2" = "terminal close" ]; then echo %q; exit 0; fi\nexec %q "$@"\n' \
  "$T/close-refuses" '{"ok":false,"error":{"message":"CLOSE-REFUSED"}}' "$BIN/orca-ide-stand-in" > "$BIN/orca-ide"; chmod +x "$BIN/orca-ide"
touch "$T/close-refuses"
author; printf 'verdict=PLAN-DONE\n' >> "$PREC"; run close plan-author seat-builder >"$T/out" 2>&1; RC=$?
R1="$RC:$(grep -c 'closed seat=' "$T/out"):$(grep -c 'pane h1 did not close.*CLOSE-REFUSED' "$T/out"):$([ -e "$T/pane-up" ] && echo live || echo gone):$(grep -c '^settled=task_1$' "$PREC")"
# The same refusal when collect ends a seat: the verdict is read and settled, so it is recorded, but collect says the pane
# is open, names seat.sh close and exits 5; on-go does not run.
rm -f "$PREC"
CREC=${REC%/*}/seat-seat-builder-certifier.txt
printf 'handle=h1\ntask=task_9\nrole=certifier\nunit=seat-builder\nworktree=seat-builder\nlaunched=%s\nphase=dispatched\n' "$LA" > "$CREC"
printf 'Done.\nVERDICT: GO\n' > "$T/screen"; touch "$T/pane-up"
COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run collect certifier seat-builder --on-go "touch $T/on-go-ran" >"$T/out" 2>&1; RC=$?
R2="$RC:$(grep -c '^verdict=VERDICT: GO' "$CREC"):$(grep -c 'closed seat=' "$T/out"):$(grep -c 'seat.sh close certifier seat-builder' "$T/out"):$([ -e "$T/pane-up" ] && echo live || echo gone):$([ -e "$T/on-go-ran" ] && echo yes || echo no)"
# Issue 604's rerun: a plan judge's recorded verdict with its pane still live; the rerun's close refused is no closed seat.
JREC=${REC%/*}/seat-seat-builder-plan-judge-sol.txt
printf 'handle=h1\ntask=task_8\nrole=plan-judge-sol\nunit=seat-builder\nworktree=seat-builder\nlaunched=%s\nphase=dispatched\nverdict=VERDICT: GO\n' "$LA" > "$JREC"
printf 'Idle.\n' > "$T/screen"; touch "$T/pane-up"
COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run collect plan-judge-sol seat-builder >"$T/out" 2>&1; RC=$?
R3="$RC:$(grep -c 'closed seat=' "$T/out"):$(grep -c 'seat.sh close plan-judge-sol seat-builder' "$T/out")"
rm -f "$T/close-refuses"
COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run collect plan-judge-sol seat-builder >"$T/out" 2>&1; RC=$?
R4="$RC:$(grep -c 'closed seat=plan-judge-sol unit=seat-builder VERDICT: GO' "$T/out"):$([ -e "$T/pane-up" ] && echo live || echo gone)"
check "a pane close Orca refuses is no closed seat: seat.sh close, collect and its rerun exit 5 naming seat.sh close, collect records the verdict and runs no on-go, and the rerun closes once Orca takes it" \
  "5:0:1:live:1 5:1:0:1:live:no 5:0:1 0:1:gone" "$R1 $R2 $R3 $R4"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
