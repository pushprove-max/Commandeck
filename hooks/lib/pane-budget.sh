#!/usr/bin/env bash
# pane_budget <transcript.jsonl> <worktree> -- measure a worker pane against the
# budget pane-budget-gate.sh enforces. Sets PB_SUMMARY (the counts and limits)
# and PB_CONTEXT; returns 0 within budget, 1 over it.
#
# One home for the limits and the counts. The limits are the plugin's
# config/pane-budget.json; a brief that names a plan with measured budgets
# (.claude/plans/<plan>.status.json) replaces them for its unit.
# The budget is context and compactions. Turns are counted for the summary
# only: no pane of any role is stopped for its number of turns
# (owner ruling 2026-10-12).
# shellcheck source=context-size.sh
. "$(dirname "${BASH_SOURCE[0]}")/context-size.sh"
pane_budget() {
  local LOG=$1 DIR=$2 PLUGIN=${BASH_SOURCE[0]%/*}/../.. UNIT CONFIG CONTEXT_LIMIT COMPACTION_LIMIT BRIEF PLAN CLASS STATUS BUDGET_NOTE COUNT CONTEXT CONTEXT_METRIC COMPACTIONS
  UNIT=$(basename "$DIR")
  CONFIG=${PANE_BUDGET_CONFIG:-"$PLUGIN/config/pane-budget.json"}
  CONTEXT_LIMIT=$(jq -r '.context' "$CONFIG"); COMPACTION_LIMIT=$(jq -r '.compactions // empty' "$CONFIG")
  BUDGET_NOTE="fixed config"
  BRIEF="$DIR/.claude/briefs/$UNIT.md"
  PLAN=${PANE_BUDGET_PLAN:-}
  if [ -z "$PLAN" ] && [ -f "$BRIEF" ]; then
    PLAN=$(sed -n 's@^Plan:.*\.claude/plans/\([^` ]*\)\.md.*@\1@p' "$BRIEF" | head -1)
  fi
  PLAN=${PLAN##*/}; PLAN=${PLAN%.status.json}; PLAN=${PLAN%.md}
  CLASS=""
  if [ -f "$BRIEF" ]; then
    CLASS=$(head -12 "$BRIEF" | tr '\n' ' ' | grep -ioE 'Class:[[:space:]]*[A-Za-z/-]+' | head -1 | tr '[:upper:]' '[:lower:]')
    case "$CLASS" in
      *gate-ci*|*gate/ci*) CLASS=gate-ci ;;
      *cross-file*) CLASS=cross-file ;;
      *risky*) CLASS=risky ;;
      *runtime*) CLASS=runtime ;;
      *tooling*) CLASS=tooling ;;
      *) CLASS="" ;;
    esac
  fi
  STATUS="$DIR/.claude/plans/$PLAN.status.json"
  if [ -n "$PLAN" ] && [ -n "$CLASS" ] && [ -f "$STATUS" ] && jq -e --arg class "$CLASS" '
    .budget[$class] as $budget
    | ($budget.context.p90 | type == "number" and . > 0 and floor == .)
      and ($budget.compactions.p90 | type == "number" and . >= 0 and floor == .)
  ' "$STATUS" >/dev/null 2>&1; then
    CONTEXT_LIMIT=$(jq -r --arg class "$CLASS" '.budget[$class].context.p90' "$STATUS")
    COMPACTION_LIMIT=$(jq -r --arg class "$CLASS" '.budget[$class].compactions.p90' "$STATUS")
    BUDGET_NOTE="measured $CLASS class"
  elif [ -n "$PLAN" ] && [ -n "$CLASS" ] && [ -f "$STATUS" ]; then
    BUDGET_NOTE="fixed config; $CLASS class entry incomplete"
  fi
  # A turn is one reply (message.id): Claude writes a line per content block, so
  # a line count ran ~3.5x high.
  COUNT=$(grep -F '"type":"assistant"' "$LOG" | jq -rR 'fromjson? | .message.id // .uuid // input_line_number' | sort -u | wc -l | tr -d ' ')
  # The CURRENT context, not the historical max: a max never falls after a
  # compaction, and one transient oversized request used to pin it forever.
  CONTEXT=$(context_size "$LOG" || true)
  if [ -n "$CONTEXT" ]; then CONTEXT_METRIC="usage input tokens"; else CONTEXT=$(( $(wc -c < "$LOG") / 4 )); CONTEXT_METRIC="bytes/4 fallback (no usage record)"; fi
  COMPACTIONS=$(grep -Ec '"isCompactSummary"[[:space:]]*:[[:space:]]*true' "$LOG" || true)
  PB_CONTEXT=$CONTEXT
  PB_SUMMARY="turns=$COUNT context=$CONTEXT/$CONTEXT_LIMIT [$CONTEXT_METRIC] compactions=$COMPACTIONS/$COMPACTION_LIMIT; budget=$BUDGET_NOTE"
  [ "$CONTEXT" -le "$CONTEXT_LIMIT" ] && { [ -z "$COMPACTION_LIMIT" ] || [ "$COMPACTIONS" -le "$COMPACTION_LIMIT" ]; }
}
