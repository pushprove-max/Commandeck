#!/usr/bin/env bash
# builder-fresh-round.sh <handle> <hand-off file> [<seat record>] -- start a Builder's next round in a fresh
# session of the same pane: wait until the pane is idle and stays idle, type /clear, wait for the new session,
# then type the pointer to the hand-off file. Same pane, handle, Orca task and dispatch; new transcript. With a
# seat record, the new session's id is appended as its last session= line, which main-watch.sh reads, so main
# watches the new log and not the cleared one.
# builder-codex-pass.sh runs it after a NO-GO pass, and builder-add-work.sh when main adds work, each as a plain
# background child. It waits while the pane is busy (saying so, and for how long), until the pane is gone, Orca fails
# 5 tries in a row, or MAXW seconds (COMMANDECK_FRESH_ROUND_MAX_SECONDS, 1800) pass, when main is told; one hand-off
# to a pane at a time. Orca's accepted:false on a typing is retried 3 times and said.
# A hand-off that does not start gets nothing typed: the reason and a re-run line go to stderr and to main
# (to-main.sh: a log alone was never read), the exit is 1, and the round stays in the old session.
# Self-test: bash scripts/__tests__/builder-fresh-round.test.sh
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
H=${1:?usage: builder-fresh-round.sh <handle> <hand-off file> [<seat record>]}
HAND=${2:?usage: builder-fresh-round.sh <handle> <hand-off file> [<seat record>]}
REC=${3:-}
ARGS=("$@")
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
SETTLE=${COMMANDECK_FRESH_ROUND_SETTLE_SECONDS:-20}
MAXW=${COMMANDECK_FRESH_ROUND_MAX_SECONDS:-1800}   # the longest this waits on a busy pane before telling main
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
# A one-off typing failure is retried once (a refused setting is a config error, told at once), whole and under the lock already held (fd 9 stays open across the exec, and
# the retry does not reopen it); only a failed retry tells main.
fail() {
  if [ -n "${LOCKED:-}" ] && [ -z "${PP_FRESH_ROUND_RETRY:-}" ]; then
    echo "builder-fresh-round: $1; retrying the hand-off once" >&2
    rm -f "${STAMP:-}"
    PP_FRESH_ROUND_RETRY=1 exec bash "${BASH_SOURCE[0]}" "${ARGS[@]}"
  fi
  tell "$1; the round of $HAND stays in the old session."
}
# send <text> -- type <text> and Enter into the pane; Orca's answer is kept for the reason when it fails. Orca may take
# the request and type nothing (accepted:false: a paired phone can hold the pane's keyboard, issue 342): nothing was
# typed, so it is retried in place, 3 tries SETTLE apart, each refusal said; only a pane that refuses all 3 fails.
send() {
  local try
  for try in 1 2 3; do
    SENT=$(orca-ide terminal send --terminal "$H" --text "$1" --enter --json 2>&1) || { SENT=$(printf '%s' "$SENT" | tr -s '\n' ' ' | cut -c1-300); return 1; }
    jq -e 'any(.. | objects | select(has("accepted")) | .accepted; . == false)' >/dev/null 2>&1 <<<"$SENT" || return 0
    SENT="Orca took no input (accepted:false)"
    echo "builder-fresh-round: Orca refused the typing (accepted:false) into $H, try $try of 3" >&2
    [ "$try" = 3 ] || sleep "$SETTLE"
  done
  return 1
}
# listed -- 0: Orca's list holds $H live; 1: it answers without it (gone); 2: no list (it failed, or is not JSON).
listed() {
  orca-ide terminal list --json 2>/dev/null | jq -e --arg h "$H" '(.result | if type == "array" then . else .terminals end)
    | if type == "array" then any(.[]; .handle == $h and .orphaned != true) else error("no list") end' >/dev/null 2>&1
  local r=$?; [ "$r" -le 1 ] || r=2; return "$r"
}
# A second hand-off to the same pane waits here until the first exits: two would interleave their typing.
if [ -z "${PP_FRESH_ROUND_RETRY:-}" ]; then
  mkdir -p "$PP_SCRATCH" && exec 9>>"$PP_SCRATCH/fresh-round-$H.lock" \
    && { flock -n 9 || { echo "builder-fresh-round: another hand-off to $H holds its lock; waiting for it" >&2; flock 9; }; } || fail "cannot lock $PP_SCRATCH/fresh-round-$H.lock; nothing typed"
