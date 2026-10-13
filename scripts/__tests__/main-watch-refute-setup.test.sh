#!/usr/bin/env bash
# A refute file of main-watch loads the suite's set-up and helpers, and none of
# its cases. Five of them ran every case first, minutes each, and timed out on
# a busy machine with nothing broken.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
D=scripts/__tests__

# refute_files_load_setup_only: every refute file that loads the suite asks for
# the set-up half on that same line.
loads=$(grep -l 'main-watch\.test\.sh' "$D"/main-watch-*.refute.test.sh)
[ "$(wc -l <<<"$loads")" -eq 5 ] || { echo "FAIL: refute_files_load_setup_only: expected 5 refute files that load the suite, found: $loads" >&2; exit 1; }
bad=$(grep -H 'source .*main-watch\.test\.sh' $loads | grep -v ':MAIN_WATCH_TEST_HALF=setup source ' || true)
[ -z "$bad" ] || { echo "FAIL: refute_files_load_setup_only: these load every case of the suite: $bad" >&2; exit 1; }

# setup_half_runs_no_case: the set-up half leaves no send, no seat and no task,
# has ticked once (the watcher posts only what finished after its first tick),
# and defines every helper a refute file calls.
MAIN_WATCH_TEST_HALF=setup source "$D/main-watch.test.sh"
[ ! -s "$T/sends" ] || fail "setup_half_runs_no_case: the set-up half sent something"
[ -z "$(ls "$S" | grep '^seat-' || true)" ] || fail "setup_half_runs_no_case: the set-up half left a seat record, so a case ran"
[ ! -s "$F/tasks" ] || fail "setup_half_runs_no_case: the set-up half left a task, so a case ran"
[ -d "$S/main-watch" ] || fail "setup_half_runs_no_case: the set-up half did not tick once"
for fn in tick seat state posts fail transcript offers hu has bseat bstart nudges; do
  declare -F "$fn" > /dev/null || fail "setup_half_runs_no_case: helper $fn is not defined by the set-up half"
done
echo "PASS: a main-watch refute file loads the set-up half only, and that half runs no case"
