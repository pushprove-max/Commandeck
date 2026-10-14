#!/usr/bin/env bash
# answer-worker.sh <terminal-handle|unit> <text> -- main's one way to answer a
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
# pane's session log; otherwise this exits 1 and says so.
#
# ANSWER_WORKER_WAIT: seconds to wait for the text in the log (default 60).
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/codex-helpers.sh"
H=${1:?usage: answer-worker.sh <terminal-handle|unit> <text>}; H=${H#terminal:}
TEXT=${2:?usage: answer-worker.sh <terminal-handle|unit> <text>}
if [ -d "$PP_WORKSPACES/$H" ]; then
  U=$H; H=$(pp_seat_pane "unit-$U" "$PP_WORKSPACES/$U")
  [ -n "$H" ] || { bash "$HERE/to-main.sh" --unit "$U" status "answer from main" "$TEXT" 2>/dev/null
    [ $? = 3 ] && echo "answer-worker: the Builder of $U is not running; the answer is queued and shown first when it starts again. Not delivered yet." >&2 \
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

rc=0; pane_is_busy "$H" || rc=$?
if [ "$rc" = 1 ]; then
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
  LOG=$("$HERE/read-verdict.sh" --state --worktree "$WT" --agent "$KIND" --current 2>/dev/null | sed -n 's/^session=//p')
  [ -n "$LOG" ] && grep -qF -- "$TAG" "$LOG" 2>/dev/null && { echo "answer-worker: delivered to $H ($WAY), tag $TAG"; exit 0; }
  # A pane that was mid-turn and has since ended its turn will never read its
  # inbox: the answer is typed in then, once, and waited for afresh.
  if [ "$WAY" = "sent to the pane's inbox" ]; then
    rc=0; pane_is_busy "$H" || rc=$?
    if [ "$rc" = 1 ]; then
      WAY="typed into the pane once its turn ended with the inbox message unread"
      orca-ide terminal send --terminal "$H" --text "$MSG" --enter --json >/dev/null \
        || { echo "answer-worker: terminal send to $H failed; the answer was not delivered" >&2; exit 1; }
      LEFT=$WAIT; sleep 2; continue
    fi
  fi
  [ "$LEFT" -gt 0 ] || break
  sleep 2; LEFT=$((LEFT - 2))
done
echo "answer-worker: NOT delivered: the answer was $WAY, but its tag $TAG is not in $H's session log (${LOG:-no log found for $WT}) after ${WAIT}s. A pane that is mid-turn reads its inbox only at its next check; run this again once its turn has ended." >&2
exit 1
