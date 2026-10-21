#!/usr/bin/env bash
# builder-fresh-round.sh <handle> <hand-off file> [<seat record>] -- start a Builder's next round in a fresh
# session of the same pane: wait until the pane is idle and stays idle, type /clear, wait for the new session,
# then type the pointer to the hand-off file. Same pane, handle, Orca task and dispatch; new transcript. With a
# seat record, the new session's id is appended as its last session= line, which main-watch.sh reads, so main
# watches the new log and not the cleared one.
# builder-codex-pass.sh runs it after a NO-GO pass, and builder-add-work.sh when main adds work, each as a plain
# background child. It waits while the pane is busy, until the pane is gone or Orca fails 5 tries in a row; one
# hand-off to a pane at a time.
# A hand-off that does not start gets nothing typed: the reason and a re-run line go to stderr and to main
# (to-main.sh: a log alone was never read), the exit is 1, and the round stays in the old session.
# Self-test: bash scripts/__tests__/builder-fresh-round.test.sh
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
H=${1:?usage: builder-fresh-round.sh <handle> <hand-off file> [<seat record>]}
HAND=${2:?usage: builder-fresh-round.sh <handle> <hand-off file> [<seat record>]}
REC=${3:-}
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
SETTLE=${COMMANDECK_FRESH_ROUND_SETTLE_SECONDS:-20}
# idle <ms> -- the pane is idle within <ms>. Orca's answer is kept in W: a busy pane is a wait that timed out.
idle() { W=$(orca-ide terminal wait --terminal "$H" --for tui-idle --timeout-ms "$1" --json 2>&1); }
# tell <reason> -- the reason on stderr, and to main: a hand-off that never started is news only main can act on.
# Main first, so the log's last line is written once nothing more runs.
# A question, not an escalation: Orca refuses an escalation from a pane with no dispatch of its own.
tell() {
  local d; d=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  bash "$d/to-main.sh" question "fresh round not started: ${HAND##*/}" "builder-fresh-round: $1
re-run: bash $(printf %q "$d/builder-fresh-round.sh") $(printf %q "$H") $(printf %q "$HAND")${REC:+ $(printf %q "$REC")}" >/dev/null 2>&1 \
    || [ $? = 3 ] || echo "builder-fresh-round: telling main failed too" >&2   # 3: queued for main's next session
  echo "builder-fresh-round: $1" >&2
  exit 1
}
fail() { tell "$1; the round of $HAND stays in the old session."; }
# send <text> -- type <text> and Enter into the pane; Orca's answer is kept for the reason when it fails.
send() { SENT=$(orca-ide terminal send --terminal "$H" --text "$1" --enter --json 2>&1) || { SENT=$(printf '%s' "$SENT" | tr -s '\n' ' ' | cut -c1-300); return 1; }; }
# listed -- 0: Orca's list holds $H live; 1: it answers without it (gone); 2: no list (it failed, or is not JSON).
listed() {
  orca-ide terminal list --json 2>/dev/null | jq -e --arg h "$H" '(.result | if type == "array" then . else .terminals end)
    | if type == "array" then any(.[]; .handle == $h and .orphaned != true) else error("no list") end' >/dev/null 2>&1
  local r=$?; [ "$r" -le 1 ] || r=2; return "$r"
}
# A second hand-off to the same pane waits here until the first exits: two would interleave their typing.
mkdir -p "$PP_SCRATCH" && exec 9>>"$PP_SCRATCH/fresh-round-$H.lock" && flock 9 || fail "cannot lock $PP_SCRATCH/fresh-round-$H.lock; nothing typed"
# Idle twice, SETTLE apart: a background-task notice can wake the old session just after it ends its turn, and
# /clear typed into a busy turn is lost. A busy pane (the wait timed out) or one blocked on its user (Orca exits 1
# with wait.satisfied false) is waited on 5 minutes a try, for as long as it is listed. Any other failed wait,
# the first or the second, or a list that does not answer, is Orca failing: 5 in a row and main is told, since
# retried for good it would hold the lock and stall every later hand-off unseen. The sleep after every try
# keeps an Orca that answers at once from spinning the loop.
DOWN=0 MS=300000
while :; do
  if idle "$MS"; then
    [ "$MS" = 1000 ] && break
    MS=1000
  else
    MS=300000
    if jq -e '.error.code == "timeout" or .result.wait.satisfied == false' >/dev/null 2>&1 <<<"$W"; then
      DOWN=0
    else
      listed; case $? in
        1) fail "pane $H is gone; nothing typed" ;;
        0) why="wait: $(printf '%s' "$W" | tr -s '\n' ' ' | cut -c1-200)" ;;
        *) why="wait and list gave no answer" ;;
      esac
      DOWN=$((DOWN + 1)); [ "$DOWN" -lt 5 ] || fail "Orca failed 5 times in a row ($why); nothing typed"
    fi
  fi
  sleep "$SETTLE"
