#!/usr/bin/env bash
# orca-wait.sh decides which messages are worth a turn of main's context. Every
# message it prints costs main a full context replay, and every message it drops
# is one main never hears about, so both directions are load-bearing and neither
# is visible from the outside: a filter that silently keeps everything looks
# exactly like a filter that works.
#
# The rule under test is that a seat's own report is the DRIVER's business while
# that driver is alive. On 2026-09-15 main was woken twice by one implementer
# finishing -- once by its escalation, once by its worker_done -- and had
# nothing to do with either, because the driver had already dispatched the
# review round off the same report.
#
# orca-ide and systemctl are stubbed on PATH; the script is copied into a
# throwaway repo so its ROOT holds no read-verdict.sh to shell out to. Same
# stubbing convention the other driver self-tests use.
set -euo pipefail

SOURCE=$(git rev-parse --show-toplevel)
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
fail() { echo "FAIL: $*" >&2; [ -z "${OUT:-}" ] || printf 'output was:\n%s\n' "$OUT" >&2; exit 1; }

REPO=$SCRATCH/repo
mkdir -p "$REPO/scripts" "$SCRATCH/bin" "$SCRATCH/ws"
git -C "$REPO" init -q
cp "$SOURCE/scripts/orca-wait.sh" "$SOURCE/scripts/paths.sh" "$SOURCE/scripts/project-main.sh" "$SOURCE/scripts/requirements.sh" "$SOURCE/scripts/host-services.sh" "$REPO/scripts/"
mkdir -p "$REPO/hooks/lib"; cp "$SOURCE/hooks/lib/project.sh" "$REPO/hooks/lib/"
export COMMANDECK_HOST_OS=Linux  # the systemctl stubs are the service manager under test

# wt-alpha has a live driver; wt-beta and wt-gamma do not.
cat > "$SCRATCH/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
# NODRIVER=1 is the same machine after that driver died.
case " $* " in *" list-units "*) [ -z "${DONE_FIRST:-}" ] || for n in 1 2 3 1 2 3 1 2 3; do echo "drive-wt-done$n-1789434$RANDOM.service loaded inactive dead driver"; done
  [ -n "${NODRIVER:-}" ] || echo "drive-wt-alpha-1789434098.service loaded active running driver"
  [ -z "${STOPPED:-}" ] || echo "● ${STOPPED_NAME:-drive-wt-delta-1789434099}.service loaded ${STOPPED_STATE:-failed failed} driver"
  [ -z "${FIXTURE:-}" ] || printf 'drive-wt-done%s-178943410%s.service loaded inactive dead driver\n' 1 1 2 2 3 3 ;; esac
SYSTEMCTL

# The batch in $BATCH, then an empty one so the ack loop settles; a blocking
# wait finds nothing. Bodies carry no marker except where a case needs one, to
# keep enrich out of the way. NOTERMS=1 is a pane listing that fails, so no
# sender maps to a worktree.
cat > "$SCRATCH/bin/orca-ide" <<'ORCA'
#!/usr/bin/env bash
echo "$*" >> "$CALLS"
case "$1 $2" in
  "terminal list") [ -z "${NOTERMS:-}" ] || exit 1 ;;
esac
case "$1 $2" in
  "orchestration run-current") echo '{"result":{"run":{"id":"run_test"}}}'; exit 0 ;;
  "orchestration run-use") exit 0 ;;
  "orchestration task-list") if [ -n "${FAKE_TASKS:-}" ]; then echo "$FAKE_TASKS"; else echo '{"result":{"tasks":[]}}'; fi; exit 0 ;;
  "orchestration gate-list") echo '{"result":{"gates":[]}}'; exit 0 ;;
  "orchestration task-update") echo '{"ok":true}'; exit 0 ;;
  "terminal list")
    cat <<'EOF'
{"result":{"terminals":[
  {"handle":"term_alpha_seat","worktreePath":"WSDIR/wt-alpha","agentIdentity":"claude"},
  {"handle":"term_beta_seat","worktreePath":"WSDIR/wt-beta","agentIdentity":"claude"},
  {"handle":"term_gamma_seat","worktreePath":"WSDIR/wt-gamma","agentIdentity":"claude"},
  {"handle":"term_u_seat","worktreePath":"WSDIR/u","agentIdentity":"claude"},
  {"handle":"term_main","worktreePath":"MAINDIR","agentIdentity":"claude"}
]}}
EOF
    exit 0 ;;
esac
case " $* " in
  *" --ack "*) echo '{"result":{"messages":[],"deliveryId":null}}'; exit 0 ;;
  *" --wait "*) sleep 0.2; echo '{"result":{"messages":[],"deliveryId":null}}'; exit 0 ;;
esac
cat "$BATCH"
ORCA
cat > "$SCRATCH/batch.main" <<'EOF'
{"result":{"deliveryId":"d1","messages":[
  {"id":"m1","type":"heartbeat","from_handle":"term_alpha_seat","subject":"alive","body":""},
  {"id":"m2","type":"worker_done","from_handle":"term_alpha_seat","subject":"SUPPRESS driven worker report","body":"implemented the thing"},
  {"id":"m3","type":"worker_done","from_handle":"term_beta_seat","subject":"KEEP undriven worker report","body":"implemented the thing"},
  {"id":"m4","type":"escalation","from_handle":"term_alpha_seat","subject":"KEEP driven escalation","body":"blocked on a decision"},
  {"id":"m5","type":"question","from_handle":"term_main","subject":"drive wt-alpha: merge-ready","body":"route=merge-ready"},
  {"id":"m6","type":"question","from_handle":"term_alpha_seat","subject":"codex turn complete (wt-alpha)","body":"VERDICT: GO"},
  {"id":"m7","type":"question","from_handle":"term_gamma_seat","subject":"codex turn complete (wt-gamma)","body":"VERDICT: GO"},
  {"id":"m8","type":"question","from_handle":"term_main","subject":"seat brief-reviewer wt-alpha: SUPPRESS driven seat verdict","body":"VERDICT: NO-GO"},
  {"id":"m9","type":"question","from_handle":"term_main","subject":"seat brief-reviewer wt-beta: KEEP undriven seat verdict","body":"VERDICT: GO"},
  {"id":"m10","type":"question","from_handle":"term_main","subject":"drive wt-alpha SUPPRESS wrapper exit rc=1","body":"tail of the same log"},
  {"id":"m11","type":"question","from_handle":"term_main","subject":"STOP unit=wt-alpha round=1 route=main-read next=KEEP loop stop","body":"the loop stopped"},
  {"id":"m12","type":"question","from_handle":"term_main","subject":"drive wt-alpha: FYI SUPPRESS code review round 2 started on abc","body":"x"},
  {"id":"m13","type":"question","from_handle":"term_main","subject":"drive wt-beta: FYI SUPPRESS class raised","body":"x"}
]}}
EOF
sed -i "s|WSDIR|$SCRATCH/ws|g; s|MAINDIR|$REPO|g" "$SCRATCH/bin/orca-ide"
chmod +x "$SCRATCH/bin/orca-ide" "$SCRATCH/bin/systemctl"

