#!/usr/bin/env bash
# unit-close.sh <unit> merged | <unit> drop '<reason>' | --sweep [--apply]
# Closes the Orca task(s) a unit's Builder seat recorded (#396), which otherwise stay open after the unit leaves.
#   merged  merge-unit-local.sh's cleanup_step calls it before any pane closes: each task of the record closes completed.
#           Exit 0 closed, 1 not closed (the printed line says why; a refusal never changes the merge's own exit code).
#   drop    removes an UNMERGED unit: tasks close failed with the reason (a refused close stops before anything is
#           removed), then its panes close, its Codex helpers stop, the panes are listed again, and only an empty,
#           readable second listing lets `worktree remove --force` run. Otherwise: KEPT <wt>: <why>, exit 1.
#   --sweep every Builder record whose worktree is gone, with open tasks in the bound run: merged -> completed, else
#           failed. Live worktrees and <repo>@<unit> records (another repository's) are skipped; an open task in no
#           record is listed `no record <task> <status>`, never closed. Dry run unless --apply.
# Task ids come from $PP_SCRATCH/seat-<unit>-builder.txt (task= and answer_task=) not yet marked settled=<task>, never
# from the task list's spec text. Every close goes through pp_task_close, which refuses while the pane works or has an
# open question. Exit codes: 0 done, 1 refused or kept, 2 usage.
# Self-test: bash scripts/__tests__/unit-close.test.sh
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
usage() { echo "usage: unit-close.sh <unit> merged | <unit> drop '<reason>' | --sweep [--apply]" >&2; exit 2; }
OPEN='pending|ready|dispatched|blocked'
# merged_sha <unit> -- the unit's mergeSha from the ledger when it is an ancestor of local main.
merged_sha() {
  local sha
  sha=$(jq -rs --arg u "$1" '[.[] | select(.unit == $u and .mergeSha)] | last | .mergeSha // empty' \
    "$PP_MAIN/.claude/metrics/unit-ledger.jsonl" 2>/dev/null || true)
  [[ $sha =~ ^[0-9a-f]{40}$ ]] && git -C "$PP_MAIN" merge-base --is-ancestor "$sha" main 2>/dev/null && echo "$sha"
}
# close <task> <status> [result-json] -- pp_task_close; on success the record gains settled=<task> (seat.sh's marker).
close() {
  local rec=$PP_SCRATCH/seat-$UNIT-builder.txt
  WHY=$(pp_task_close "$@" 2>&1) || { WHY=$(tr '\n' ' ' <<<"${WHY:-no answer}" | sed 's/ *$//'); return 1; }
  [ -s "$rec" ] && [ -n "$(tail -c1 "$rec" 2>/dev/null)" ] && echo >> "$rec"
  echo "settled=$1" >> "$rec"
}
# tasks -- the record's task= and answer_task= ids not yet settled.
tasks() {
  local rec=$PP_SCRATCH/seat-$UNIT-builder.txt t
  for t in $(sed -n 's/^\(answer_\)\{0,1\}task=//p' "$rec"); do grep -qxF "settled=$t" "$rec" || echo "$t"; done
}

