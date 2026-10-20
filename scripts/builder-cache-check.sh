#!/usr/bin/env bash
# builder-cache-check.sh <worktree> [session-id] -- prove a launched Builder ran
# its main thread and its subagents on the 5-minute prompt cache (owner, 2026-10-18; setup's
# prompt-cache answer, which worktree-setup.sh writes as CLAUDE_CODE_PROMPT_CACHE_TTL).
# Reads the session's transcripts under ~/.claude/projects/<worktree-slug>/:
# <session>.jsonl (main thread) and <session>/subagents/agent-*.jsonl, field
# message.usage.cache_creation.ephemeral_1h_input_tokens / ephemeral_5m_input_tokens.
# Default session: the newest. Exit 1 when either side is wrong or unproved.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
WT=${1:?usage: builder-cache-check.sh <worktree> [session-id]}
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
PROJ=$HOME/.claude/projects/$(pp_slug "$(cd "$WT" && pwd -P)")
if [ -n "${2:-}" ]; then MAIN=$PROJ/$2.jsonl
else MAIN=$(ls -t "$PROJ"/*.jsonl 2>/dev/null | awk 'NR == 1' || true); fi
[ -f "${MAIN:-}" ] || { echo "no Builder transcript under $PROJ" >&2; exit 1; }
SUBS=("${MAIN%.jsonl}"/subagents/agent-*.jsonl)
[ -e "${SUBS[0]}" ] || { echo "no subagent transcript beside ${MAIN##*/}: run one Explore to prove the 5m side" >&2; exit 1; }
# Sums of each TTL's cache writes over assistant turns, as "<1h> <5m>". Claude
# Code 2.1.300's api-request rows hold no usage: dropped before jq slurps them.
sum() { grep -hv '^{"type":"api-request' "$@" | jq -rs '[.[] | select(.type == "assistant") | .message.usage.cache_creation // {}]
  | "\(map(.ephemeral_1h_input_tokens // 0) | add // 0) \(map(.ephemeral_5m_input_tokens // 0) | add // 0)"'; }
read -r MH MM <<<"$(sum "$MAIN")"
read -r SH SM <<<"$(sum "${SUBS[@]}")"
echo "${MAIN##*/}: main thread 1h=$MH 5m=$MM; ${#SUBS[@]} subagent transcript(s) 1h=$SH 5m=$SM"
OK=1
{ [ "$MM" -gt 0 ] && [ "$MH" -eq 0 ]; } || { echo "FAIL: the main thread must write only 5m cache (1h=$MH 5m=$MM)" >&2; OK=0; }
{ [ "$SM" -gt 0 ] && [ "$SH" -eq 0 ]; } || { echo "FAIL: subagents must write only 5m cache (1h=$SH 5m=$SM)" >&2; OK=0; }
[ "$OK" = 1 ]
