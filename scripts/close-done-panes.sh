#!/usr/bin/env bash
# close-done-panes.sh [--close] -- list (default) or close agent panes whose
# agent Orca reports `done` and that have been silent for QUIET_SECONDS, and
# unclaimed panes in any Orca state silent for ORPHAN_SECONDS (Orca's state
# lies both ways). main-watch.sh runs it with --close every tick.
# Prints handle<TAB>worktree<TAB>agent<TAB>idle-minutes per pane.
#
# Why: main may not call `terminal list`, and board.sh's seats cover seat records only, so finished panes on
# a live unit had no handle main could reach. On 2026-09-23 four of them sat
# 1.5 to 9.5 hours in one worktree; nothing closed them across restarts.
#
# For the done rule, silence is the agent's own last report (`worktree ps`
# updatedAt), never the pane's lastOutputAt: an idle Claude TUI redraws, so its
# output is always recent and a finished fixer never read quiet (2026-09-28).
# For the orphan rule it is the later of the two: updatedAt moves only on a
# state change, so one long turn looks stale while its TUI still draws, and a
# pane still drawing is never an orphan. A pane with no agent in `worktree ps`
# uses lastOutputAt for both.
# ponytail: an idle Claude pane redraws, so the orphan rule never closes one
# Orca calls `working` while it still draws; read its session log's mtime if
# such panes pile up.
#
# NEVER closed: the calling pane; any pane in the main checkout; a reviewer
# named in a round's .kept file, or in a round's .txt while that round is still
# open (the loop reads its verdict from the pane); the pane each live loop/drive
# unit last named (Orca's `done` lies); a unit's implementer, Builder or
# fixer pane named in its seat record; every pane in a worktree the owner owns
# (not CLI-created, or a named keeper); every pane in another repo's worktree
# (outside $PP_WORKSPACES: Orca lists every repo's, and that repo's records are not here). A seat pane whose record
# has no verdict= line, until seat.sh collect writes one.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
CLOSE=0; [ "${1:-}" = --close ] && CLOSE=1
SELF=${ORCA_TERMINAL_HANDLE:-}
QUIET_SECONDS=${COMMANDECK_DONE_PANE_QUIET_SECONDS:-600}
ORPHAN_SECONDS=${COMMANDECK_ORPHAN_PANE_QUIET_SECONDS:-1800}
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
. "$(dirname "${BASH_SOURCE[0]}")/host-services.sh"
SCRATCH=$PP_SCRATCH
MAIN=$PP_MAIN
# board.sh passes what it already fetched, so a board call makes each RPC once.
PS_JSON=${COMMANDECK_PS_JSON:-$(timeout 8 orca-ide worktree ps --json)}
TERMS_JSON=${COMMANDECK_TERMINALS_JSON:-$(orca-ide terminal list --json)}
WT_JSON=$(orca-ide worktree list --json)
# An error answer is not an empty list: with no agents every pane looks
# agent-less, and the orphan rule would close panes that may be working.
answered() { jq -e "$2" <<<"$1" >/dev/null 2>&1 || { echo "close-done-panes: orca-ide $3 did not answer with a list; closing nothing" >&2; exit 1; }; }
answered "$PS_JSON" '.result.worktrees | type == "array"' 'worktree ps'
answered "$TERMS_JSON" '.result | if type == "array" then true else (.terminals | type == "array") end' 'terminal list'
answered "$WT_JSON" '.result.worktrees | type == "array"' 'worktree list'
# Same driver finder and log path as board.sh's loops section; keep them in parity.
DRIVERS=${COMMANDECK_DRIVERS:-$(hs_list 'loop-*' 'drive-*' --no-legend --plain | awk '{print $1}')} \
  || { echo "close-done-panes: cannot read the service state, so a live driver's panes cannot be told apart; closing nothing" >&2; exit 1; }
