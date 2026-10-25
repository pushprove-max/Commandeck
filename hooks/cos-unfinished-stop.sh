#!/usr/bin/env bash
# Stop hook, Chief-of-Staff pane, and main's pane when no Chief of Staff runs (issue 364): blocks a reply that
# leaves its own work undone -- "haven't filed it", "want me to ...", "I can also ..." -- once per turn. The pane must
# do the work now, or keep the line and say in the same sentence why it needs the owner or is out of its authority.
# The second Stop of a turn (stop_hook_active) always passes, so a justified line never loops. Every other pane passes.
#
# Self-test: bash scripts/run-shell-tests.sh hooks/__tests__/cos-unfinished-stop.test.sh
set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
[ "$(jq -r '.stop_hook_active // false' <<<"$INPUT" 2>/dev/null)" = true ] && exit 0
[ "${COMMANDECK_REVIEWER:-}" = 1 ] && exit 0
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)}
GITDIR=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
COMMON=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
TOP=$(git -C "${ROOT:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0

T=$(jq -r '.transcript_path // empty' <<<"$INPUT" 2>/dev/null)
[ -n "$T" ] && [ -f "$T" ] || exit 0
# The last assistant reply's text, from the transcript's final assistant entry.
TEXT=$(tail -n 200 "$T" | jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // ""' 2>/dev/null)
[ -n "$TEXT" ] || exit 0

HIT=$(grep -oiE "(haven'?t|have not|did not|didn'?t|not yet) (filed|file it|sent|relayed|told main|fixed|checked)|not filed yet|want me to|shall i|should i |say (the word|if you want)|if you'?d like|i can (also )?(file|fix|send|check|do|open|run)|let me know if" <<<"$TEXT" | head -3 | paste -sd'|' -)
[ -n "$HIT" ] || exit 0
# Whose turn it is, asked only once a reply has a hit: the Chief of Staff's own worktree, or main's checkout when no
# Chief of Staff pane runs (cos-tell.sh --handle finds none). Any other pane, and main beside a live Chief of Staff, passes.
if [ "$GITDIR" != "$COMMON" ] && [ "${TOP##*/}" = Chief-of-Staff ]; then :
elif [ "$GITDIR" = "$COMMON" ] && ! bash "${BASH_SOURCE[0]%/*}/../scripts/cos-tell.sh" --handle >/dev/null 2>&1; then :
else exit 0; fi
R="Unfinished work in your reply ($HIT). If it is yours to do (file, relay, check, fix tooling), do it now and report it done. Keep the line only if it truly needs the owner or is outside your authority, and say why in the same sentence."
HOOK_FIRE_BLOCK=1
jq -cn --arg r "$R" '{decision:"block", reason:$r}'
