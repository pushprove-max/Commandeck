#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
set -u
ROOT=$(git rev-parse --show-toplevel)
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
mkdir -p "$BOX/w/.claude/briefs"
printf '{"context":1,"compactions":2}\n' > "$BOX/budget.json"
printf '{"type":"assistant","payload":"this transcript exceeds one byte"}\n' > "$BOX/log.jsonl"
printf '{"transcript_path":"%s/log.jsonl","tool_name":"Edit"}\n' "$BOX" > "$BOX/input"
CLAUDE_PROJECT_DIR="$BOX/w" PANE_BUDGET_CONFIG="$BOX/budget.json" "$ROOT/hooks/pane-budget-gate.sh" < "$BOX/input" >/dev/null 2>&1
test "$?" -eq 2 || exit 1
printf '{"context":999999,"compactions":0}\n' > "$BOX/budget.json"
printf '%s\n' '{"isCompactSummary":true}' > "$BOX/log.jsonl"
CLAUDE_PROJECT_DIR="$BOX/w" PANE_BUDGET_CONFIG="$BOX/budget.json" "$ROOT/hooks/pane-budget-gate.sh" < "$BOX/input" >/dev/null 2>&1
test "$?" -eq 2 || exit 1
echo "pane-budget-context: 1 passed, 0 failed"
