#!/usr/bin/env bash
# merge-queue.sh <unit> ... -- run merge-unit-local.sh for each unit in order,
# one at a time, stopping at the first failure, merged (a step after its commit
# failed) or not. Exit 4: every unit merged, and one or more could not file an
# issue for a finding left open.
# Logs: <scratch>/merge-<unit>.log (paths.sh PP_SCRATCH)
# Self-test: bash scripts/__tests__/merge-unit-local.test.sh
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[ $# -gt 0 ] || { echo "usage: merge-queue.sh <unit> ..." >&2; exit 2; }
COMMANDECK_MAIN=$(git rev-parse --show-toplevel) . "$HERE/paths.sh" || exit 1
mkdir -p "$PP_SCRATCH" || exit 1
UNFILED=0

for unit in "$@"; do
  log=$PP_SCRATCH/merge-$unit.log
  "$HERE/merge-unit-local.sh" "$unit" > "$log" 2>&1; rc=$?
  if [ "$rc" != 0 ] && [ "$rc" != 4 ]; then
    # 3 is a unit that merged and then failed a later step: merging it again would merge it twice.
    if [ "$rc" = 3 ]; then echo "merge-queue: STOPPED at $unit (MERGED, but a step after the merge commit failed; finish it by hand, do not merge it again); log: $log" >&2
    else echo "merge-queue: STOPPED at $unit (not merged); log: $log" >&2; fi
    tail -n 3 "$log" >&2
    exit 1
  fi
  # 4 is a unit that merged and could not file an issue for a finding left open: the queue goes on.
  if [ "$rc" = 4 ]; then
    UNFILED=4
    echo "merge-queue: $unit merged; $(grep -c '^NOT FILED: ' "$log") finding(s) NOT FILED as issues, the command that files them is in $log" >&2
    continue
  fi
  echo "merge-queue: $unit merged; $(tail -n 1 "$log" | cut -c1-160)"
done
echo "merge-queue: all $# unit(s) merged"
exit "$UNFILED"
