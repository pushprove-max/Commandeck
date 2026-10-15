#!/usr/bin/env bash
# dashboard-view.test.sh -- runs the dashboard page's DOM tests (dashboard-view.test.mjs) in the shell test
# family. They need jsdom, which the plugin does not ship: COMMANDECK_TEST_NODE_MODULES names a node_modules
# folder that has it. Without one the file is skipped and says so, never counted as a pass in silence.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
if [ ! -d "${COMMANDECK_TEST_NODE_MODULES:-}/jsdom" ]; then
  echo "SKIPPED dashboard-view.test.mjs: no jsdom; set COMMANDECK_TEST_NODE_MODULES to a node_modules folder that has it"
  exit 0
fi
node --test dashboard-view.test.mjs