waiter() {  # waiter <batch file> -- calls land in $SCRATCH/calls
  rm -f "$SCRATCH/calls"; rm -rf "$SCRATCH/scratch"
  (cd "$REPO" && BATCH=$1 CALLS=$SCRATCH/calls PATH=$SCRATCH/bin:$PATH COMMANDECK_WORKSPACES=$SCRATCH/ws \
    COMMANDECK_SCRATCH=$SCRATCH/scratch HOME=$SCRATCH \
    bash scripts/orca-wait.sh --run run_test "${@:2}" 2>/dev/null)
}

OUT=$(waiter "$SCRATCH/batch.main") \
  || fail "orca-wait exited non-zero on a batch that holds messages to print"

# 1. THE RULE. A seat's worker_done while its driver is alive is the driver's
#    input, not main's: the driver dispatches the next stage off that same
#    report and wakes main at its own judgment point.
case $OUT in *"SUPPRESS driven worker report"*)
  fail "a driven unit's worker_done still woke main" ;; esac

# 2. The same report with NO driver watching is the only signal there is.
#    Dropping it strands a finished worker forever.
case $OUT in *"KEEP undriven worker report"*) ;; *)
  fail "an undriven unit's worker_done was dropped; nothing else would report it" ;; esac

# 3. An escalation is a seat asking for a decision its driver cannot make. It
#    passes even while that driver is alive, or a blocked unit waits on a
#    seat timeout instead of on main.
case $OUT in *"KEEP driven escalation"*) ;; *)
  fail "a driven unit's escalation was dropped; only main can answer one" ;; esac

# 4. The driver's own wake carries the stage main acts on. It is sent from the
#    MAIN pane handle, which sits in the checkout and not a worktree, so it
#    must never be classified as a seat message.
case $OUT in *"drive wt-alpha: merge-ready"*) ;; *)
  fail "the driver's own wake was filtered out as if a seat had sent it" ;; esac

# 5. Pre-existing rule, guarded here because this change rewrites its predicate:
#    a pane's turn-complete echo is noise while a driver watches that unit, even
#    carrying a verdict, and is the only signal when no driver does.
case $OUT in *"(wt-alpha)"*) fail "a driven unit's turn-complete echo woke main" ;; esac
case $OUT in *"(wt-gamma)"*) ;; *)
  fail "an undriven unit's turn-complete echo was dropped" ;; esac

# 6. seat.sh announces EVERY seat verdict, and it sends from the driver's own
#    handle -- which sits in the checkout, so rule 1 in this file cannot see it.
#    A driver wakes main at its own judgment points, so while one is alive this
#    is the same outcome a second time. On 2026-09-15 one batch carried five of
#    them and main could act on none.
case $OUT in *"SUPPRESS driven seat verdict"*)
  fail "a driven unit's seat verdict woke main; its driver reports that itself" ;; esac

# 7. The same line with no driver watching is the only report of that seat.
case $OUT in *"KEEP undriven seat verdict"*) ;; *)
  fail "an undriven unit's seat verdict was dropped; nothing else would report it" ;; esac

# 8. loop-run.sh's wrapper sends a second wake when the driver process ends,
#    carrying only the tail of the log the driver's own wake already explained.
#    Safe to drop only because a driver that dies sending nothing leaves a done
#    file main-watch.sh posts (main-watch.test.sh).
case $OUT in *"SUPPRESS wrapper exit rc"*)
  fail "the wrapper's exit wake woke main on top of the driver's own wake" ;; esac

# 9. A loop that STOPS replaces that subject with its route, and that is the
#    line main acts on. Dropping it strands a unit waiting to be merged.
case $OUT in *"KEEP loop stop"*) ;; *)
  fail "a loop stop was dropped; main is the only thing that can route one" ;; esac

# 9b. A driver FYI (round started, class raised, fixes needed) needs nothing
#     from main, driven or not: the driver keeps going and its log keeps the
#     line (owner ruling 2026-10-01). Half of main's wakes on 2026-09-30 were these.
case $OUT in *"FYI SUPPRESS"*)
  fail "a driver FYI woke main; it is driver-log content, not a decision" ;; esac

# 10. SELF-TEST TRAFFIC. The harness runs a fake unit named exactly `u` from
#     two recorded panes; its wakes reached main all through 2026-09-16 and
#     every checkpoint had to say to ignore them. Every subject form an emitter
#     uses is here, and none may print. The recorded panes stay suppressed after
#     they vanish from the pane listing, and so do the subject forms.
cat > "$SCRATCH/batch.harness" <<'EOF'
{"result":{"deliveryId":"d2","messages":[
  {"id":"h1","type":"question","from_handle":"term_main","subject":"seat implementer on u: settled","body":"VERDICT: GO"},
  {"id":"h2","type":"question","from_handle":"term_main","subject":"seat brief-reviewer u: NO-GO","body":"x"},
  {"id":"h3","type":"question","from_handle":"term_main","subject":"drive u: merge-ready","body":"x"},
  {"id":"h4","type":"question","from_handle":"term_x","subject":"codex turn complete (u)","body":"VERDICT: GO"},
  {"id":"h5","type":"question","from_handle":"term_main","subject":"STOP unit=u round=1 route=main-read next=x","body":"x"},
  {"id":"h6","type":"worker_done","from_handle":"term_impl","subject":"u: all four cuts green","body":"x"},
  {"id":"h7","type":"question","from_handle":"term_sol","subject":"u round 2","body":"x"},
  {"id":"h8","type":"escalation","from_handle":"term_3d8255b5","subject":"blocked on a decision","body":"x"},
  {"id":"h9","type":"worker_done","from_handle":"term_1c94009f","subject":"implemented the thing","body":"x"}
]}}
EOF
for terms in listed missing; do
  OUT=$(NOTERMS=$([ $terms = missing ] && echo 1) waiter "$SCRATCH/batch.harness") \
    && fail "a batch of only self-test traffic woke main (panes $terms)"
  case $OUT in *" | "*) fail "self-test traffic was printed (panes $terms)" ;; esac
  grep -q -- '--ack d2' "$SCRATCH/calls" || fail "self-test traffic was not acknowledged and will replay (panes $terms)"
done

