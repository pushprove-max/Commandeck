#!/usr/bin/env bash
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
. "$ROOT/hooks/lib/hook-fire-log.sh"
fail=0
for command in \
  'TOKENS=(shortValue42); curl -H "Authorization: Bearer ${TOKENS[0]}" https://example.com' \
  $'gh auth login --with-token <<\'a b\'\na\nshortValue42\na b' \
  $'gh auth login --with-token <<E\'O\'F\nE\nshortValue42\nEOF'; do
  _HOOK_FIRE_HEAD=$(jq -cn --arg c "$command" \
    '{tool_input:{command:$c}}')
  _hook_fire_log_summary
  if [[ $summary == *shortValue42* ]]; then
    printf 'credential retained: %s\n' "$summary"
    fail=1
  fi
done
exit "$fail"
