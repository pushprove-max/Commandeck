#!/usr/bin/env bash
# Wires the /test-audit workflow's argument and packing tests into the shell
# test family, so they run wherever run-shell-tests.sh runs.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
node --max-old-space-size=4096 --test test-audit-workflow.test.mjs
