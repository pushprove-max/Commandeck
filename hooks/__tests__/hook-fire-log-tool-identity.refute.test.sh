#!/usr/bin/env bash
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export COMMANDECK_HOOK_FIRE_LOG="$T/fires.jsonl"
. "$ROOT/hooks/lib/hook-fire-log.sh"
row() {
  local payload
  payload=$(jq -cn --arg t "$1" --arg u "$2" \
    '{session_id:"11111111-2222-4333-8444-555555555555",
      hook_event_name:"PreToolUse",tool_name:$t,
      tool_input:{name_path:"X",relative_path:"src/x.ts"},
      tool_use_id:$u}')
  hook_fire_log_arm "$payload"
  trap - EXIT
  _hook_fire_log_write "$3"
}
row mcp__serena__find_symbol toolu_a block
row mcp__serena__find_referencing_symbols toolu_b allow
bash "$ROOT/scripts/hook-fire-log-summary.sh" 1 |
  jq -e 'any(.hooks[];
    .blocks == 1 and .retried_identical == 0 and .worked_around == 1)'
