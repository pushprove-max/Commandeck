#!/usr/bin/env bash
# builder-cache-check.sh <worktree> [session-id] -- prove a launched Builder ran
# its main thread and its subagents on the prompt cache of the Builder and worker answer (issue 367; 5m
# when unanswered, leave proves nothing), which worktree-setup.sh writes as CLAUDE_CODE_PROMPT_CACHE_TTL.
# Reads the session's transcripts under ~/.claude/projects/<worktree-slug>/:
# <session>.jsonl (main thread) and <session>/subagents/agent-*.jsonl, field
# message.usage.cache_creation.ephemeral_1h_input_tokens / ephemeral_5m_input_tokens.
# Default session: the newest. Exit 1 when either side is wrong or unproved.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
WT=${1:?usage: builder-cache-check.sh <worktree> [session-id]}
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
# The answer of the worktree's own project, as worktree-setup.sh reads it; paths.sh resolved the caller's project.
P=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && P=${P%/.git} || P=$PP_MAIN
WANT=$(PP_MAIN=$P pp_option workerPromptCacheTtl)
case $WANT in
  leave) echo "workers' prompt cache: leave (setup sets no TTL); nothing to prove"; exit 0 ;;
  1h) OTHER=5m ;;
  *) WANT=5m OTHER=1h ;;
esac
PROJ=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(pp_slug "$(cd "$WT" && pwd -P)")
if [ -n "${2:-}" ]; then MAIN=$PROJ/$2.jsonl
else MAIN=$(ls -t "$PROJ"/*.jsonl 2>/dev/null | awk 'NR == 1' || true); fi
[ -f "${MAIN:-}" ] || { echo "no Builder transcript under $PROJ" >&2; exit 1; }
SUBS=("${MAIN%.jsonl}"/subagents/agent-*.jsonl)
[ -e "${SUBS[0]}" ] || { echo "no subagent transcript beside ${MAIN##*/}: run one Explore to prove the $WANT side" >&2; exit 1; }
# Sums of each TTL's cache writes over assistant turns, as "<1h> <5m>". Claude
# Code 2.1.300's api-request rows hold no usage: dropped before jq slurps them.
sum() { grep -hv '^{"type":"api-request' "$@" | jq -rs '[.[] | select(.type == "assistant") | .message.usage.cache_creation // {}]
  | "\(map(.ephemeral_1h_input_tokens // 0) | add // 0) \(map(.ephemeral_5m_input_tokens // 0) | add // 0)"'; }
read -r MH MM <<<"$(sum "$MAIN")"
read -r SH SM <<<"$(sum "${SUBS[@]}")"
echo "${MAIN##*/}: main thread 1h=$MH 5m=$MM; ${#SUBS[@]} subagent transcript(s) 1h=$SH 5m=$SM"
OK=1
# the wanted TTL's sum is over 0 and the other's is 0, per side
if [ "$WANT" = 5m ]; then MW=$MM MO=$MH SW=$SM SO=$SH; else MW=$MH MO=$MM SW=$SH SO=$SM; fi
{ [ "$MW" -gt 0 ] && [ "$MO" -eq 0 ]; } || { echo "FAIL: the main thread must write only $WANT cache (1h=$MH 5m=$MM)" >&2; OK=0; }
{ [ "$SW" -gt 0 ] && [ "$SO" -eq 0 ]; } || { echo "FAIL: subagents must write only $WANT cache (1h=$SH 5m=$SM)" >&2; OK=0; }
[ "$OK" = 1 ]
