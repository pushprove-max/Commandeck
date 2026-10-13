#!/usr/bin/env bash
# dashboard-view-ci.test.sh -- dashboard-view.test.sh skips the DOM tests when
# no jsdom is lent to it. What this pins: in CI that is a failure, not a skip,
# so the suite cannot go green with the dashboard's page untested.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

OUT=$(CI=true COMMANDECK_TEST_NODE_MODULES= bash "$HERE/dashboard-view.test.sh" 2>&1); RC=$?
check "in CI, no jsdom fails the file" 1 "$RC"
check "and says what is missing" 1 "$(grep -c 'no jsdom' <<<"$OUT")"
check "the workflow lends jsdom to the tests" 1 "$(grep -c 'COMMANDECK_TEST_NODE_MODULES=.*GITHUB_ENV' "$ROOT/.github/workflows/ci.yml")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
