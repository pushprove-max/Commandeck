#!/usr/bin/env bash
# shell-tests-for.sh (host issue 2997): the shell tests a change reaches by name, so a change to a helper cannot pass
# the merge check while a test that runs it, but is named after something else, goes unrun.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
SEL=$REAL/scripts/shell-tests-for.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP" && mkdir -p scripts/__tests__ hooks/__tests__
echo 'echo dash' > scripts/dashboard.sh; echo 'echo helper' > scripts/helper.sh
echo '# unrelated: runs scripts/helper.sh' > scripts/__tests__/other.test.sh
echo '# runs scripts/dashboard.sh' > scripts/__tests__/dashboard.test.sh
echo 'exec bash dashboard.test.sh' > scripts/__tests__/dashboard-live.test.sh
echo '# runs a hook, mentions gone.test.sh' > hooks/__tests__/watch.test.sh
sel() { printf '%s\n' "$@" | bash "$SEL" | paste -sd" " -; }

check "a change to a script named only by an unrelated test selects that test" "scripts/__tests__/other.test.sh" "$(sel scripts/helper.sh)"
check "a test that only runs another test follows, until nothing new turns up" \
  "scripts/__tests__/dashboard-live.test.sh scripts/__tests__/dashboard.test.sh" "$(sel scripts/dashboard.sh)"
check "a deleted test file selects nothing itself but its name still seeds the tests that name it" "hooks/__tests__/watch.test.sh" \
  "$(sel scripts/__tests__/gone.test.sh)"
check "a path outside hooks/ and scripts/ selects nothing (an empty seed list must not match every test)" "" "$(sel README.md)"
check "no input selects nothing" "" "$(bash "$SEL" < /dev/null | paste -sd" " -)"

# #493: the pass's rebase check walks two rounds, not to the end of the chain. Chain: helper.sh -> a.test.sh -> b.test.sh -> c.test.sh.
echo '# runs scripts/helper.sh' > scripts/__tests__/a.test.sh; echo '# runs a.test.sh' > scripts/__tests__/b.test.sh
echo '# runs b.test.sh' > scripts/__tests__/c.test.sh
hops() { printf 'scripts/helper.sh\n' | bash "$SEL" "$@" 2>/dev/null | grep -E '/[abc]\.test\.sh$' | sed 's#.*/##' | paste -sd" " -; }
# Catches: --hops ignored (full walk reaches c), or counted from zero or three (a is missed, or c is reached).
check "two_hops_stop_the_chain: --hops 2 reaches a and b but not c, no flag walks the whole chain" \
  "a.test.sh b.test.sh | a.test.sh b.test.sh c.test.sh" "$(hops --hops 2) | $(hops)"
# Catches: a bad hop count walking anyway instead of exiting 2.
check "two_hops_stop_the_chain: a zero, a word and a missing value exit 2" "2 2 2" \
  "$(echo | bash "$SEL" --hops 0 >/dev/null 2>&1; echo $?) $(echo | bash "$SEL" --hops x >/dev/null 2>&1; echo $?) $(echo | bash "$SEL" --hops >/dev/null 2>&1; echo $?)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