if [ "${1:-}" = --sweep ]; then
  APPLY=0
  case "${2:-}" in --apply) APPLY=1 ;; "") ;; *) usage ;; esac
  RUN=${COMMANDECK_RUN:-$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE" || true)}
  LIST=$(orca-ide orchestration task-list --run "${RUN:-none}" --json 2>/dev/null) \
    && jq -e '.result.tasks | type == "array"' <<<"$LIST" >/dev/null 2>&1 \
    || { echo "could not read the task list of run ${RUN:-none} ($PP_RUN_FILE)" >&2; exit 1; }
  status_of() { jq -r --arg t "$1" 'first(.result.tasks[] | select(.id == $t) | .status) // empty' <<<"$LIST"; }
  rc=0 n=0 refused=0 orphans=0
  for rec in "$PP_SCRATCH"/seat-*-builder.txt; do
    [ -f "$rec" ] || continue
    UNIT=${rec##*/seat-}; UNIT=${UNIT%-builder.txt}
    case $UNIT in *@*) echo "skip $UNIT: another repository's record"; continue ;; esac
    if [ -d "$PP_WORKSPACES/$UNIT" ]; then echo "skip $UNIT: worktree live"; continue; fi
    if [ -n "$(merged_sha "$UNIT")" ]; then to=completed why='unit merged'; else to=failed why='worktree gone, unit not merged'; fi
    res=$(jq -nc --arg r "$why (unit-close.sh --sweep)" '{reason: $r}')
    for t in $(tasks); do
      [[ $(status_of "$t") =~ ^($OPEN)$ ]] || continue
      n=$((n + 1))
      if [ "$APPLY" = 0 ]; then echo "would close $t $to $UNIT"
      elif close "$t" "$to" "$res"; then echo "closed $t $to $UNIT"
      else echo "NOT closed $t $to $UNIT: $WHY"; refused=$((refused + 1)); rc=1; fi
    done
  done
  NAMED=$(sed -n 's/^\(answer_\)\{0,1\}task=//p' "$PP_SCRATCH"/seat-*.txt 2>/dev/null || true)
  while read -r t st; do
    [ -n "$t" ] && ! grep -qxF -- "$t" <<<"$NAMED" || continue
    echo "no record $t $st"; orphans=$((orphans + 1))
  done < <(jq -r --arg open "^($OPEN)$" '.result.tasks[] | select(.status | test($open)) | "\(.id) \(.status)"' <<<"$LIST")
  if [ "$APPLY" = 0 ]; then echo "sweep: $n would close, $orphans with no record"
  else echo "sweep: $((n - refused)) closed, $refused refused, $orphans with no record"; fi
  exit $rc
fi

UNIT=${1:-}; MODE=${2:-}
[[ $UNIT =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage
REC=$PP_SCRATCH/seat-$UNIT-builder.txt
case $MODE in
  merged)
    [ $# = 2 ] || usage
    [ -f "$REC" ] || { echo "STEP 5 task NOT closed: no Builder seat record $REC; unit-close.sh --sweep --apply closes it later"; exit 1; }
    rc=0
    for t in $(tasks); do
      if close "$t" completed; then echo "STEP 5 task: closed $t completed"
      else echo "STEP 5 task NOT closed: $WHY; unit-close.sh --sweep --apply closes it later"; rc=1; fi
    done
    exit $rc ;;
  drop)
    REASON=${3:-}; [ $# = 3 ] && [ -n "$REASON" ] || usage
    SHA=$(merged_sha "$UNIT" || true)
    [ -z "$SHA" ] || { echo "REFUSED: $UNIT is merged (${SHA:0:12} on main); drop is for an unmerged unit" >&2; exit 1; }
    WT=$PP_WORKSPACES/$UNIT
    if [ -f "$REC" ]; then
      for t in $(tasks); do
        close "$t" failed "$(jq -nc --arg r "$REASON" '{reason: $r}')" \
          || { echo "REFUSED: task $t not closed, nothing removed: $WHY" >&2; exit 1; }
        echo "closed $t failed"
      done
    else echo "no Builder seat record $REC; no task closed"; fi
    [ -d "$WT" ] || { echo "worktree $WT is already gone"; exit 0; }
    STUCK=
    if PANES=$(pp_worktree_panes "$WT"); then
      while IFS= read -r h; do
        [ -n "$h" ] || continue
        pp_pane_close "$h" "unit dropped: $REASON" || { echo "pane $h did not close" >&2; STUCK="a pane did not close"; }
      done <<<"$PANES"
    else STUCK="the pane list could not be read"; fi
    bash "$HERE/codex-helpers.sh" stop "$WT" || true
    if [ -z "$STUCK" ]; then
      if ! LEFT=$(pp_worktree_panes "$WT"); then STUCK="the pane list could not be read after the close"
      elif [ -n "$LEFT" ]; then STUCK="still listed after the close: $(tr '\n' ' ' <<<"$LEFT" | sed 's/ $//')"; fi
    fi
    [ -z "$STUCK" ] || { echo "KEPT $WT: $STUCK" >&2; exit 1; }
    orca-ide worktree remove --worktree "path:$WT" --force >/dev/null \
      || { echo "KEPT $WT: could not remove it; its tasks are already failed, rerun to remove it" >&2; exit 1; }
    echo "dropped $UNIT: $REASON" ;;
  *) usage ;;
esac
