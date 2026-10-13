#!/usr/bin/env bash
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
. "$ROOT/hooks/lib/hook-fire-log.sh"
fail=0
for command in \
  'printf %s shortValue42 | gh auth login --with-token' \
  'echo shortValue42 | gh auth login --with-token' \
  'printf %s shortValue42 | redis-cli -x AUTH'; do
  _HOOK_FIRE_HEAD=$(jq -cn --arg c "$command" \
    '{tool_input:{command:$c}}')
  _hook_fire_log_summary
  if [[ $summary == *shortValue42* ]]; then
    printf 'credential retained: %s\n' "$summary"
    fail=1
  fi
done
exit "$fail"
