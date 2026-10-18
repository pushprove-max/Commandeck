#!/usr/bin/env bash
# answer-worker.sh <terminal-handle|unit> <text> [<question-id>] -- main's one way to answer a
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
# Either way the answer counts as delivered only when its text is in the
# pane's session log (exit 0). An inbox message to a pane still mid-turn when
# the wait ends is queued, not read yet (exit 2); anything else exits 1, NOT
# delivered. An answer that left main (delivered, queued in the inbox, or
# queued for a restart) closes the unit's question waiting on main in the
# decisions ledger: the one <question-id> names, or the only one open. With
# several open and none named, none is closed: one answer is not every answer.
#
# ANSWER_WORKER_WAIT: seconds to wait for the text in the log (default 60).
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/codex-helpers.sh"
H=${1:?usage: answer-worker.sh <terminal-handle|unit> <text> [<question-id>]}; H=${H#terminal:}
TEXT=${2:?usage: answer-worker.sh <terminal-handle|unit> <text> [<question-id>]}
Q=${3:-}
# close_asks -- answer the unit's question waiting on main in the decisions ledger (orca-wait.sh
# recorded it): the answer has left main, read or queued.
close_asks() {
  local u=${U:-} ids
  [ -n "$u" ] || case ${WT:-} in "$PP_WORKSPACES"/*) u=${WT#"$PP_WORKSPACES"/}; u=${u%%/*} ;; esac
  [ -n "$u" ] || return 0
  ids=$(bash "$HERE/decision.sh" list 2>/dev/null | jq -r --arg s "$u asks" --arg q "$Q" \
    '.[] | select(.answeredAt == null and .waitsOn == "main" and .source == $s and ($q == "" or .id == $q)) | .id')
  if [ -z "$ids" ]; then [ -z "$Q" ] || echo "answer-worker: no open question $Q from $u in the ledger; nothing closed" >&2; return 0; fi
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
WAIT=${ANSWER_WORKER_WAIT:-60}
# The tag is what is looked for in the log: the text itself may be re-wrapped.
TAG="answer-$(date +%s)-$$"
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
log_state
if idle; then
  WAY="typed into the pane"
  orca-ide terminal send --terminal "$H" --text "$MSG" --enter --json >/dev/null \
    || { echo "answer-worker: terminal send to $H failed; the answer was not delivered" >&2; exit 1; }
else
  WAY="sent to the pane's inbox"
  orca-ide orchestration send --to "$H" --type status --subject "answer from main" --body "$MSG" --json >/dev/null \
    || { echo "answer-worker: the inbox send to $H failed; the answer was not delivered" >&2; exit 1; }
fi

LEFT=$WAIT
while :; do
  log_state
  [ -n "$LOG" ] && grep -qF -- "$TAG" "$LOG" 2>/dev/null && { close_asks; echo "answer-worker: delivered to $H ($WAY), tag $TAG"; exit 0; }
  # A pane that was mid-turn and has since ended its turn will never read its
  # inbox: the answer is typed in then, once, and waited for afresh.
  if [ "$WAY" = "sent to the pane's inbox" ]; then
    if idle; then
      WAY="typed into the pane once its turn ended with the inbox message unread"
      orca-ide terminal send --terminal "$H" --text "$MSG" --enter --json >/dev/null \
        || { echo "answer-worker: terminal send to $H failed; the answer was not delivered" >&2; exit 1; }
      LEFT=$WAIT; sleep 2; continue
    fi
  fi
  [ "$LEFT" -gt 0 ] || break
  sleep 2; LEFT=$((LEFT - 2))
done
# Still mid-turn: the answer sits in its inbox, read at the pane's next check. Not a failure, and not read either.
[ "$WAY" = "sent to the pane's inbox" ] && { close_asks; echo "answer-worker: queued, not read yet: $H is still mid-turn after ${WAIT}s; the answer is in its inbox, read at its next check (tag $TAG). Do not send it again." >&2; exit 2; }
echo "answer-worker: NOT delivered: the answer was $WAY, but its tag $TAG is not in $H's session log (${LOG:-no log found for $WT}) after ${WAIT}s." >&2
exit 1