# 11. Real news beside self-test traffic still arrives, including units whose
#     names start with u, a question, and a body that talks about self-tests.
cat > "$SCRATCH/batch.mixed" <<'EOF'
{"result":{"deliveryId":"d3","messages":[
  {"id":"x1","type":"worker_done","from_handle":"term_u_seat","subject":"SUPPRESS harness pane report","body":"x"},
  {"id":"x2","type":"question","from_handle":"term_main","subject":"drive u: SUPPRESS harness driver","body":"x"},
  {"id":"x3","type":"question","from_handle":"term_main","subject":"drive wt-alpha: KEEP driver wake","body":"x"},
  {"id":"x4","type":"escalation","from_handle":"term_alpha_seat","subject":"KEEP driven escalation","body":"x"},
  {"id":"x5","type":"question","from_handle":"term_beta_seat","subject":"KEEP undriven question","body":"which fixture?"},
  {"id":"x6","type":"worker_done","from_handle":"term_beta_seat","subject":"KEEP self-test mention","body":"the u self-test from term_3d8255b5 passed"},
  {"id":"x7","type":"question","from_handle":"term_main","subject":"seat implementer on u1209-attempt-heartbeat: KEEP settled","body":"x"},
  {"id":"x8","type":"question","from_handle":"term_main","subject":"drive u1209-attempt-heartbeat: KEEP u-prefixed unit","body":"x"}
]}}
EOF
for terms in listed missing; do
  OUT=$(NOTERMS=$([ $terms = missing ] && echo 1) waiter "$SCRATCH/batch.mixed") \
    || fail "a mixed batch did not wake main (panes $terms)"
  for k in "KEEP driver wake" "KEEP driven escalation" "KEEP undriven question" "KEEP self-test mention" "KEEP settled" "KEEP u-prefixed unit"; do
    case $OUT in *"$k"*) ;; *) fail "'$k' was dropped beside self-test traffic (panes $terms)" ;; esac
  done
  case $OUT in *"SUPPRESS harness driver"*) fail "a harness driver wake printed beside real news" ;; esac
  # Only a listed pane can be traced to the u worktree; its subject names no unit.
  [ $terms = missing ] || case $OUT in *"SUPPRESS harness pane report"*)
    fail "a report from a pane in the u worktree printed" ;; esac
done

# 12. A driven seat's report suppressed while its driver lives must still
#     surface once that driver is gone and the delivery comes round again.
cat > "$SCRATCH/batch.late" <<'EOF'
{"result":{"deliveryId":"d4","messages":[
  {"id":"late1","type":"worker_done","from_handle":"term_alpha_seat","subject":"LATE driven worker report","body":"x"}
]}}
EOF
OUT=$(waiter "$SCRATCH/batch.late") && fail "a driven seat's worker_done woke main"
OUT=$(NODRIVER=1 waiter "$SCRATCH/batch.late") \
  || fail "a suppressed report did not surface after its driver died"
case $OUT in *"LATE driven worker report"*) ;; *)
  fail "a report filtered while driven is lost once its driver is gone" ;; esac

# 13. main-watch.sh's post for a driver that died is kept, even though its
#     subject ends like the wrapper's exit wake in case 8.
cat > "$SCRATCH/batch.watch" <<'EOF'
{"result":{"deliveryId":"d5","messages":[
  {"id":"w1","type":"question","from_handle":"term_main","subject":"main-watch: wt-alpha stopped: drive wt-alpha exit rc=1","body":"x"}
]}}
EOF
OUT=$(waiter "$SCRATCH/batch.watch") || fail "main-watch's post of a dead driver was dropped"

# 14. A stopped driver arrives with its log tail and a NEEDS-MAIN line naming
#     the next step, so main acts on the wake instead of opening the log. With
#     a STOP route the line is that route; without one it says to relaunch.
#     The tail is --full's; the terse wake keeps only the NEEDS-MAIN line.
stopped() {  # stopped <log text> [orca-wait args] -- the waiter with a failed wt-delta driver
  rm -f "$SCRATCH/calls"; rm -rf "$SCRATCH/scratch"; mkdir -p "$SCRATCH/scratch/scratchpad"
  printf '%s\n' "$1" > "$SCRATCH/scratch/scratchpad/wt-delta-drive-1.log"
  (cd "$REPO" && BATCH=$SCRATCH/batch.watch CALLS=$SCRATCH/calls STOPPED=1 PATH=$SCRATCH/bin:$PATH \
    COMMANDECK_WORKSPACES=$SCRATCH/ws COMMANDECK_SCRATCH=$SCRATCH/scratch HOME=$SCRATCH \
    bash scripts/orca-wait.sh --run run_test "${@:2}" 2>/dev/null)
}
ROUTED=$(printf 'line one\nSTOP unit=wt-delta round=2 route=main-read next=scripts/merge-unit-local.sh wt-delta\nTAIL-2\nTAIL-3')
OUT=$(stopped "$ROUTED" --full)
for k in "STOP unit=wt-delta" TAIL-2 TAIL-3 "NEEDS-MAIN: wt-delta stopped with a route; run: scripts/merge-unit-local.sh wt-delta"; do
  case $OUT in *"$k"*) ;; *) fail "a stopped driver's --full wake lacks '$k'" ;; esac
done
case $OUT in *"line one"*) fail "the stopped driver's tail printed more than 3 lines" ;; esac
OUT=$(stopped "$ROUTED")
case $OUT in *"NEEDS-MAIN: wt-delta stopped with a route; run: scripts/merge-unit-local.sh wt-delta"*) ;; *)
  fail "the terse wake dropped a stopped driver's route; main would open the log for it" ;; esac
case $OUT in *TAIL-2*) fail "the terse wake printed a stopped driver's log tail" ;; esac
OUT=$(stopped "crashed: unbound variable")
case $OUT in *"NEEDS-MAIN: wt-delta driver failed without a STOP route; read tail -3 "*) ;; *)
  fail "a routeless stopped driver's terse line does not say which log to read" ;; esac
OUT=$(stopped "crashed: unbound variable" --full)
case $OUT in *"NEEDS-MAIN: wt-delta driver failed without a STOP route; read the tail above"*) ;; *)
  fail "a routeless stopped driver has no NEEDS-MAIN line under --full" ;; esac
# A driver that finished cleanly stays listed as inactive on the Mac until the
# next launch boots it out; its DONE line is news under --full, never a NEEDS-MAIN.
OUT=$(STOPPED_STATE="inactive dead" stopped "$(printf 'STEP 5 cleanup\nDONE unit=wt-delta merged=local sha=abc12345')" --full)
case $OUT in *"DONE unit=wt-delta"*) ;; *) fail "a finished driver's --full wake lacks its DONE line" ;; esac
case $OUT in *"NEEDS-MAIN: wt-delta"*) fail "a driver that finished cleanly asks main for a relaunch" ;; esac
# A unit whose NAME holds the word `dead` is listed like any other: the state
# column never says dead (the awk keeps name and ACTIVE only), so a word filter
# on the line could only ever hide a unit by its name.
rm -rf "$SCRATCH/scratch"; mkdir -p "$SCRATCH/scratch/scratchpad"
printf 'STOP unit=dead-code round=1 route=main-read next=RUN-THIS\n' > "$SCRATCH/scratch/scratchpad/dead-code-drive-1.log"
OUT=$(cd "$REPO" && BATCH=$SCRATCH/batch.watch CALLS=$SCRATCH/calls STOPPED=1 STOPPED_NAME=drive-dead-code-1789434100 \
  PATH=$SCRATCH/bin:$PATH COMMANDECK_WORKSPACES=$SCRATCH/ws COMMANDECK_SCRATCH=$SCRATCH/scratch HOME=$SCRATCH \
  bash scripts/orca-wait.sh --run run_test 2>/dev/null)
