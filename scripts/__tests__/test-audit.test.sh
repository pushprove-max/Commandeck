#!/usr/bin/env bash
# test-audit.test.sh -- runs the /test-audit workflow's coverage and packing tests
# (test-audit.test.mjs) in the shell test family.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
node --test test-audit.test.mjs
