#!/usr/bin/env bash
# ci-watch.sh <sha> -- watch each GitHub Actions run of <sha> to its end, then print one line with each job's result
# (issue 259). It detaches itself (pp_detach), so that line comes to main as a status message. A failed run's
# failed jobs are rerun once (gh run rerun --failed): the run id goes in $PP_SCRATCH/ci-watch-reruns first, so no
# run is rerun twice, by this call or a later one. A run whose workflow name or file says deploy is only watched.
# It waits with gh run watch --exit-status, never a poll loop. Exit 0 every run green, 1 one is not or the listing is cut short, 3 no run listed.
# Self-test: bash scripts/__tests__/ci-watch.test.sh
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
SHA=${1:-}
[[ $# = 1 && $SHA =~ ^[0-9a-f]{7,40}$ ]] || { echo "usage: ci-watch.sh <sha>" >&2; exit 2; }
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
mkdir -p "$PP_SCRATCH" || exit 1
[ -n "${COMMANDECK_FOREGROUND:-}" ] || { pp_detach "$PP_SCRATCH/ci-watch-$SHA.log" "ci-watch.sh $SHA" bash "$0" "$@"; exit; }
REC=$PP_SCRATCH/ci-watch-reruns
# Every page: gh run list stops at 20 runs, and a run past them would go unwatched.
RUNS=$(timeout 60 gh api --paginate "repos/{owner}/{repo}/actions/runs?head_sha=$SHA&per_page=100" \
  --jq '"total\t\(.total_count)", (.workflow_runs[] | "\(.id)\t\(.name)")' </dev/null) \
  || { echo "ci-watch $SHA: listing the runs failed"; exit 1; }
# GitHub stops a head_sha listing at 1,000 runs but counts them all, and a run added or removed between pages shifts
# them (one id repeats, another goes unread): a run left out may be the failed one.
TOTALS=$(grep '^total' <<<"$RUNS" | cut -f2 | sort -u); RUNS=$(grep -v '^total' <<<"$RUNS")
[ "$(grep -c . <<<"$TOTALS")" -le 1 ] || { echo "ci-watch $SHA: NOT green -- the run count changed while the listing was read ($(echo $TOTALS)), so a run may have gone unread"; exit 1; }
N=$(cut -f1 <<<"$RUNS" | grep . | sort -u | wc -l | tr -d ' ')
[ "$N" -ge "${TOTALS:-0}" ] || { echo "ci-watch $SHA: NOT green -- the listing holds $N of $TOTALS runs, so the rest went unread"; exit 1; }
[ -n "$RUNS" ] || { echo "ci-watch $SHA: no CI run listed for this commit"; exit 3; }
RC=0 LINE=
while IFS=$'\t' read -r id name; do
  gh run watch "$id" --exit-status >/dev/null 2>&1 </dev/null; rc=$? again=
  if [ "$rc" != 0 ] && ! grep -qx "$id" "$REC" 2>/dev/null; then
    # A file that cannot be read counts as a deploy: a rerun is never guessed.
    file=$(gh api "repos/{owner}/{repo}/actions/runs/$id" --jq .path </dev/null 2>/dev/null) || file=deploy
    # The record is checked again and written under a lock: two watchers of one sha both pass the check above.
    if ! grep -qi deploy <<<"$name $file" \
      && { flock -w 30 9 && ! grep -qx "$id" "$REC" 2>/dev/null && echo "$id" >> "$REC"; } 9>>"$REC.lock"; then
      # shortcut: the watch right after the rerun trusts GitHub to have queued the new attempt; if a watch ever reads the old attempt's result, wait on `gh run view --json attempt` first.
      gh run rerun "$id" --failed >/dev/null 2>&1 </dev/null \
        && { again=" (rerun once)"; gh run watch "$id" --exit-status >/dev/null 2>&1 </dev/null; rc=$?; }
    fi
  fi
  [ "$rc" = 0 ] || RC=1
  LINE+="$name: $(gh run view "$id" --json jobs --jq '[.jobs[] | "\(.name) \(.conclusion)"] | join(", ")' </dev/null 2>/dev/null || echo "jobs not read")$again; "
done <<<"$RUNS"
echo "ci-watch $SHA: $([ "$RC" = 0 ] && echo green || echo NOT green) -- ${LINE%; }"
exit "$RC"