case $OUT in *"NEEDS-MAIN: dead-code stopped with a route; run: RUN-THIS"*) ;; *)
  fail "a stopped driver whose unit name holds 'dead' was hidden from the state block" ;; esac
# Under a C locale systemctl's bullet is three bytes, not one character; a strip
# of one leading character left two and shifted every column (2026-10-01 merge).
OUT=$(LC_ALL=C stopped "$ROUTED" --full)
case $OUT in *"NEEDS-MAIN: wt-delta stopped with a route; run: scripts/merge-unit-local.sh wt-delta"*) ;; *)
  fail "under LC_ALL=C the bullet's leftover bytes hid a stopped driver's route" ;; esac

# 14b. A STOPPED DRIVER WHOSE UNIT ALREADY MERGED. settings-versions-1978 was
#      merged as a feat(<unit>) commit while its driver's STOP line still
#      named a merge to run; the wake kept telling main to merge it again.
#      Only a feat(<unit>) commit made AFTER the stop retires the line.
git -C "$REPO" symbolic-ref HEAD refs/heads/main
commit_at() {  # commit_at <subject> <epoch>
  GIT_AUTHOR_DATE="$2 +0000" GIT_COMMITTER_DATE="$2 +0000" git -C "$REPO" -c user.name=t -c user.email=t@t \
    commit -q --allow-empty -m "$1"
}
commit_at "feat(wt-delta): implement unit" 1000000000
OUT=$(stopped "$ROUTED")
case $OUT in *"NEEDS-MAIN: wt-delta"*) ;; *) fail "a merge from BEFORE the stop retired its NEEDS-MAIN line" ;; esac
commit_at "feat(wt-delta): implement unit" 4000000000
OUT=$(stopped "$ROUTED")
case $OUT in *"NEEDS-MAIN: wt-delta"*) fail "a unit already merged on main still told main to merge it" ;; esac
OUT=$(stopped "crashed: unbound variable" --full)
case $OUT in *"NEEDS-MAIN: wt-delta"*) fail "a merged unit's routeless stop still asked for a relaunch" ;; esac
git -C "$REPO" reset -q --hard HEAD~1
commit_at "feat(wt-delta-other): implement unit" 4000000001
OUT=$(stopped "$ROUTED")
case $OUT in *"NEEDS-MAIN: wt-delta"*) ;; *) fail "another unit's feat commit retired this unit's NEEDS-MAIN line" ;; esac

# 14c. THE FULL BODY SURVIVES THE 200-CHARACTER SUMMARY. Each printed message
#      names a file holding its whole body (newlines, quotes, tabs intact),
#      written before the acknowledgement.
LONGB=$(printf 'z%.0s' {1..260})
jq -n --arg long "$LONGB" '{result:{deliveryId:"d7", messages:[
  {id:"msg-full-1", type:"question", from_handle:"term_main", subject:"KEEP long ask",
   body:("line \"one\"\nit'"'"'s line two\n\ttabbed " + $long + " TAIL-MARK")}]}}' > "$SCRATCH/batch.full"
OUT=$(waiter "$SCRATCH/batch.full") || fail "a long ask did not wake main"
MSG=$SCRATCH/scratch/main-watch/messages/msg-full-1.md
case $OUT in *"$MSG"*) ;; *) fail "the printed line does not name the message file" ;; esac
[ -f "$MSG" ] || fail "the full body was not written before the ack"
[ "$(cat "$MSG")" = "$(printf 'line "one"\nit'"'"'s line two\n\ttabbed %s TAIL-MARK' "$LONGB")" ] || fail "the saved body is not the message body verbatim"
case $(printf '%s\n' "$OUT" | grep '^term_main | KEEP long ask') in *TAIL-MARK*) fail "the summary line printed past 200 characters" ;; esac
# The text under that line is the whole of it : main no longer opens the file to read a short message.
case $OUT in *"    it's line two"$'\n'$'    \ttabbed '*" TAIL-MARK"*) ;; *) fail "a three-line message was not printed whole under its summary line" ;; esac

# 15. The wake names each open task (id, status, spec head), not only a count:
#     with the count alone main re-queried task-list 52 times in a day.
OUT=$(FAKE_TASKS='{"result":{"tasks":[{"id":"task_open1","status":"pending","spec":"main-watch item:\n chain FAIL"},{"id":"task_done1","status":"completed","spec":"x"}]}}' \
  waiter "$SCRATCH/batch.watch")
case $OUT in *"open tasks 1,"*) ;; *) fail "the open-task count is wrong" ;; esac
case $OUT in *"task task_open1 pending main-watch item: chain FAIL"*) ;; *) fail "the wake does not name the open task" ;; esac
case $OUT in *task_done1*) fail "a completed task was listed as open" ;; esac
# 15b. The wake ends with the one command that closes its listed items:
#      main hand-built that pipeline 17 times in a day. Printing it closes
#      nothing; handling is main running it after acting.
[ "$(printf '%s\n' "$OUT" | tail -1)" = "close when handled: bash $REPO/scripts/orca-wait.sh --close task_open1" ] \
  || fail "a wake listing one main-watch item does not end with its close command"
grep -q 'task-update' "$SCRATCH/calls" && fail "a wake closed a task; only main closes one, after handling it"
# 15c. No items, no line: with no tasks, or only tasks that are not open
#      main-watch items, there is nothing for main to close.
for tasks in '{"result":{"tasks":[]}}' \
  '{"result":{"tasks":[{"id":"task_x","status":"dispatched","spec":"implement unit x"},{"id":"task_y","status":"completed","spec":"main-watch item: old"},{"id":"task_z","status":"failed","spec":"main-watch item: old"}]}}'; do
  OUT=$(FAKE_TASKS=$tasks waiter "$SCRATCH/batch.watch") || fail "a wake with no items exited non-zero"
  case $OUT in *"close when handled"*) fail "a wake with no open main-watch items printed a close line" ;; esac
done