PROTECT=$(
  cat "$SCRATCH"/review-handles-*-r*.kept 2>/dev/null | grep -o 'term_[0-9a-f-]*' || true
  # Only a unit's latest round's .txt protects; a later round means it closed.
  # The reports file is no signal: review-round.sh writes a routing line into it
  # before launch, and a refused round relaunches under the same number.
  for f in "$SCRATCH"/review-handles-*-r*.txt; do
    [ -e "$f" ] || continue
    b=${f##*/review-handles-}; b=${b%.txt}; u=${b%-r*}; r=${b##*-r}
    [[ $r =~ ^[0-9]+$ ]] && [ -e "$SCRATCH/review-handles-$u-r$((r+1)).txt" ] && continue
    grep -o 'term_[0-9a-f-]*' "$f" || true
  done
  # The builder's pane stays open until the merge, with or without a live driver; merge-unit-local.sh closes it.
  cat "$SCRATCH"/seat-*-implementer.txt "$SCRATCH"/seat-*-fixer.txt "$SCRATCH"/seat-*-builder.txt 2>/dev/null | sed -n 's/^handle=//p' || true
  for svc in $DRIVERS; do
    n=${svc%.service}; u=${n#*-}; u=${u%-*}
    grep -oE '(implementer|pane)=term_[0-9a-f-]+' "$SCRATCH/scratchpad/$u-${n%%-*}-${n##*-}.log" 2>/dev/null | tail -1 | cut -d= -f2 || true
  done
)
# A seat pane whose record has no verdict= line is left to seat.sh collect: neither the done nor the orphan rule
# closes it (a plan seat printed PLAN-DONE and was swept before collect).
# A record with a verdict= line was collected, so it claims nothing.
# One awk over every record: two processes per record took 5 s of each board.
CLAIMED=$(awk 'FNR == 1 { if (!v) printf "%s", h; h = ""; v = 0 }
  /^verdict=/ { v = 1 } /^handle=/ { h = h substr($0, 8) "\n" }
  END { if (!v) printf "%s", h }' "$SCRATCH"/seat-*.txt 2>/dev/null || true)
NOW=$(( $(date +%s) * 1000 ))
rows=$(jq -rn --argjson ps "$PS_JSON" --argjson ts "$TERMS_JSON" --argjson wl "$WT_JSON" \
  --arg self "$SELF" --arg main "$MAIN" --arg ws "$PP_WORKSPACES" --rawfile prot <(printf '%s' "$PROTECT") --rawfile claim <(printf '%s' "$CLAIMED") --rawfile keep <(pp_keep_worktrees) \
  --argjson now "$NOW" --argjson cutoff "$(( NOW - QUIET_SECONDS * 1000 ))" \
  --argjson orphan "$(( NOW - ORPHAN_SECONDS * 1000 ))" "$PP_PNORM"'
  ($prot | split("\n")) as $prot | ($ws | pnorm) as $ws | ($main | pnorm) as $main
  | ($claim | split("\n")) as $claim | ($keep | split("\n") | map(select(. != ""))) as $keep
  | ($ts.result | if type == "array" then . else .terminals end) as $ts
  | [ $wl.result.worktrees[]
      | select(.cliProvenance.kind == "created-by-cli" and .isMainWorktree != true
               and (.path | pnorm | startswith($ws + "/"))
               and (.displayName | IN($keep[]) | not)
               and (.path | split("/") | last | IN($keep[]) | not))
      | .path | pnorm ] as $owned
  | [ $ps.result.worktrees[]? | .agents[]? ] as $agents
  | $ts[]
  | select(.handle != $self and (.worktreePath | pnorm) != $main and (.worktreePath | pnorm | IN($owned[]))
           and (.handle | IN($prot[]) | not))
  | "\(.tabId):\(.leafId)" as $k
  | [ $agents[] | select(.paneKey == $k) ] as $a
  | ([ $ts[] | select("\(.tabId):\(.leafId)" == $k) ] | length) as $n
  | (if ($a | length) > 0 then ($a | map(.updatedAt) | max) else .lastOutputAt end) as $at
  | ([$at, .lastOutputAt] | map(numbers) | max) as $oat
  | "\(.handle)\t\(.worktreePath | split("/") | last)\t\($a[0].agentType // .agentIdentity // "shell")" as $row
  | if $n != 1 then "skip\t\($k)\t\($n) panes carry this key, need exactly 1"
    elif ($at | type) != "number" then empty
    elif ($a | length) > 0 and all($a[]; .state == "done") and $at < $cutoff and (.handle | IN($claim[]) | not)
    then "\($row)\t\(($now - $at) / 60000 | floor)"
    elif (.handle | IN($claim[]) | not) and all($a[]; .state != "working") and $oat < $orphan
    then "\($row)\t\(($now - $oat) / 60000 | floor)"
    else empty end')
closed=""
while IFS=$'\t' read -r h wt agent idle; do
  [ -n "$h" ] || continue
  if [ "$h" = skip ]; then echo "skip $wt: $agent" >&2; continue; fi
  if [ "$CLOSE" = 1 ]; then
    # A refused close can exit 0; pp_pane_close counts only `.ok` and logs the close with its cause.
    if pp_pane_close "$h" "sweep: ${agent:-shell} idle ${idle}m"; then
      printf 'closed %s\t%s\t%s\t%s\n' "$h" "$wt" "$agent" "$idle"; closed+=" $h"
    else
      echo "close of $h failed: $PP_CLOSE_RES" >&2
    fi
  else
    printf '%s\t%s\t%s\t%s\n' "$h" "$wt" "$agent" "$idle"
  fi
done <<<"$rows"
# Closing tasks is main's call; say which dispatched task lost its pane. Orca
# has no assignee field on a task or dispatch, so the pairing comes from the
# records that name both: seat records (same reader as agent-awareness.sh's
# LIVE_TASKS), and the `implementer=<h> task=<t>` line dispatch-fix.sh writes to
# fix-handles-*.txt and dispatch-unit.sh prints into the loop/drive log.
RUN=$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE" || true)
if [ -n "$closed" ] && [ -n "$RUN" ]; then
  SEATS=$(
    awk -F= '/^handle=/{h=$2} /^task=/ && h {print $2, h; h=""}' "$SCRATCH"/seat-*.txt 2>/dev/null || true
    grep -ohE 'implementer=term_[0-9a-f-]+ task=task_[0-9a-z]+' "$SCRATCH"/fix-handles-*.txt \
        "$SCRATCH"/scratchpad/*-loop-*.log "$SCRATCH"/scratchpad/*-drive-*.log 2>/dev/null \
      | sed 's/^implementer=\([^ ]*\) task=\(.*\)$/\2 \1/' || true
  )
  for t in $(orca-ide orchestration task-list --run "$RUN" --json | jq -r '.result.tasks[] | select(.status == "dispatched") | .id'); do
    for h in $(awk -v t="$t" '$1 == t {print $2}' <<<"$SEATS"); do
      case "$closed " in *" $h "*) echo "task $t is still dispatched to closed pane $h; left open" ;; esac
    done
  done
fi
