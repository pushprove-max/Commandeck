#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
set -euo pipefail
export COMMANDECK_REVIEWER=0
HOOK="$(git rev-parse --show-toplevel)/hooks/bash-guardrails.sh"
CMD='if false; then sleep 1 & PIPESTATUS=$!; fi; true; kill "$PIPESTATUS"'
rc=0
jq -cn --arg cmd "$CMD" '{tool_input:{command:$cmd}}' |
  bash "$HOOK" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || {
  printf 'FAIL: expected refusal, got exit %s\n' "$rc"
  exit 1
}