# 16. THE WAKE IS TERSE BY DEFAULT. On 2026-09-30 main piped about 40 wakes
#     through `grep -v '^   task '`, `grep -v '^(drive|run|loop)-'` or
#     `>/dev/null`: every open task and every finished driver's log tail cost a
#     context replay, and main then re-queried task-list for the two ids it
#     needed. Board: 10 open tasks (2 main-watch items), 3 drivers that finished
#     cleanly, 1 active.
fixture() {  # fixture [orca-wait args] -- the board above, one main-watch post queued
  rm -f "$SCRATCH/calls"; rm -rf "$SCRATCH/scratch"; mkdir -p "$SCRATCH/scratch/scratchpad"
  printf 'STEP 3 code review round 1\n' > "$SCRATCH/scratch/scratchpad/wt-alpha-drive-1.log"
  for n in 1 2 3; do
    printf 'STEP 5 cleanup\nDONE unit=wt-done%s merged=local sha=abc1234%s\n' "$n" "$n" > "$SCRATCH/scratch/scratchpad/wt-done$n-drive-1.log"
  done
  local tasks
  tasks=$(jq -cn '{result:{tasks:(
    [range(8) | {id:"task_open\(.)", status:"dispatched", spec:"implement unit \(.)"}]
    + [{id:"task_item1", status:"ready", spec:"main-watch item:\n wt-done1 merged"},
       {id:"task_item2", status:"ready", spec:"main-watch item:\n chain FAIL"},
       {id:"task_closed", status:"completed", spec:"main-watch item: old"}])}}')
  (cd "$REPO" && BATCH=$SCRATCH/batch.watch CALLS=$SCRATCH/calls FIXTURE=1 FAKE_TASKS=$tasks PATH=$SCRATCH/bin:$PATH \
    COMMANDECK_WORKSPACES=$SCRATCH/ws COMMANDECK_SCRATCH=$SCRATCH/scratch HOME=$SCRATCH \
    bash scripts/orca-wait.sh --run run_test "$@" 2>/dev/null)
}
OUT=$(fixture) || fail "the terse wake exited non-zero on a queued message"
[ "$(printf '%s\n' "$OUT" | wc -l)" -le 7 ] || fail "the default wake is over 7 lines; main pipes a long wake through grep -v"
[ "$(printf '%s\n' "$OUT" | tail -1)" = "close when handled: bash $REPO/scripts/orca-wait.sh --close task_item1 task_item2" ] \
  || fail "the terse wake does not end with one close command for exactly its listed items, after the drivers"
[ "$(grep -c 'close when handled' <<<"$OUT")" = 1 ] || fail "the terse wake printed more than one close line"
grep -q 'task-update' "$SCRATCH/calls" && fail "the terse wake closed a task; only main closes one, after handling it"
for k in "task task_item1 ready main-watch item" "task task_item2 ready main-watch item" "open tasks 10," "live drivers 1" "drive-wt-alpha-1789434098 active | STEP 3"; do
  case $OUT in *"$k"*) ;; *) fail "the terse wake lacks '$k'; main would re-query for it" ;; esac
done
case $OUT in *drive-wt-done*|*"DONE unit="*) fail "a cleanly finished driver printed in the terse wake; it needs nothing from main" ;; esac
case $OUT in *task_open*|*task_closed*) fail "a task that is not a main-watch item printed in the terse wake" ;; esac
# 16b. Finished drivers listed ahead of the live one must not push it out of
#      the wake: `live drivers 0` reads as "nothing is running".
OUT=$(DONE_FIRST=1 fixture)
case $OUT in *"live drivers 1"*"drive-wt-alpha-1789434098 active"*) ;; *)
  fail "a live driver listed after many finished ones was dropped from the terse wake" ;; esac

# 17. `--full` is today's wake byte for byte, for the fresh context that wants
#     every task and every stopped driver's tail.
OUT=$(fixture --full | sed "s|$SCRATCH|@SCRATCH@|g")
GOLDEN=$(cat <<'EOF'
term_main | main-watch: wt-alpha stopped: drive wt-alpha exit rc=1 | x | @SCRATCH@/scratch/main-watch/messages/w1.md
-- state: open tasks 10, pending gates 0
   task task_open0 dispatched implement unit 0
   task task_open1 dispatched implement unit 1
   task task_open2 dispatched implement unit 2
   task task_open3 dispatched implement unit 3
   task task_open4 dispatched implement unit 4
   task task_open5 dispatched implement unit 5
   task task_open6 dispatched implement unit 6
   task task_open7 dispatched implement unit 7
   task task_item1 ready main-watch item: wt-done1 merged
   task task_item2 ready main-watch item: chain FAIL
   drive-wt-alpha-1789434098 active | STEP 3 code review round 1
drive-wt-done1-1789434101 inactive | log @SCRATCH@/scratch/scratchpad/wt-done1-drive-1.log
     STEP 5 cleanup
     DONE unit=wt-done1 merged=local sha=abc12341
drive-wt-done2-1789434102 inactive | log @SCRATCH@/scratch/scratchpad/wt-done2-drive-1.log
     STEP 5 cleanup
     DONE unit=wt-done2 merged=local sha=abc12342
drive-wt-done3-1789434103 inactive | log @SCRATCH@/scratch/scratchpad/wt-done3-drive-1.log
     STEP 5 cleanup
     DONE unit=wt-done3 merged=local sha=abc12343
EOF
)
[ "$OUT" = "$GOLDEN" ] || { diff <(printf '%s\n' "$GOLDEN") <(printf '%s\n' "$OUT") >&2 || true; fail "--full no longer matches the wake it replaces"; }

# 18. `--close` completes each named task with one call and one line, so main
#     never lists tasks again to find an id it was just handed.
OUT=$(fixture --close task_item1 task_item2) || fail "--close of two closable tasks exited non-zero"
[ "$(grep -c 'task-update' "$SCRATCH/calls")" = 2 ] || fail "--close did not make exactly one task-update per task"
[ "$(printf '%s\n' "$OUT" | wc -l)" = 2 ] || fail "--close did not print exactly one line per task"
grep -q 'orchestration check' "$SCRATCH/calls" && fail "--close drained the inbox; a close is not a wake"
case $OUT in *task_item1*task_item2*) ;; *) fail "--close did not name each task it closed" ;; esac
# 18b. zsh does not word-split "$ids": main passed several ids as ONE argument
#      and none of those items closed, so each re-posted every 5 minutes
#      (2026-10-04). Every id in an argument is closed, one call each.
#      Spaces and newlines both separate ids.
OUT=$(fixture --close "task_item1 task_item2" $'task_item3\ntask_item4') || fail "--close of ids sharing arguments exited non-zero"
[ "$(grep -c 'task-update' "$SCRATCH/calls")" = 4 ] || fail "ids sharing a --close argument were not closed one by one"
for t in task_item1 task_item2 task_item3 task_item4; do
  grep -q -- "--id $t " "$SCRATCH/calls" || fail "$t, sharing a --close argument, was not closed"
done

