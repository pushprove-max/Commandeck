#!/usr/bin/env bash
# answer-worker.sh [--interrupt] <terminal-handle|unit> <text> [<question-id>] -- main's one way to answer a
# worker's question.
#
# A unit name finds its Builder's pane at send time: a restart gives the pane a
# new handle. With no live pane the answer is queued and shown first when the
# Builder starts again (to-main.sh --unit); that still exits 1, as not delivered.
#
# A worker that asked main either waits on its inbox (`orchestration check
# --wait`) or has ended its turn. An inbox message ends the wait at once, but a
# pane that has ended its turn never reads its inbox; typed text reaches that
# pane, but only queues behind a wait. So the pane's state picks the way: an
# inbox message to a pane that is mid-turn, typed text to one that is not.
# The inbox message is a reply to the question's id when <question-id> holds one
# (orchestration reply --id): a worker blocked in `orchestration ask` returns only
# on a reply to its own question, never on a new message. With no id it is a send.
# Either way the answer counts as delivered only when its text is in the
# pane's session log (exit 0). An inbox message to a pane still mid-turn when
# the wait ends is said to be queued, not read yet, and checked on until ANSWER_WORKER_ACK_WAIT seconds from the send
# (default 600): then it is NOT acknowledged (exit 1, issue 351; exit 2 is gone). Anything else not in the log exits 1,
# NOT delivered. An answer that left main (delivered, queued in the inbox, or
# queued for a restart) closes the unit's question waiting on main in the
# decisions ledger: the one <question-id> names, or the only one open. With
# several open and none named, none is closed: one answer is not every answer.
#
# In main's own foreground (issue 340) the answer is sent and the call returns 0 at once: the wait for the tag in the log,
# its retry and the ledger closing run in a detached follower, whose log the call names. Main hears from the follower
# only when the answer is NOT delivered. Anywhere else the wait runs in the call and the exit code is as above.
# --interrupt (issue 351): types the answer into the pane with an interrupt, for a pane blocked in ask-main.sh's wait. Only a
# pane whose ask-main.sh call is in that wait as the answer is sent takes it (the call's wait token is claimed for the send,
# and the call does not return until it is sent); any other pane, one between slices included, is refused with nothing
# sent and the plain command printed: an interrupt would cut the work it is doing.
# Never automatic. With no <question-id>, the pane's own open question (its seat record, the way pp_task_close counts it)
# is the thread the answer replies in, so a pane blocked in `orchestration ask` is not left to wait out its limit.
#
# ANSWER_WORKER_WAIT: seconds to wait for the text in the log (default 60).
# ANSWER_WORKER_ACK_WAIT: seconds an inbox answer to a busy pane is checked from the send before it is NOT acknowledged (default 600).
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/codex-helpers.sh"
INTERRUPT=; [ "${1-}" != --interrupt ] || { INTERRUPT=1; shift; }
H=${1:?usage: answer-worker.sh [--interrupt] <terminal-handle|unit> <text> [<question-id>]}; H=${H#terminal:}
TEXT=${2:?usage: answer-worker.sh [--interrupt] <terminal-handle|unit> <text> [<question-id>]}
Q=${3:-}
# The reply goes to the Orca id inside <unit>-msg_<id> (a bare msg_<id> works too).
QID=; case $Q in *msg_*) QID=msg_${Q##*msg_} ;; esac
# close_asks -- answer the unit's question waiting on main in the decisions ledger (orca-wait.sh
# recorded it): the answer has left main, read or queued.
close_asks() {
  local u=${U:-} ids q=$Q
  [ -n "$u" ] || case ${WT:-} in "$PP_WORKSPACES"/*) u=${WT#"$PP_WORKSPACES"/}; u=${u%%/*} ;; esac
  [ -n "$u" ] || return 0
  # The ledger keeps <unit>-msg_<id> (orca-wait.sh): a bare msg_<id> names the same question.
  case $q in msg_*) q=$u-$q ;; esac
  ids=$(bash "$HERE/decision.sh" list 2>/dev/null | jq -r --arg s "$u asks" --arg q "$q" \
    '.[] | select(.answeredAt == null and .waitsOn == "main" and .source == $s and ($q == "" or .id == $q)) | .id')
  if [ -z "$ids" ]; then [ -z "$q" ] || echo "answer-worker: no open question $q from $u in the ledger; nothing closed" >&2; return 0; fi
  if [ "$(wc -l <<<"$ids")" -gt 1 ]; then
    echo "answer-worker: $u has questions $(paste -sd' ' - <<<"$ids") open; none closed. Close the one this answered: bash $HERE/decision.sh answer <id> '<answer>'" >&2
    return 0
  fi
  bash "$HERE/decision.sh" answer "$ids" "$TEXT" >/dev/null || echo "answer-worker: decision $ids stays open in the ledger" >&2
}
if [ -d "$PP_WORKSPACES/$H" ]; then
  U=$H; H=$(pp_seat_pane "unit-$U" "$PP_WORKSPACES/$U")
  [ -n "$H" ] || { bash "$HERE/to-main.sh" --unit "$U" status "answer from main" "$TEXT" 2>/dev/null
    [ $? = 3 ] && { close_asks; echo "answer-worker: the Builder of $U is not running; the answer is queued and shown first when it starts again. Not delivered yet." >&2; } \
      || echo "answer-worker: the Builder of $U is not running, and the answer could not be queued; nothing was sent" >&2; exit 1; }
fi
# --interrupt takes only a pane blocked in ask-main.sh's wait at the moment of the send, so it never cuts the work the
# pane resumes after (an open question alone is not enough: between slices the pane is working). Right before the send it
# claims the wait token ask-main.sh holds for this pane (<id>.wait, mv'd to <id>.claim.<pid>): ask-main.sh's own removal
# and the claim exclude each other, and ask-main.sh does not return while a live claim is held. A token whose pid is not a
# live ask-main.sh is a killed call's, and is dropped. Every refusal, and a failed send, prints the one retry: the plain
# route, which reads no ask-main.sh state.
CLAIM=
claim_wait() { local t c p; for t in "$PP_SCRATCH"/ask-main/*.wait; do
    [ -f "$t" ] && grep -qxF "pane=$H" "$t" 2>/dev/null || continue
    c=${t%.wait}.claim.$$; mv "$t" "$c" 2>/dev/null || continue
    p=$(sed -n 's/^pid=//p' "$c")
    grep -qxF "pane=$H" "$c" && [ -n "$p" ] && kill -0 "$p" 2>/dev/null && ps -p "$p" -o command= 2>/dev/null | grep -q 'ask-main\.sh' \
      && { CLAIM=$c; return 0; }
    rm -f "$c"
  done; return 1; }
retry() { printf 'Send it without --interrupt: bash %s/answer-worker.sh %q %q' "$HERE" "${U:-$H}" "$TEXT"; [ -z "$Q" ] || printf ' %q' "$Q"; }
[ -z "$INTERRUPT" ] || trap '[ -z "$CLAIM" ] || rm -f "$CLAIM"' EXIT
# No question id given: the pane's own open question is the thread to reply in (issue 351). pp_seat_open_ask counts the
# questions pp_task_close counts, so the answer and the task close agree. Not in the background follower: the call that
# started it has looked, and handed on the id it found.
if [ -z "$QID" ] && [ -z "${ANSWER_WORKER_FOLLOW:-}" ]; then
  REC=$(grep -lx "handle=$H" "$PP_SCRATCH"/seat-*.txt 2>/dev/null | head -1 || true)
  if [ -z "$REC" ]; then echo "answer-worker: no seat record names $H, so its open question was not looked up" >&2
  else
    rc=0; pp_seat_open_ask "$H" "$REC" || rc=$?
    case $rc in
      0) QID=$PP_OPEN_ASK_ID Q=$QID; echo "answer-worker: replying in $QID, the open question of $H" >&2 ;;
      1) ;;
      *) echo "answer-worker: the open question of $H could not be read (inbox or dispatch); sending without a question id" >&2 ;;
    esac
  fi
fi
WAIT=${ANSWER_WORKER_WAIT:-60}
# An inbox answer still unread after WAIT is checked until ACK seconds from the send (longer than ask-main.sh's 540-second limit).
ACK=${ANSWER_WORKER_ACK_WAIT:-600}
# Given the question's id, every route ends with a reply in that question's thread: it is the only answer pp_task_close
# counts (paths.sh pp_open_ask), so an answer sent without the id leaves the asker's task unsettled. The typed route
# replies only once the tag is in the log (a reply on an undelivered answer would let pp_task_close settle a worker that
# never got it); the inbox route replies first, since that reply is how a worker blocked in `ask` receives the answer.
REPLIED=
reply_delivered() {
  [ -z "$QID" ] || [ -n "$REPLIED" ] || jq -e '.ok == true' <<<"$(orca-ide orchestration reply --id "$QID" --body "$MSG" --json 2>/dev/null)" >/dev/null 2>&1 \
    || echo "answer-worker: delivered, but the reply to $QID failed, so its task will not settle until a reply lands in that thread: orca-ide orchestration reply --id $QID --body \"answered: $TAG\"" >&2
}
# The tag is what is looked for in the log: the text itself may be re-wrapped.
TAG=${ANSWER_WORKER_TAG:-answer-$(date +%s)-$$}
MSG="[$TAG] $TEXT"

TS=$(timeout 8 orca-ide terminal list --json 2>/dev/null) && PS=$(timeout 8 orca-ide worktree ps --json 2>/dev/null) \
  || { echo "answer-worker: Orca's pane lists cannot be read; nothing was sent to $H" >&2; exit 1; }
WT=$(pane_worktree_of "$TS" "$PS" "$H")
[ -n "$WT" ] || { echo "answer-worker: no agent pane $H in Orca's worktree list; nothing was sent. A restarted pane has a new handle: pass the unit name instead" >&2; exit 1; }
# The pane's log is looked up by worktree and kind: a Builder's Codex reviewer writes its own log in the same worktree.
KIND=$(pane_kind_of "$TS" "$PS" "$H")
[ -n "$KIND" ] || { echo "answer-worker: Orca does not say whether $H is a Claude or a Codex pane, so its session log cannot be picked; nothing was sent" >&2; exit 1; }

# The pane's session log now, by worktree and kind, and whether its turn is over.
# Two Claude planners share one worktree, so a planner pane (a seat record with its handle) is read through its launch
# binding, the first session after its launch handed its tag; --current would pick the newer planner's log.
# A Builder is not bound that way: a fresh round gives it a later session.
log_state() {
  local rec at tag
  rec=$(grep -lx "handle=$H" "$PP_SCRATCH"/seat-*.txt 2>/dev/null | head -1)
  at=$(sed -n 's/^launched=//p' "$rec" 2>/dev/null | tail -1); tag=$(sed -n 's/^tag=//p' "$rec" 2>/dev/null | tail -1)
  if [ -n "$at" ] && [ -n "$tag" ] && ! grep -qx 'role=builder' "$rec"; then
    V=$("$HERE/read-verdict.sh" --state --worktree "$WT" --agent "$KIND" --launched "$at" --spec "$tag" 2>/dev/null)
  else V=$("$HERE/read-verdict.sh" --state --worktree "$WT" --agent "$KIND" --current 2>/dev/null); fi
  LOG=$(sed -n 's/^session=//p' <<<"$V")
}
# idle: 0 when the pane's turn is over. Its log says so first: Orca can keep `working` for a pane whose
# turn ended (a Builder past its done marker beside its reviewer), and an answer left in that inbox was never read.
idle() {
  local rc=0
  grep -qx 'state=complete' <<<"$V" && return 0
  pane_is_busy "$H" || rc=$?
  [ "$rc" = 1 ]
}
# wake <result> -- the wake log's line for this answer (the owner's view of what main sent a worker).
wake() { pp_wake_log answer-worker "$H" "answer ${TAG}" "$@"; }
log_state
# The background follower (issue 340) is this script run again: the answer is already sent, the way it went is handed
# over, and only the wait for the tag in the log, its retry and the closing of the ledger entry are left.
FOLLOW=${ANSWER_WORKER_FOLLOW:-}
if [ -n "$FOLLOW" ]; then
  WAY=$ANSWER_WORKER_WAY REPLIED=${ANSWER_WORKER_REPLIED:-}
elif [ -n "$INTERRUPT" ]; then
  WAY="typed into the pane with an interrupt"
  claim_wait || { echo "answer-worker: --interrupt refused: $H is not waiting in ask-main.sh now (no question of its, or its wait has returned); nothing was sent. $(retry)" >&2; exit 1; }
  timeout 8 orca-ide terminal send --terminal "$H" --text "$MSG" --enter --interrupt --json >/dev/null; rc=$?
  rm -f "$CLAIM"; CLAIM=
  [ "$rc" = 0 ] || { wake refused "terminal send --interrupt failed"; echo "answer-worker: terminal send --interrupt to $H failed (exit $rc); the answer may have been typed before it ended, so check the pane first. $(retry)" >&2; exit 1; }
  wake sent
elif idle; then
  WAY="typed into the pane"
  orca-ide terminal send --terminal "$H" --text "$MSG" --enter --json >/dev/null \
    || { wake refused "terminal send failed"; echo "answer-worker: terminal send to $H failed; the answer was not delivered" >&2; exit 1; }
  wake sent
else
  # A Builder blocked in `orchestration ask` returns only on a reply to its question's id (host 33cdf11c).
  WAY="sent to the pane's inbox${QID:+ as a reply to $QID}"
  if [ -n "$QID" ]; then
    orca-ide orchestration reply --id "$QID" --body "$MSG" --json >/dev/null \
      || { wake refused "inbox reply to $QID failed"; echo "answer-worker: the inbox reply to $QID failed; the answer was not delivered" >&2; exit 1; }
    REPLIED=1
  else
    orca-ide orchestration send --to "$H" --type status --subject "answer from main" --body "$MSG" --json >/dev/null \
      || { wake refused "inbox send failed"; echo "answer-worker: the inbox send to $H failed; the answer was not delivered" >&2; exit 1; }
  fi
  wake sent
fi

confirm() {
local LEFT=$WAIT T0=$SECONDS QUEUED=
while :; do
  log_state
  [ -n "$LOG" ] && grep -qF -- "$TAG" "$LOG" 2>/dev/null && { reply_delivered; close_asks; pp_close_items "$H"; echo "answer-worker: delivered to $H ($WAY), tag $TAG"; return 0; }
  # A pane that was mid-turn and has since ended its turn will never read its
  # inbox: the answer is typed in then, once, and waited for afresh.
  if [[ $WAY == "sent to the pane's inbox"* ]]; then
    if idle; then
      WAY="typed into the pane once its turn ended with the inbox message unread"
      orca-ide terminal send --terminal "$H" --text "$MSG" --enter --json >/dev/null \
        || { wake refused "terminal send failed"; echo "answer-worker: terminal send to $H failed; the answer was not delivered" >&2; return 1; }
      wake sent
      LEFT=$WAIT; sleep 2; continue
    fi
  fi
  if [ "$LEFT" -le 0 ]; then
    [[ $WAY == "sent to the pane's inbox"* ]] || break
    # Issue 351: still mid-turn, the answer sits in its inbox, read at the pane's next check. That is said once, and the
    # check goes on until the tag is in the log or ACK seconds from the send have passed: an answer nobody read is not delivered.
    [ -n "$QUEUED" ] || { close_asks; QUEUED=1; echo "answer-worker: queued, not read yet: $H is still mid-turn after ${WAIT}s; the answer is in its inbox, read at its next check (tag $TAG). Still checking for up to ${ACK}s from the send. Do not send it again." >&2; }
    [ $((SECONDS - T0)) -lt "$ACK" ] || { echo "answer-worker: NOT acknowledged: the answer (tag $TAG) is still unread in $H's inbox after ${ACK}s; $H never ended its turn or read its inbox. Send it again, or look at the pane." >&2; return 1; }
  fi
  sleep 2; LEFT=$((LEFT - 2))
done
echo "answer-worker: NOT delivered: the answer was $WAY, but its tag $TAG is not in $H's session log (${LOG:-no log found for $WT}) after ${WAIT}s." >&2
return 1
}
# In main's own foreground the wait runs detached (issue 340): the answer is sent, so this returns at once, naming the
# log. Only an answer that is NOT delivered (exit 1 of the wait) comes to main, as a message; a delivered or queued one
# says nothing more. Anywhere else (a test, a script, the follower itself) the wait runs here and its code is the exit.
if [ -z "$FOLLOW" ] && pp_main_foreground; then
  FLOG=$PP_SCRATCH/answer-worker-$TAG.log
  mkdir -p "$PP_SCRATCH"
  # Its own session, so main's pane closing does not end it. perl's POSIX::setsid on every host: it execs in
  # place, so $! is the follower; Linux setsid(1) can fork, leaving $! a pid that already exited.
  DETACH=(perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec $ARGV[0]: $!\n"')
  ANSWER_WORKER_FOLLOW=1 ANSWER_WORKER_TAG=$TAG ANSWER_WORKER_WAY=$WAY ANSWER_WORKER_REPLIED=$REPLIED COMMANDECK_FOREGROUND=1 \
    nohup "${DETACH[@]}" bash -c 'log=$1; shift; "$@" > "$log" 2>&1; rc=$?
      [ "$rc" != 1 ] || bash "$0" question "answer-worker.sh: not delivered" "$(tail -n 5 "$log")" >/dev/null 2>&1' \
    "$HERE/to-main.sh" "$FLOG" bash "$HERE/answer-worker.sh" "$H" "$TEXT" "$Q" </dev/null >/dev/null 2>&1 &
  echo "answer-worker: sent to $H ($WAY), tag $TAG; whether it arrived is checked in the background (pid $!): $FLOG. Main hears only if it is NOT delivered. Do not send it again."
  exit 0
fi
confirm
exit $?
