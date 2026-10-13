#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export CLAUDE_PROJECT_DIR="$T"
export COMMANDECK_HOOK_FIRE_LOG="$T/hook-fire.jsonl"
# The heap-cap block is strict tier (hooks/lib/project.sh); the case needs a blocked call.
export COMMANDECK_HOOK_TIER=strict
INPUT='{"hook_event_name":"PreToolUse","session_id":"00000000-0000-4000-8000-000000000002","tool_name":"Bash","tool_use_id":"blocked","tool_input":{"command":"node --test"}}'
printf '%s' "$INPUT" | bash "$ROOT/hooks/builder-event-log.sh"
rc=0
printf '%s' "$INPUT" | bash "$ROOT/hooks/bash-guardrails.sh" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ]
NOW=$(jq -r 'select(.event == "tool-start") | (.ts | fromdateiso8601) + 1900' "$T/.claude/builder-events.jsonl")
jq -s --argjson now "$NOW" -f "$ROOT/scripts/dashboard_builders.jq" \
  "$T/.claude/builder-events.jsonl" |
  jq -e '[.signals[] | select(.kind == "stuck")] == []' >/dev/null
