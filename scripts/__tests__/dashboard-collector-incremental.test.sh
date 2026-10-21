#!/usr/bin/env bash
# dashboard-collector-incremental.test.sh -- runs the collector's read-only-what-changed tests
# (dashboard-collector-incremental.test.mjs, issue 299) in the shell test family.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
node --test dashboard-collector-incremental.test.mjs
