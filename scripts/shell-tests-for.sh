#!/usr/bin/env bash
# The shell tests that cover a change (host issues 2997, 2951). Run from a checkout root with the changed paths on stdin
# (added, modified AND deleted). Prints, sorted and unique, every EXISTING {hooks,scripts}/__tests__/*.test.sh that
# the input names, or that names (by basename) an input file under hooks/ or scripts/, repeated over the
# files found until nothing new turns up (dashboard.sh -> dashboard.test.sh -> dashboard-live.test.sh, which only execs
# dashboard.test.sh). The existence filter drops a deleted test file; its basename still seeds the next round.
# Used by run-shell-tests.sh --changed <base> --callers: one selector, no test map.
# shortcut: a basename match over-selects (paths.sh names 40 tests); accepted, upgrade to a real map if it hurts.
# WARNING: with no seed basenames select nothing extra; an empty `grep -F -f` pattern list matches every file.
# --hops <n> stops after n rounds (#493, a merge ran hundreds of files): the pass's rebase check passes 2, which keeps
# helper -> test -> test. No flag keeps the full walk, which --changed --callers relies on.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -7; exit 0 ;; esac
set -euo pipefail
hops=
if [ "${1:-}" = --hops ]; then
  [[ ${2:-} =~ ^[1-9][0-9]*$ ]] && [ $# = 2 ] || { echo "usage: shell-tests-for.sh [--hops <n, 1 or more>]" >&2; exit 2; }
  hops=$2
elif [ $# != 0 ]; then
  echo "usage: shell-tests-for.sh [--hops <n, 1 or more>]" >&2; exit 2
fi
input=$(cat)
found=$({ grep -E '^(hooks|scripts)/__tests__/[^/]+\.test\.sh$' <<<"$input" || true; } | while IFS= read -r f; do
  if [ -f "$f" ]; then echo "$f"; fi
done | LC_ALL=C sort -u)
round=0
while [ -z "$hops" ] || [ "$round" -lt "$hops" ]; do
  round=$((round + 1))
  seeds=$({ grep -E '^(hooks|scripts)/' <<<"$input" || true; printf '%s\n' "$found"; } | sed 's#.*/##' | grep . | LC_ALL=C sort -u || true)
  [ -n "$seeds" ] || break
  more=$(grep -lF -f <(printf '%s\n' "$seeds") hooks/__tests__/*.test.sh scripts/__tests__/*.test.sh 2>/dev/null || true)
  next=$(printf '%s\n%s\n' "$found" "$more" | grep . | LC_ALL=C sort -u || true)
  [ "$next" != "$found" ] || break
  found=$next
done
[ -z "$found" ] || printf '%s\n' "$found"
