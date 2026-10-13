#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
FAIL=0
for COMMAND in \
  'git -C "." clean -fdx' \
  'git -c "core.pager=cat" clean -fdx'
do
  RC=0
  jq -nc --arg command "$COMMAND" \
    '{tool_input:{command:$command}}' |
    COMMANDECK_HOOK_FIRE_LOG=/dev/null \
      bash "$ROOT/hooks/git-safety.sh" >/dev/null 2>&1 ||
    RC=$?
  if [ "$RC" -ne 2 ]; then
    echo "FAIL: $COMMAND expected 2, got $RC"
    FAIL=$((FAIL + 1))
  fi
done
[ "$FAIL" -eq 0 ]
