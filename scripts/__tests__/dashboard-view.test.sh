#!/usr/bin/env bash
# Wires the dashboard's node and python tests into the shell test family, so
# they run wherever run-shell-tests.sh runs. The DOM tests need jsdom, which
# the plugin does not ship: COMMANDECK_TEST_NODE_MODULES names a node_modules
# folder that has it. Without one those files are skipped and named, never
# counted as passed; in CI (CI is set) that is a failure, so the suite cannot
# go green with the page untested.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
DOM=(dashboard-view.test.mjs dashboard-collector-stale.refute.test.mjs dashboard-cos-capped-empty.refute.test.mjs)
PLAIN=(builder-verdict-round.refute.test.mjs dashboard-guard-blocks-read-error.test.mjs dashboard-limit-cost.refute.test.mjs)
rc=0
[ -d "${COMMANDECK_TEST_NODE_MODULES:-}/jsdom" ] || [ -z "${CI:-}" ] \
  || { echo "FAILED: no jsdom in CI, so ${#DOM[@]} DOM test files (${DOM[*]}) would be skipped; the workflow sets COMMANDECK_TEST_NODE_MODULES"; exit 1; }
node --max-old-space-size=4096 --test "${PLAIN[@]}" || rc=1
python3 dashboard-missing-prompt.refute.test.py || rc=1
if [ -d "${COMMANDECK_TEST_NODE_MODULES:-}/jsdom" ]; then node --max-old-space-size=4096 --test "${DOM[@]}" || rc=1
else echo "SKIPPED ${#DOM[@]} DOM test files (${DOM[*]}): no jsdom; set COMMANDECK_TEST_NODE_MODULES to a node_modules folder that has it"; fi
exit $rc
