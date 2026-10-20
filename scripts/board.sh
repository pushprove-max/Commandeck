#!/usr/bin/env bash
# board.sh -- the ONE call main makes at resume and after every wake: the run
# id, each worktree with its branch and diffstat, the open tasks, the seat
# handles, the live loop units, main-watch's state, and each unit's brief mtime
# and newest pass verdict.
#
# Resuming from a checkpoint cost about eight tool calls of rediscovery, and a
# third of those were wrong guesses (the workspaces root, task-list's run id)
# that then had to be redone. A fresh context after /clear pays that every
# time. Guessing an input is the expensive failure, so this prints the inputs.
# It opens no worktree, acks no message and closes no task. In the main
# checkout it writes two things: the run id file, when Orca's run differs from
# it, and the terminal's binding to that run, when the terminal is unbound.
# Usage: board.sh [--full] [unit]   -- with a unit, only that unit's rows; --full uncut.
#        board.sh --unit <unit> --seats   -- each seat record of the unit: role, handle, phase, verdict.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel)
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
WS=$PP_WORKSPACES
. "$(dirname "${BASH_SOURCE[0]}")/host-services.sh"
SCRATCH=$PP_SCRATCH
# A seat's launch runs in the background (issue 233): its record's last phase= line says where it is. No Orca call.
if [ "${1-}" = --unit ]; then
  [ -n "${2-}" ] && [ "${3-}" = --seats ] || { echo "usage: board.sh --unit <unit> --seats" >&2; exit 2; }
  for r in "$SCRATCH"/seat-"$2"-*.txt; do
    [ -f "$r" ] && [ "$(sed -n 's/^unit=//p' "$r" | head -1)" = "$2" ] || continue
    line=; for k in role handle phase verdict; do v=$(sed -n "s/^$k=//p" "$r" | tail -1); line+=" ${v:--}"; done
    echo " $line"
  done
  exit 0
fi
# Issue 223: thirty worktrees filled main's context. By default each section shows at most 12 lines and the
# board 3,000 bytes; section headers and alert lines always print, and the last line names the whole board's file.
# shortcut: one board-<pid>.txt per cut board, never pruned; prune by age if the folder grows.
FULL=0; [ "${1-}" != --full ] || { FULL=1; shift; }
if [ "$FULL" = 0 ] && [ -z "${BOARD_UNCUT:-}" ]; then
  mkdir -p "$SCRATCH" || exit 1
  B=$SCRATCH/board-$$.txt
  BOARD_UNCUT=1 bash "${BASH_SOURCE[0]}" "$@" > "$B"; rc=$?
  awk -v f="$B" '/^== / { s = 0 } { s++ }
    /^ *[A-Z][A-Z ,-]{5,}( --|:)|^== |^RUN=/ { print; n += length($0) + 1; next }
    s <= 13 && n + length($0) < 2800 { print; n += length($0) + 1; next } { cut++ }
    END { if (cut) print "board: " cut " lines not shown (whole board: " f "; board.sh --full)"; exit !cut }' "$B" || rm -f "$B"
  exit $rc
