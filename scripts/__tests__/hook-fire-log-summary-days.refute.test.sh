#!/usr/bin/env bash
# With no log directory to discover at all, the summary still answers for the
# window it was asked for: the default discovery once dropped the day count.
set -u
OUT=$(env -u COMMANDECK_HOOK_FIRE_LOG HOME=/dev/null bash "$(dirname "$0")/../hook-fire-log-summary.sh" 7) \
  || { echo "FAIL: the summary exited $?"; exit 1; }
[ "$(jq -r .days <<<"$OUT")" = 7 ] || { echo "FAIL: days is not 7: $OUT"; exit 1; }
echo "1 passed, 0 failed"