done
STAMP=$(mktemp) || fail "cannot make a temp file; nothing typed"
trap 'rm -f "$STAMP"' EXIT
send /clear || fail "typing /clear into $H failed (${SENT:-no answer}); nothing typed"
idle 120000 || fail "typed /clear but the new session of $H was not idle within 120s; the hand-off pointer was not typed"
# Issue 289: /clear keeps the model the pane opened with; from fix round 2 on, a Builder not on Opus steps up.
N=$(sed -n 's/.*-fix-r\([0-9][0-9]*\)\.md$/\1/p' <<<"${HAND##*/}")
if [ "${N:-0}" -ge 2 ] && [ -n "$REC" ] && [ -f "$REC" ]; then
  M=$(sed -n 's/^model=//p' "$REC" | tail -1)
  [ -n "$M" ] || M=$(sed -n 's/^cmd=.*--model[ =]\([^ ]*\).*/\1/p' "$REC" | tail -1)
  if [[ $M != *opus* ]]; then
    send "/model opus" || fail "typed /clear but typing /model opus into $H failed (${SENT:-no answer})"
    idle 120000 || fail "typed /model opus but $H was not idle within 120s; the hand-off pointer was not typed"
    echo model=opus >> "$REC"
  fi
fi
# Issue 278: the new session retitles its pane; give it back its role and unit.
U=$(sed -n 's/^unit=//p' "$REC" 2>/dev/null | tail -1)
[[ -n $U || $HAND != */.claude/briefs/* ]] || U=$(basename "${HAND%/.claude/briefs/*}")
. "$(dirname "${BASH_SOURCE[0]}")/codex-helpers.sh"
[ -z "$U" ] || timeout 8 orca-ide terminal set-pane-title --terminal "$H" --title "$(pane_title builder "$U")" >/dev/null 2>&1 || true
send "Your task spec is the file $HAND. Read all of it now and do what it says." \
  || fail "typed /clear but typing the hand-off pointer into $H failed (${SENT:-no answer})"
echo "builder-fresh-round: $H cleared and handed $HAND"
[ -n "$REC" ] && [ -f "$REC" ] || exit 0
# The new session is the log written since /clear that carries the pointer, other than the one the record names.
OLD=$(sed -n 's/^session=//p' "$REC" | tail -1)
PROJ=$HOME/.claude/projects/$(pp_slug "${HAND%/.claude/briefs/*}")
NEW=
for _ in $(seq 30); do
  NEW=$(find "$PROJ" -maxdepth 1 -name '*.jsonl' -newer "$STAMP" ! -name "${OLD:-none}.jsonl" -exec grep -lF -- "$HAND" {} + 2>/dev/null | head -1)
  [ -n "$NEW" ] && break
  sleep 2
done
[ -n "$NEW" ] || tell "no new session log in $PROJ names $HAND after 60s, so the pane may never have taken it; $REC still names session ${OLD:-none}"
NEW=${NEW##*/}
echo "session=${NEW%.jsonl}" >> "$REC"
echo "builder-fresh-round: $REC now names session ${NEW%.jsonl}"