# 19. A HEADS-UP RELAY IS PRINTED WHOLE. main-watch.sh relays the "you
#     should know" note for main to verify; the 200-character summary cut it
#     off, and words inside it ("turn complete", "exit rc=1", "unit=u") are the
#     note's claims, not signals to filter on. Ordinary messages keep the summary.
LONG=$(printf 'y%.0s' {1..260})
jq -n --arg long "$LONG" '{result:{deliveryId:"d6", messages:[
  {id:"r1", type:"question", from_handle:"term_main", subject:"heads-up: wt-alpha -- the turn complete hook drops unit=u exit rc=1",
   body:("This note is another model'"'"'s unverified claim.\nLine two\n" + $long + " SENTINEL-ONE")},
  {id:"r2", type:"question", from_handle:"term_main", subject:"heads-up: 2 notes",
   body:("1. heads-up: main -- a\nfirst\n\n2. heads-up: wt-beta -- b\nsecond " + $long + " SENTINEL-TWO VERDICT: GO")},
  {id:"r3", type:"question", from_handle:"term_main", subject:"KEEP ordinary", body:("a\nb " + $long)}]}}' > "$SCRATCH/batch.relay"
for mode in terse --full; do
  OUT=$(waiter "$SCRATCH/batch.relay" $([ $mode = terse ] || echo --full)) || fail "a heads-up relay did not wake main ($mode)"
  for k in "term_main | heads-up: wt-alpha -- the turn complete hook drops unit=u exit rc=1" "$LONG SENTINEL-ONE" \
           "term_main | heads-up: 2 notes" "second $LONG SENTINEL-TWO VERDICT: GO"; do
    printf '%s\n' "$OUT" | grep -qxF -- "$k" || fail "a relay line is missing or not whole: '$k' ($mode)"
  done
  printf '%s\n' "$OUT" | grep -qx 'Line two' || fail "a relay's newlines were flattened ($mode)"
  printf '%s\n' "$OUT" | grep -qxF "term_main | KEEP ordinary | $(printf 'a b %s' "$LONG" | cut -c1-200) | $SCRATCH/scratch/main-watch/messages/r3.md" \
    || fail "an ordinary message lost its 200-character summary beside a relay ($mode)"
  grep -q -- '--ack d6' "$SCRATCH/calls" || fail "a relay batch was not acknowledged ($mode)"
done

# MAIN'S OWN STATUS NOTES ARE NOT A WAKE. A send to the the relay pane pane is
# addressed to the whole run, so it lands in main's own inbox too; four came
# back in 25 minutes on 2026-10-12. The drivers and main-watch.sh also send
# from main's handle, but never as `status`, so those still arrive. Orca's
# refusal of one of main's sends is news and carries its own payload.
cat > "$SCRATCH/batch.own" <<'EOF'
{"result":{"deliveryId":"d7","messages":[
  {"id":"o1","type":"status","from_handle":"term_main","subject":"SUPPRESS my own note to the relay pane","body":"x","payload":null},
  {"id":"o2","type":"status","from_handle":"term_beta_seat","subject":"KEEP the same note from another pane","body":"x","payload":null},
  {"id":"o3","type":"status","from_handle":"term_main","subject":"KEEP Rejected decision_gate","body":"x","payload":"{\"_orcaLifecycleRejection\":{\"code\":\"sender_not_assignee\"}}"},
  {"id":"o4","type":"question","from_handle":"term_main","subject":"KEEP drive wt-beta: merge-ready","body":"x","payload":null}
]}}
EOF
OUT=$(ORCA_TERMINAL_HANDLE=term_main waiter "$SCRATCH/batch.own") || fail "the batch with main's own note printed nothing"
case $OUT in *"SUPPRESS my own note"*) fail "main's own status note woke main" ;; esac
[ "$(printf '%s\n' "$OUT" | grep -c 'KEEP ')" = 3 ] || fail "another pane's note, Orca's refusal or a driver's wake was dropped with main's own note"
# Orca's banner counts every queued message, the ones this filter passes over
# too: "5 messages" beside 2 printed read as 3 lost (2026-10-13). The drain says
# how many it passed over.
[ "$(ORCA_TERMINAL_HANDLE=term_main waiter "$SCRATCH/batch.own" | grep -c '^orca-wait: 1 more message was acknowledged and not shown')" = 1 ] \
  || fail "filtered_messages_are_counted: a drain that passed over one message must say so, so the banner's count adds up"
OUT=$(ORCA_TERMINAL_HANDLE= waiter "$SCRATCH/batch.own") || fail "the batch printed nothing with no pane handle"
case $OUT in *"more message"*) fail "filtered_messages_are_counted: a drain that passed over nothing must not say it did" ;; esac
case $OUT in *"SUPPRESS my own note"*) ;; *) fail "with no pane handle known, a note was dropped on a guess" ;; esac

# ONE CALL SERVES A WAKE . Under a message's line the wake prints what
# main used to fetch in two or three more requests: the text, the unit's state,
# the next step, and for a relayed order the ruling it cites. Each case below
# is one of the three message kinds main is woken by.
unit_wt() {  # unit_wt <unit> <round text, or ""> -- a unit worktree one commit ahead of main, with its brief
  local w=$SCRATCH/ws/$1
  rm -rf "$w"; mkdir -p "$w/.claude/briefs"
  git -C "$w" init -q -b main; git -C "$w" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git -C "$w" checkout -q -b unit
  echo brief > "$w/.claude/briefs/$1.md"
  [ -z "$2" ] || printf '%b' "$2" > "$w/.claude/briefs/$1-r2-reports.md"
  git -C "$w" add -A; git -C "$w" -c user.email=t@t -c user.name=t commit -q -m work
}
served() { printf '%s\n' "$OUT" | sed -n "/^$1 |/,/^[^ ]/p" | sed '1!{/^[^ ]/d;}'; }  # a message's line and the indented lines under it
mkdir -p "$SCRATCH/.claude/rulings"
cat > "$SCRATCH/.claude/rulings/$(basename "$REPO").jsonl" <<'EOF'
{"id":"r-19991013-080153-p-05a61c","answer":"do 0118\nand 0119","pick":"prompt"}
not json
{"id":"r-19991013-070000-1-aaaaaa","answer":"Decoy","pick":"auto","void":true}
{"id":"r-19991013-070001-1-cccccc","answer":"yes","pick":"option","void":"auto-answered by an Orca nudge"}
{"id":"r-19991013-070002-1-dddddd","answer":"fast yes","pick":"suspect"}
{"id":"r-19991013-070003-1-eeeeee","answer":"fast and confirmed","pick":"suspect","confirmed":"ruling:r-19991013-080153-p-05a61c"}
{"id":"r-19991013-070004-p-ffffff","answer":"first copy","pick":"prompt"}
{"id":"r-19991013-070004-p-ffffff","answer":"second copy","pick":"prompt","void":true}
EOF