fi
LOCKED=1
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
      # Issue 342: a busy pane is waited on, but not for ever and not in silence. Past MAXW seconds main is told (tell, not
      # fail: a retry would wait the whole limit again) and the re-run line is its to use when the pane idles.
      [ "$SECONDS" -lt "$MAXW" ] || tell "pane $H stayed busy for $SECONDS s (limit $MAXW s, COMMANDECK_FRESH_ROUND_MAX_SECONDS); nothing typed; the round of $HAND stays in the old session."
      echo "builder-fresh-round: pane $H is busy (mid-turn, or waiting on its user); waiting, $SECONDS s of $MAXW s used" >&2
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
# Issue 313, the fixer: /clear keeps the model and effort the pane opened with. Only a fix hand-off
# (<unit>-fix-r<N>.md) switches anything, and its count is that unit's fix hand-offs in the folder (not N, the pass
# number), so it resets per build. The first runs on fixer first, every later one on fixer's model and effort (both
# Opus high; builder: as the Builder launched, a per-build raise included); /plugin config keys beat routing's.
# fixerEnabled=false keeps the Builder's launched model and effort, switching back a pane an earlier round moved. Each
# switch is typed only where the pane differs, and the record says the rule.
if [[ ${HAND##*/} =~ ^(.+)-fix-r[0-9]+\.md$ ]] && [ -n "$REC" ] && [ -f "$REC" ]; then
  FU=${BASH_REMATCH[1]}
  K=$(ls "${HAND%/*}/$FU"-fix-r*.md 2>/dev/null | grep -cE -- '-fix-r[0-9]+\.md$')
  # pick <var> <field> <routing path> -- the key's value, else routing's; a value the key does not take stops the hand-off.
  SRC=routing
  pick() { local v rc=0; v=$(pp_role_option fixer "$2" 2>&1) || rc=$?
    case $rc in 0) SRC=config ;; 1) v=$(jq -r "$3 // empty" "$(pp_routing)") ;; *) tell "${v#REFUSED: }; nothing switched, the hand-off pointer was not typed; the round of $HAND stays in the old session." ;; esac
    printf -v "$1" '%s' "$v"; }
  rc=0; EN=$(pp_role_option fixer enabled 2>&1) || rc=$?
  [ "$rc" != 2 ] || tell "${EN#REFUSED: }; nothing switched, the hand-off pointer was not typed; the round of $HAND stays in the old session."
  # The pane's model and effort now: the last switch the record names, else the launch's own command.
  CM=$(sed -n 's/^model=//p' "$REC" | tail -1); [ -n "$CM" ] || CM=$(sed -n 's/^cmd=.*--model[ =]\([^ ]*\).*/\1/p' "$REC" | tail -1)
  CE=$(sed -n 's/^effort=//p' "$REC" | tail -1); [ -n "$CE" ] || CE=$(sed -n 's/^cmd=.*--effort[ =]\([^ ]*\).*/\1/p' "$REC" | tail -1)
  if [ "$EN" = false ]; then RULE=off WM=builder WE=builder
  elif [ "$K" -le 1 ]; then pick WM firstModel .roles.fixer.first.model; pick WE firstEffort .roles.fixer.first.effort; RULE=first:$SRC
  else pick WM model .roles.fixer.model; pick WE effort .roles.fixer.effort; RULE=later:$SRC; fi
  # builder: the Builder's launched model or effort, which the pane keeps.
  [ "$WM" != builder ] || WM=$(sed -n 's/^cmd=.*--model[ =]\([^ ]*\).*/\1/p' "$REC" | tail -1)
  [ "$WE" != builder ] || WE=$(sed -n 's/^cmd=.*--effort[ =]\([^ ]*\).*/\1/p' "$REC" | tail -1)
  if [ -n "$WM" ] && [[ $CM != *"$WM"* ]]; then
    send "/model $WM" || fail "typed /clear but typing /model $WM into $H failed (${SENT:-no answer})"
    idle 120000 || fail "typed /model $WM but $H was not idle within 120s; the hand-off pointer was not typed"
  fi
  # /effort takes in place in an idle Claude pane (checked on a live pane for issue 313), as seat.sh effort sends it.
  if [ -n "$WE" ] && [ "$CE" != "$WE" ]; then
    send "/effort $WE" || fail "typed /clear but typing /effort $WE into $H failed (${SENT:-no answer})"
    idle 120000 || fail "typed /effort $WE but $H was not idle within 120s; the hand-off pointer was not typed"
  fi
  { [ -z "$WM" ] || echo "model=$WM"; [ -z "$WE" ] || echo "effort=$WE"; } >> "$REC"
  echo "fixer=$RULE" >> "$REC"
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
# The pane that ran this pass is the live Builder. A relaunch leaves its record on the dead handle, and the first-line
# readers (main-watch, board, pp_watched_seats) would keep watching and protecting that one (host issue 3011): rewrite
# the line in place, never append. A record with no handle= line is left alone. The old pane stays as prior_pane= (a
# key with no "handle=" in it): a question it sent still holds the task (pp_task_close).
CUR=$(sed -n 's/^handle=//p' "$REC" | head -1)
if [ -n "$CUR" ] && [ "$CUR" != "$H" ]; then
  awk -v h="$H" -v o="$CUR" '!d && /^handle=/ { print "handle=" h; d = 1; next } { print } END { print "prior_pane=" o }' "$REC" > "$REC.tmp" && mv "$REC.tmp" "$REC" \
    && echo "builder-fresh-round: $REC now names pane $H"
fi
# The new session is the log written since /clear that carries the pointer, other than the one the record names.
OLD=$(sed -n 's/^session=//p' "$REC" | tail -1)
PROJ=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(pp_slug "${HAND%/.claude/briefs/*}")
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
