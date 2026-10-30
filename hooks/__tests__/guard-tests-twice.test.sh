#!/usr/bin/env bash
# Self-test for #484: builder-search-guard.test.sh and guard-try.test.sh keep streak files under /tmp. With fixed
# session names, two runs at once (two worktrees, or a push gate beside a hand run) cleared or fed each other's
# streaks and a green file went red. Each run now owns its names.
set -uo pipefail
D=$(cd "$(dirname "$0")" && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
twice() { # <test file>: runs it twice at once, three rounds; prints the failed-count tails of every run
  local f=$1 r i out=
  for r in 1 2 3; do
    for i in a b; do timeout 120 bash "$D/$f" >"$TMP/$f.$r$i" 2>&1 & done
    wait
    for i in a b; do out+="$(tail -1 "$TMP/$f.$r$i" | sed 's/.*, //') "; done
  done
  echo "${out% }"
}
GREEN="0 failed 0 failed 0 failed 0 failed 0 failed 0 failed"
# A fixed session name in either file shows here as a failed count in some round.
check "guard_tests_run_twice_at_once: builder-search-guard.test.sh, twice at once, three rounds" "$GREEN" "$(twice builder-search-guard.test.sh)"
check "guard_tests_run_twice_at_once: guard-try.test.sh, twice at once, three rounds" "$GREEN" "$(twice guard-try.test.sh)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