fi
RUN=$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE" || true)
ONLY=${1:-}
# The project's run is the one main's own terminal is bound to, and this is
# where it is written down for the watcher and every pane. Orca's machine-wide
# current-run file is never read: another project on the machine moves it.
# Main checkout only: a worktree pane is unbound, or bound to something else.
IS_MAIN=0 CUR=
if [ "$(git rev-parse --path-format=absolute --git-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ]; then
  IS_MAIN=1
  CUR=$(orca-ide orchestration run-current --json 2>/dev/null | jq -r '.result.run.id // empty')
  if [ -n "$CUR" ] && [ "$CUR" != "$RUN" ] && mkdir -p "$SCRATCH" && printf '%s\n' "$CUR" > "$PP_RUN_FILE.$$" && mv "$PP_RUN_FILE.$$" "$PP_RUN_FILE"; then RUN=$CUR; fi
fi

echo "RUN=${RUN:-NONE}  WS=$WS  SCRATCH=$SCRATCH  ROOT=$ROOT"
# That RUN is the file's value, not this terminal's binding. /clear gives main a
# new handle with no run bound, and an unbound main cannot reply to a worker's
# question or create a task -- it finds out only when a reply is refused with
# consumer_fenced, having already spent the call.
#
# BIND ONLY FROM UNBOUND, never rebind. A rebind moves the run's coordinator
# terminal and fences whichever driver holds it, so this must not fire on the
# after-every-wake call, where main is already bound. From UNBOUND there is
# nothing to fence, and that is the restart case: `Read -> board.sh ->
# orca-ide orchestration run-use` ran 14 times on 2026-09-15 as three separate
# turns, because main's next action after an unbound board is always this exact
# call. Doing it here spends the same one call inside a turn main already paid
# for.
# Main checkout only: a worktree pane (the relay pane, a worker) is always unbound, and
# binding there moves main's run to it and leaves main's inbox empty.
if [ "$IS_MAIN" = 1 ] && [ -z "$CUR" ]; then
  if [ -n "$RUN" ] && orca-ide orchestration run-use --id "$RUN" >/dev/null 2>&1; then
    echo "BOUND this terminal to $RUN (it was unbound; no rebind, so no driver was fenced)"
  else
    NORUN=; [ -n "$RUN" ] || NORUN="; this project has no run yet: orca-ide orchestration run-create makes one, and the next board.sh records it"
    echo "THIS TERMINAL IS NOT BOUND TO A RUN: orca-ide orchestration run-use --id ${RUN:-<run_id>} before any reply, task-create or dispatch$NORUN"
  fi
fi
echo "main: $(git -C "$ROOT" log --oneline -1) | $(git -C "$ROOT" status --porcelain | wc -l) dirty | $(git -C "$ROOT" log --oneline '@{u}..' 2>/dev/null | wc -l) unpushed"

echo
echo "== worktrees"
# Orca's own per-pane agent state is the only "this worker has finished" signal
# for a pane with no marker; its `working` is never proof of work (see the
# driver lines' log= field). A loop-dispatched implementer has no seat record, so the
# stopped-panes section below cannot see it, and a marker the worker forgot to
# print never arrives: on 2026-09-19 three implementers were
# re-dispatched in a row and a chain-fixes fixer sat finished for twenty
# minutes, because nothing main could call said the pane was done.
# COMMANDECK_AGENTS and COMMANDECK_DRIVERS are test seams: they carry what the two
# RPCs would have returned, so the stranded-worker rule below is checkable
# without Orca or systemd.
PS_JSON=$(timeout 8 orca-ide worktree ps --json 2>/dev/null)
AGENTS=${COMMANDECK_AGENTS:-$(jq -r '
  .result.worktrees[]? | select(.isMainWorktree != true) | select(.isArchived != true)
  | "\(.displayName)\t" + ((.agents // []) | map("\(.agentType):\(.state)") | join(" "))' <<<"$PS_JSON" 2>/dev/null)}
# Driver unit names carry the unit: `loop-<unit>-<epoch>.service`.
DRIVERS=${COMMANDECK_DRIVERS:-$(hs_list 'loop-*' 'drive-*' --no-legend --plain | awk '{print $1}')}
STRANDED=""
for wt in "$WS"/*/; do
  u=$(basename "$wt")
  [ -z "$ONLY" ] || [ "$u" = "$ONLY" ] || continue
  [ -d "$wt/.git" ] || [ -f "$wt/.git" ] || continue
  br=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)
  dirty=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l)
  stat=$(git -C "$wt" diff --stat 2>/dev/null | tail -1 | xargs)
  ag=$(awk -F'\t' -v u="$u" '$1 == u { print $2 }' <<<"$AGENTS")
  # orca-says: Orca's agent state is a claim, not proof of work; the
  # driver lines below carry the worker's session-log truth.
  echo "  $u [$br] dirty=$dirty${ag:+ orca-says=$ag} ${stat:+| $stat}"
  # Trouble only when EVERY pane on this worktree has finished while its driver
  # is still running. A round keeps finished reviewer panes warm beside a live
  # worker, so any `working` agent means the unit is progressing normally.
  case "$ag" in
    *:done*)
      case "$ag" in *:working*) ;; *)
        # Exact name: `loop-<u>-` alone also matches a sibling `<u>-sentinel`.
        # shellcheck disable=SC2086
        # Not waiting: since its last dispatch, its newest log settled on the
        # marker, or settled and then launched a seat (`<role>=... launched=`, `handles:`).
        dlog=$(ls -t "$SCRATCH/scratchpad/$u"-{drive,loop}-*.log 2>/dev/null | head -1)
        if grep -qxE "(loop|drive)-${u//./\\.}-[0-9]+\.service" <<<"$(printf '%s\n' $DRIVERS)" \
           && ! awk '/implementer=term_/ { s = set = 0; next }
                     /wait settled on / { set = 1; if (/settled on marker/) s = 1 }
                     set && (/ launched=[0-9]/ || /^handles: /) { s = 1 }
                     END { exit !s }' "${dlog:-/dev/null}"; then
          # A budget-spent seat leaves a handoff and no marker; the driver
          # hands over within minutes. One older than 10 minutes was never picked up.
          ho=$wt/.claude/briefs/$u-handoff.md
          if [ -f "$ho" ] && [ -n "$(find "$ho" -mmin -10)" ] && { [ -z "$dlog" ] || [ "$ho" -nt "$dlog" ]; }; then
            STRANDED+="  HANDOVER PENDING -- $u: seat ran out of budget and wrote its handoff; the driver hands it to a fresh pane"$'\n'
          else
            STRANDED+="  WORKER DONE, DRIVER STILL WAITING -- $u: every pane finished, its driver is still waiting for a marker it will never get"$'\n'
          fi
        fi ;;
      esac ;;
  esac
  # The brief is the plan author's real done-signal; "turn complete" fires on
  # any turn that prints a marker, so main judges by the file, never by the pane's echo.
  while IFS= read -r b; do
    [ -f "$b" ] || continue
    echo "      brief $(stat -c '%y' "$b" | cut -c1-16)  $(basename "$b")"
  done < <(pp_unit_briefs "$wt/.claude/briefs" "$u")
  # The newest pass by round number, with its verdict: a unit whose last pass ended NO-GO is
  # being fixed, not waiting to merge, whatever its pane says.
  rn=0 rf=
  while IFS= read -r b; do
    n=${b##*/}; n=${n#"$u-r"}; n=${n%-reports.md}
    [[ $n =~ ^[0-9]+$ ]] && [ $((10#$n)) -ge "$rn" ] && { rn=$((10#$n)); rf=$b; }
  done < <(pp_unit_briefs "$wt/.claude/briefs" "$u" | grep -- '-reports\.md$')
  if [ -n "$rf" ]; then
    counts=$(grep -oE '^[[:space:]]*[-*] \[P[0-3]\]' "$rf" | grep -oE 'P[0-3]' | sort | uniq -c | awk '{ printf "%s%s %s", (NR > 1 ? ", " : ""), $2, $1 }')
    echo "      pass r$rn $(sed -n 's/^Pass: //p' "$rf" | head -1): $(grep -v '^[[:space:]]*$' "$rf" | tail -1)${counts:+ ($counts)}"
  fi
done
# Printed after the list so it is the last thing read.
[ -z "$STRANDED" ] || printf '%s' "$STRANDED"

echo
echo "== open tasks"
if [ -n "$RUN" ]; then
  orca-ide orchestration task-list --run "$RUN" --json 2>/dev/null \
    | jq -r '.result.tasks[]
             | select(.status != "completed" and .status != "failed")
             | "  \(.id)  \(.status)  \(.display_name[0:64])"' \
    || echo "  (task-list unavailable)"
else
  echo "  (no run bound)"
fi

echo
echo "== seats (live worktrees only)"
# Seat records are never deleted, so the whole history of every merged unit is
# on disk. Only a unit whose worktree still exists can still be waited on.
#
# One awk names every record's unit and worktree (a planner's is <unit>-plan for a unit planned before 0.18.0), and only a
# live worktree's record is opened: a process or three per record (1,044 records on 2026-10-11) took 16 s.
SEATS=()
while IFS=$'\x1f' read -r f u w; do
  [ -n "$u" ] && [ -d "$WS/${w:-$u}" ] && SEATS+=("$f")
done < <(awk -v OFS=$'\x1f' 'function out() { if (f != "") print f, v["unit"], v["worktree"] }
  FNR == 1 { out(); f = FILENAME; split("", v) }
  /^(unit|worktree)=/ { k = substr($0, 1, index($0, "=") - 1); if (!(k in v)) v[k] = substr($0, length(k) + 2) }
  END { out() }' "$SCRATCH"/seat-*.txt 2>/dev/null)
for r in ${SEATS[@]+"${SEATS[@]}"}; do
  u=$(grep '^unit=' "$r" | cut -d= -f2)
  [ -z "$ONLY" ] || [ "$u" = "$ONLY" ] || continue
  h=$(grep '^handle=' "$r" | cut -d= -f2)
  [ -n "$h" ] || continue
  echo "  $u $(grep '^role=' "$r" | cut -d= -f2) $h $(grep '^task=' "$r" | cut -d= -f2)"
done

echo
echo "== panes that have stopped, and their last words"
# THE QUESTION THIS ANSWERS IS "what is unit X waiting for", and it cost five
# calls by hand on 2026-09-15: journalctl, the run log, a blocked pane read,
# read-verdict, then the raw Codex log, to learn that wt775's plan author had
# stopped asking main for a stored-row count nobody was going to give it.
#
# NOT a stall list, and deliberately not filtered into one. A plan-author that
# ended on PLAN-DONE appears here beside one that ended on PLAN-BLOCKED, and
# main tells them apart by reading two words. Deciding which is which needs each
# seat's expected marker, and a filter that guesses wrong hides the one line
# this section exists to show.
#
# A seat whose driver already collected it is gone from the terminal list, so
# the live-pane filter is what keeps merged units' old seat records out.
# ponytail: read-verdict costs about a second per seat, so these run in
# parallel rather than being made cheaper. Serial, fourteen seats added
# fifteen seconds to every wake.
LIVE=$(orca-ide terminal list --json 2>/dev/null || true)
STOPPED=$(mktemp -d)
trap 'pp_rm_rf "$STOPPED"' EXIT
for r in ${SEATS[@]+"${SEATS[@]}"}; do
  u=$(grep '^unit=' "$r" | cut -d= -f2)
  [ -z "$ONLY" ] || [ "$u" = "$ONLY" ] || continue
  h=$(grep '^handle=' "$r" | cut -d= -f2)
  [ -n "$h" ] || continue
  # Shell glob, never `printf | grep -q`: grep exits on the match, printf takes
  # SIGPIPE writing the rest, and pipefail then reports a LIVE pane as gone.
  # Same bug that killed a driver in seat.sh wait on 2026-09-15.
  [ "${LIVE#*"$h"}" = "$LIVE" ] && continue
  role=$(grep '^role=' "$r" | cut -d= -f2)
  launched=$(grep '^launched=' "$r" | cut -d= -f2)
  (
    msg=$(bash "$PP_SCRIPTS/read-verdict.sh" "$h" 5 "" "" "" "" "" "${launched:-0}" 2>/dev/null)
    [ $? -eq 5 ] || exit 0
    # tail -n +4 drops read-verdict's own three-line heading; what is left is
    # the pane's last message, which is the only part main has not already got.
    printf '  %s %s: %s\n' "$u" "$role" \
      "$(printf '%s' "$msg" | tail -n +4 | tr '\n' ' ' | cut -c1-200)" > "$STOPPED/$u-$role"
  ) &
done
wait
if [ -n "$(ls -A "$STOPPED" 2>/dev/null)" ]; then cat "$STOPPED"/*; else echo "  (none)"; fi

echo
echo "== finished panes (close with close-done-panes.sh --close)"
# A finished pane on a live unit is in no wake and no seat record, and main may
# not list terminals itself; this is the only place its handle reaches main.
done_panes=$(COMMANDECK_PS_JSON="$PS_JSON" COMMANDECK_TERMINALS_JSON="$LIVE" COMMANDECK_DRIVERS="$DRIVERS" \
  bash "$PP_SCRIPTS/close-done-panes.sh" 2>&1 | awk -F'\t' -v u="$ONLY" 'u == "" || $2 == u')
if [ -n "$done_panes" ]; then sed 's/^/  /' <<<"$done_panes"; else echo "  (none)"; fi

echo
echo "== loops and main-watch"
# loop-run.sh names its unit after the SCRIPT it drives, so a unit-drive run is
# `drive-<unit>-<epoch>` and a unit-loop run is `loop-<unit>-<epoch>`. Matching
# only `loop-*` hid a live driver, which reads as "nothing is running".
# `run-*` needs the .service suffix: systemd's own transient scopes and mounts
# are all named run-*, and the bare glob buried the drivers under 25 of them.
# A driver line carries its worker's session-log truth, read from the task the
# driver last logged (`task=`), because Orca's `working` has kept a spent seat
# "busy" for 42 minutes.
seat_truth() { # worktree task -- log=running|idle <N>m|unknown, outstanding, overdue, last words
  local st; st=$(timeout 20 bash "$PP_SCRIPTS/read-verdict.sh" --state --worktree "$1" --task "$2" 2>/dev/null)
  kv() { sed -n "s/^$1=//p" <<<"$st" | head -1; }
  local log idle
  idle=$(kv idle_seconds)
  case "$(kv state)" in
    complete) if [ -n "$idle" ]; then log="idle $((idle / 60))m"; else log=running; fi ;;
    running) log=running ;;
    *) log="unknown ($(kv reason))" ;;
  esac
  printf 'log=%s%s%s last="%s"' "$log" "$(kv outstanding | sed 's/^./ outstanding=&/')" \
    "$(kv overdue | sed 's/^./ overdue=&/')" "$(kv last_message | cut -c1-100)"
}
hs_list --no-legend >/dev/null 2>&1 || echo "  SERVICE STATE UNKNOWN: the service manager gave no answer; live drivers and chains may be missing below"
hs_list 'loop-*' 'drive-*' 'chain-*' 'run-*.service' --no-legend --plain \
  | awk 'NF {print $1, $3 "/" $4}' \
  | while read -r svc st; do
      line="  $svc $st"
      case "$svc" in
        loop-*|drive-*)
          # loop-<unit>-<epoch>.service logs to scratchpad/<unit>-loop-<epoch>.log.
          n=${svc%.service}; u=${n#*-}; u=${u%-*}
          task=$(grep -o 'task=task_[0-9a-z]*' "$SCRATCH/scratchpad/$u-${n%%-*}-${n##*-}.log" 2>/dev/null | tail -1)
          [ -z "$task" ] || [ ! -d "$WS/$u" ] || line+=" | $(seat_truth "$WS/$u" "${task#task=}")" ;;
      esac
      printf '%s\n' "$line"
    done || true
# The certification host and its state, job or no job: a chain that cannot
# start (bad switch, no peer, host asleep) must show its reason here, not
# silence. The last chain's final log line is where an unreachable peer's SSH
# error lands; the board never opens an SSH session itself.
if CH=$(hs_chain_host); then
  [ "$(hs_os)" = Darwin ] && here=mac || here=pc
  via=local
  [ "$CH" = "$here" ] || via="ssh $(tr -d '[:space:]' 2>/dev/null < "$HOME/.config/devenv/peer")"
  last=$(ls -t "$SCRATCH"/scratchpad/chain-"$CH"-*.log 2>/dev/null | grep -E "/chain-$CH-[0-9]+\.log\$" | head -1)
  if [ "$via" = "ssh " ]; then state="WAITING: no peer named in ~/.config/devenv/peer, so no chain can start"
  elif grep -q . <<<"$(hs_list --state=active "chain-$CH-*" --no-legend --plain 2>/dev/null)"; then state="running"
  elif [ -n "$last" ]; then state="idle; last $(basename "$last" .log): $(tail -1 "$last" | cut -c1-160)"
  else state="idle; no chain has run on $CH"; fi
  echo "CHAIN HOST: $CH via $via -- $state"
else
  echo "CHAIN HOST: INVALID '$CH' in ~/.config/devenv/chain-host -- WAITING: no chain can start until it says mac or pc"
fi
# Units placed on the peer, and new units waiting for room (unit-placement.sh).
for f in "$SCRATCH"/offload-${ONLY:-*}.txt; do [ -e "$f" ] && echo "OFFLOADED: $(tr '\n' ' ' < "$f")"; done
for f in "$SCRATCH"/offload-${ONLY:-*}.wait; do
  [ -e "$f" ] || continue
  u=${f##*/offload-}; echo "PLACEMENT WAIT: ${u%.wait} -- $(head -1 "$f")"
done
# main-watch.sh is the one thing that wakes main.
echo "  $(bash "$PP_SCRIPTS/main-watch.sh" --status)"
