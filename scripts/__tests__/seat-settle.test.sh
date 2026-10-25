#!/usr/bin/env bash
# seat-settle.test.sh -- seat.sh collect settles a seat's task only when its pane reads idle and no question it asked
# since its launch is still unanswered in the question's own thread (host issue 2998). A working pane, an open question
# and any check that cannot be read all refuse: collect closes no pane, writes no verdict=, and exits 4 with the rerun
# line; the rerun that finds the pane idle and the question answered settles the task once. The setup is
# fixtures/seat-setup.sh (ps-working makes Orca report the pane mid-turn; inbox.json is the inbox).
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

touch "$T/ps-working"; col
check "settle refused while the Builder pane works: exit 4, the rerun line, no task closed, the pane kept, no verdict=" "4:2:0:yes:0" \
  "$RC:$(grep -c 'not settled' "$T/out"):$(closes):$([ -e "$T/pane-up" ] && echo yes || echo no):$(grep -c '^verdict=' "$REC")"
rm "$T/ps-working"

ask | inbox; col
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
check "a reply in the thread lets it settle: exit 0, the task closed once, the pane closed, the verdict recorded" "0:1:no:1" \
  "$RC:$(closes):$([ -e "$T/pane-up" ] && echo yes || echo no):$(grep -c '^verdict=VERDICT: GO' "$REC")"
check "the record says the task is settled" "1" "$(grep -c '^settled=task_1$' "$REC")"
col
check "a rerun closes no task a second time" "1" "$(closes)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
