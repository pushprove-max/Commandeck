#!/usr/bin/env bash
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
. "$ROOT/hooks/lib/hook-fire-log.sh"
fail=0
for command in \
  'curl -ubob:shortValue42 https://example.com' \
  'curl --proxy-user bob:shortValue42 https://example.com' \
  'SSHPASS=shortValue42 sshpass -e ssh host' \
  'redis-cli -a shortValue42 ping'; do
  _HOOK_FIRE_HEAD=$(jq -cn --arg c "$command" \
    '{tool_input:{command:$c}}')
  _hook_fire_log_summary
  if [[ $summary == *shortValue42* ]]; then
    printf 'credential retained: %s\n' "$summary"
    fail=1
  fi
done
exit "$fail"