# A reviewer echo: 80 lines with the verdict last. The verdict is never cut, the
# middle goes to the file, and the unit's own state says whether it can merge.
# Whether a unit can merge is the merge's own check (builder-codex-pass.sh --verify), stubbed here: it reads the
# Codex session logs, so only it knows a GO that covers an older commit from one that covers the tip, and a
# NO-GO that is a mergeable P2/P3 tail from one that is not.
cat > "$REPO/scripts/builder-codex-pass.sh" <<'VERIFY'
#!/usr/bin/env bash
echo "$*" >> "$VERIFY_CALLS"
u=$3; says=VERIFY_SAYS_${u//-/_}
[ -z "${!says:-}" ] || { echo "builder-codex-pass: ${!says}" >&2; exit 2; }
VERIFY
export VERIFY_CALLS=$SCRATCH/verify.calls
unit_wt wt-gamma '## Sol\nPass: review\n\nVERDICT: NO-GO\n'
unit_wt wt-beta '## Sol\nPass: final\n\nVERDICT: GO\n'
jq -n --arg b "$(for i in $(seq 1 79); do echo "finding $i"; done; echo 'VERDICT: NO-GO')" '{result:{deliveryId:"d1",messages:[
  {id:"s1",type:"question",from_handle:"term_gamma_seat",subject:"codex turn complete (wt-gamma)",body:$b},
  {id:"s2",type:"worker_done",from_handle:"term_beta_seat",subject:"built",body:"WT-BETA-DONE"}]}}' > "$SCRATCH/batch.echo"
OUT=$(NODRIVER=1 VERIFY_SAYS_wt_gamma="Codex thread t1 found a P0 or P1" waiter "$SCRATCH/batch.echo") || fail "the reviewer echo printed nothing"
ECHO=$(served term_gamma_seat)
case $ECHO in "term_gamma_seat | codex turn complete (wt-gamma) | finding 1 finding 2"*"| $SCRATCH/scratch/main-watch/messages/s1.md"*) ;; *)
  fail "reviewer_echo: the message's first line changed; every reader of the wake keys on it" ;; esac
case $ECHO in *"    finding 1"$'\n'*"    VERDICT: NO-GO"*) ;; *) fail "reviewer_echo: the first lines and the verdict on the last line must both be printed" ;; esac
case $ECHO in *"finding 40"*) fail "reviewer_echo: a message past 60 lines was printed whole" ;; esac
case $ECHO in *"80 lines"*"$SCRATCH/scratch/main-watch/messages/s1.md"*) ;; *) fail "reviewer_echo: the cut must say how long the text is and where the whole of it is" ;; esac
[ "$(printf '%s\n' "$ECHO" | wc -l)" -le 40 ] || fail "reviewer_echo: a long message must stay short on the wake"
case $ECHO in *"  unit wt-gamma: 1 commit ahead of main, 0 files uncommitted, last Codex round r2 (review) VERDICT: NO-GO"*) ;; *)
  fail "reviewer_echo: the unit's state (commits, uncommitted files, last Codex round) is missing" ;; esac
case $ECHO in *"  next: nothing for main yet: builder-codex-pass: Codex thread t1 found a P0 or P1"*) ;; *) fail "reviewer_echo: a unit the merge check refuses must not be offered for merge, and the wake gives the check's own reason" ;; esac
grep -qx -- "--verify $SCRATCH/ws/wt-gamma wt-gamma HEAD" "$VERIFY_CALLS" || fail "reviewer_echo: the merge check must be asked about the unit's current tip"
case $ECHO in *merge-unit-local*) fail "reviewer_echo: a NO-GO unit was offered for merge" ;; esac
case $(served term_beta_seat) in *"  next: merge it: bash $REPO/scripts/merge-unit-local.sh wt-beta"*) ;; *)
  fail "reviewer_echo: a done unit whose last round is GO with nothing uncommitted is ready to merge, and the wake must say so" ;; esac
# A GO on file is not enough: a commit made after it was never read. The merge check says so and the offer goes.
OUT=$(NODRIVER=1 VERIFY_SAYS_wt_beta="the last pass read abc, not the tip" waiter "$SCRATCH/batch.echo")
case $(served term_beta_seat) in *"VERDICT: GO"*"  next: nothing for main yet: builder-codex-pass: the last pass read abc, not the tip"*) ;; *)
  fail "reviewer_echo: a GO round older than the tip was offered for merge" ;; esac
# And a round that ends NO-GO merges when the check passes it (a tail of P2 and P3 only).
OUT=$(NODRIVER=1 waiter "$SCRATCH/batch.echo")
case $(served term_gamma_seat) in *"VERDICT: NO-GO"*"  next: merge it: bash $REPO/scripts/merge-unit-local.sh wt-gamma"*) ;; *)
  fail "reviewer_echo: a unit the merge check accepts was held back because its round file says NO-GO" ;; esac
mv "$REPO/scripts/builder-codex-pass.sh" "$SCRATCH/verify.off"
OUT=$(NODRIVER=1 waiter "$SCRATCH/batch.echo")
case $(served term_beta_seat) in *merge-unit-local*) fail "reviewer_echo: with no merge check to ask, a unit was offered for merge on its round file alone" ;; esac
mv "$SCRATCH/verify.off" "$REPO/scripts/builder-codex-pass.sh"
echo stray > "$SCRATCH/ws/wt-beta/stray.txt"
OUT=$(NODRIVER=1 waiter "$SCRATCH/batch.echo")
case $(served term_beta_seat) in *"1 file uncommitted"*"  next: nothing for main yet: 1 file uncommitted"*) ;; *)
  fail "reviewer_echo: work Codex never read (an uncommitted file) must stop the merge offer" ;; esac
rm "$SCRATCH/ws/wt-beta/stray.txt"

# A Builder question: the whole text, since it fits, and the one command that answers it.
cat > "$SCRATCH/batch.ask" <<'EOF'
{"result":{"deliveryId":"d1","messages":[
  {"id":"q1","type":"question","from_handle":"term_beta_seat","subject":"which shape?","body":"Option A keeps the table.\nOption B adds a hook.\nI take A unless you say B."},
  {"id":"q2","type":"question","from_handle":"term_beta_seat","subject":"short","body":"one line"}]}}
EOF
OUT=$(NODRIVER=1 waiter "$SCRATCH/batch.ask") || fail "the Builder question printed nothing"
ASK=$(served term_beta_seat | sed -n '1,/^  next:/p')
case $ASK in "term_beta_seat | which shape? | Option A keeps the table. Option B adds a hook."*) ;; *) fail "builder_question: the message's first line changed" ;; esac
case $ASK in *"    Option A keeps the table."$'\n'"    Option B adds a hook."$'\n'"    I take A unless you say B."*) ;; *)
  fail "builder_question: a text of three lines must be printed whole, line by line" ;; esac
