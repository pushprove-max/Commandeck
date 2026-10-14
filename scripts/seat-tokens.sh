#!/usr/bin/env bash
# seat-tokens.sh [seat-events.jsonl] -- one line per unit, then one per role:
# seats counted and their input, cached-input and output token totals. Rows
# without tokens (written before tokens were recorded, or no log found) are skipped.
# seat-tokens.sh --rollout <codex-rollout.jsonl>... -- one line per Codex session:
# turns (token_usage_record events, token_count in an older log), tool calls, the tools.* calls inside those exec
# scripts, and both per turn. Batched looks show as toolsPerTurn above 1.
# overBudget=true marks a session whose turns (model calls) exceed the
# configured review-limits.calls: Codex has no hard stop, so this is the check.
set -euo pipefail
# On a Mac: Homebrew's tools ahead of the system's, and out of its Bash 3.2 (requirements.sh).
. "$(dirname "$0")/requirements.sh"
if [ "${1:-}" = "--rollout" ]; then
  shift
  ROUTING=${COMMANDECK_ROUTING:-$(dirname "${BASH_SOURCE[0]}")/../config/routing.json}
  BUDGET=$(jq -er '.["review-limits"].calls' "$ROUTING") || { echo "routing config $ROUTING has no review-limits.calls" >&2; exit 2; }
  for f in "$@"; do
    jq -rs --arg f "$f" --argjson budget "$BUDGET" '[.[] | .payload | objects] as $p
      | ([([.[] | select(.type? == "token_usage_record")] | length), ($p | map(select(.type == "token_count")) | length)] | max) as $turns
      | ($p | map(select(.type == "custom_tool_call" or .type == "function_call"))) as $calls
      | ($calls | map((.input // .arguments // "") | [scan("tools\\.[A-Za-z0-9_]+\\(")] | length) | add // 0) as $tools
      | def per($n): if $turns == 0 then 0 else ($n / $turns * 100 | round) / 100 end;
      "turns=\($turns) toolCalls=\($calls | length) toolsCalls=\($tools) callsPerTurn=\(per($calls | length)) toolsPerTurn=\(per($tools)) budget=\($budget) overBudget=\($turns > $budget) file=\($f)"' "$f"
  done
  exit 0
fi
FILE=${1:-$(git rev-parse --show-toplevel)/.claude/metrics/seat-events.jsonl}
jq -rs '[.[] | select(.tokens != null)] as $rows
  | ("unit", "role") as $key
  | $rows | group_by(.[$key])[]
  | "\($key)=\(.[0][$key]) seats=\(length) input=\(map(.tokens.input) | add) cachedInput=\(map(.tokens.cachedInput) | add) output=\(map(.tokens.output) | add)"' "$FILE"