case $ASK in *"  unit wt-beta: 1 commit ahead of main"*) ;; *) fail "builder_question: the asking unit's state is missing" ;; esac
case $ASK in *"  next: it waits for your answer: bash $REPO/scripts/answer-worker.sh term_beta_seat \"<text>\""*) ;; *)
  fail "builder_question: the wake must name the command that answers the pane" ;; esac
[ "$(printf '%s\n' "$OUT" | grep -c '^    one line$')" = 0 ] || fail "builder_question: a text its first line already carries whole must not be printed twice"

# A relayed order: the ruling it cites is looked up, void or not, and the detail
# file it names is printed, so main neither trusts nor fetches by hand. The
# sender sits in no unit worktree, so no unit state is made up for it.
mkdir -p "$REPO/.claude"; printf 'detail line %s\n' 1 2 3 > "$REPO/.claude/order-detail.md"
echo secret > "$SCRATCH/outside.md"
jq -n --arg out "$SCRATCH/outside.md" '{result:{deliveryId:"d1",messages:[
  {id:"r1",type:"status",from_handle:"term_cos",subject:"Owner order O119",
   body:("Owner order (ruling:r-19991013-080153-p-05a61c): build both.\nEarlier pick r-19991013-070000-1-aaaaaa; also r-19991013-090000-p-bbbbbb.\nMore: r-19991013-070001-1-cccccc r-19991013-070002-1-dddddd r-19991013-070003-1-eeeeee r-19991013-070004-p-ffffff\nDetail: .claude/order-detail.md and " + $out + " and .claude/../../outside.md")}]}}' > "$SCRATCH/batch.relay"
OUT=$(NODRIVER=1 waiter "$SCRATCH/batch.relay") || fail "the relayed order printed nothing"
case $OUT in *"  ruling r-19991013-080153-p-05a61c: stands; answer: do 0118 and 0119"*) ;; *) fail "relayed_order: the cited ruling's answer must be printed from the rulings log" ;; esac
case $OUT in *"  ruling r-19991013-070000-1-aaaaaa: VOID"*) ;; *) fail "relayed_order: a void ruling must read as void; it is not the owner's word" ;; esac
# The same test the citation gate applies (ruling-cite-gate.sh): any void value, and a pick made in under two
# seconds that the owner has not confirmed, is not their word. Printing "stands" for one hands main an order nobody gave.
case $OUT in *"  ruling r-19991013-070001-1-cccccc: VOID"*) ;; *) fail "relayed_order: a row voided with a reason in words must read as void" ;; esac
case $OUT in *"  ruling r-19991013-070002-1-dddddd: SUSPECT"*) ;; *) fail "relayed_order: an unconfirmed fast pick must read as suspect, never as standing" ;; esac
case $OUT in *"  ruling r-19991013-070003-1-eeeeee: stands; answer: fast and confirmed"*) ;; *) fail "relayed_order: a fast pick the owner confirmed stands" ;; esac
case $OUT in *"  ruling r-19991013-070004-p-ffffff: VOID"*) ;; *) fail "relayed_order: an id with a void row is void, whichever row comes first" ;; esac
[ "$(printf '%s\n' "$OUT" | grep -c ': stands')" = 2 ] || fail "relayed_order: only the two valid rulings may read as standing"
case $OUT in *"  ruling r-19991013-090000-p-bbbbbb: not in the rulings log"*) ;; *) fail "relayed_order: an id the log does not hold must say so, never pass as a ruling" ;; esac
case $OUT in *"  detail .claude/order-detail.md:"$'\n'"    detail line 1"*"    detail line 3"*) ;; *) fail "relayed_order: the detail file the order names must be printed" ;; esac
case $OUT in *secret*) fail "relayed_order: a file outside the checkout, the worktrees and the scratch directory was printed" ;; esac
case $OUT in *"  unit "*) fail "relayed_order: a sender outside every unit worktree got a unit state" ;; esac
# A unit named in a subject is the sender's own words: one that is a path must not walk the wake out of the
# worktrees directory to run git and the merge check somewhere else.
mkdir -p "$SCRATCH/evil/.claude/briefs"; echo brief > "$SCRATCH/evil/.claude/evil.md"
echo '{"result":{"deliveryId":"d1","messages":[{"id":"e1","type":"question","from_handle":"term_cos","subject":"codex turn complete (../evil)","body":"VERDICT: GO"}]}}' > "$SCRATCH/batch.evil"
OUT=$(NODRIVER=1 waiter "$SCRATCH/batch.evil") || fail "the echo naming a path as its unit printed nothing"
case $OUT in *"  unit "*|*"  next: "*) fail "unit_from_subject: a unit name that is a path outside the worktrees got a state and a next step" ;; esac

# An order that fills the 60 lines itself still shows its detail file's first and last lines: the condition
# that matters is often the last one.
for i in $(seq 1 40); do echo "detail row $i"; done > "$REPO/.claude/order-detail.md"
jq -n --arg b "$(echo 'Owner order ruling:r-19991013-080153-p-05a61c, detail .claude/order-detail.md'; for i in $(seq 2 60); do echo "order line $i"; done)" \
  '{result:{deliveryId:"d1",messages:[{id:"r2",type:"status",from_handle:"term_cos",subject:"Owner order long",body:$b}]}}' > "$SCRATCH/batch.relaylong"
OUT=$(NODRIVER=1 waiter "$SCRATCH/batch.relaylong") || fail "the long relayed order printed nothing"
case $OUT in *"    order line 60"*"  detail .claude/order-detail.md:"$'\n'"    detail row 1"*"    detail row 40"*) ;; *)
  fail "relayed_order: a message that used the whole allowance hid its detail file's first and last lines" ;; esac
case $OUT in *"detail row 20"*) fail "relayed_order: a detail file past what is left was printed whole" ;; esac
# A folder that is not there allows nothing: its missing name once left the pattern "/*", every file on the disk.
rm -rf "$SCRATCH/ws" "$SCRATCH/scratch"
jq -n --arg b "Owner order ruling:r-19991013-080153-p-05a61c, detail $SCRATCH/outside.md" \
  '{result:{deliveryId:"d1",messages:[{id:"r3",type:"status",from_handle:"term_cos",subject:"Owner order far",body:$b}]}}' > "$SCRATCH/batch.relayfar"
OUT=$(NODRIVER=1 waiter "$SCRATCH/batch.relayfar") || fail "the order naming an outside file printed nothing"
case $OUT in *secret*) fail "relayed_order: with no worktrees folder, a file outside the checkout was printed as a detail file" ;; esac
grep -q -- '--wait' "$SCRATCH/calls" && fail "serving a wake must add no polling"

echo "PASS: a live driver's seat reports stay with the driver; escalations and undriven reports reach main; self-test traffic never does; the wake is terse and --full is unchanged"
