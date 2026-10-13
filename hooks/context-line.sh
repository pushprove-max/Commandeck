#!/usr/bin/env bash
# UserPromptSubmit hook (main session only): print one line when the session's
# context has passed the clear line, so the checkpoint-then-restart rule does
# not depend on main noticing (ruling 2026-09-12, token cuts: the average
# context per turn was 253K because clears happened at 350K and once at 1M).
#
# Reads the last assistant usage row of this session's transcript. The line is
# 200K (lowered from 350K 2026-10-10, main re-sent ~217K per turn); it
# must stay below the 500K auto-compact window in settings.local.json, or
# compaction fires first. Worker panes (linked worktrees, the Chief-of-Staff
# pane included) are exempt.
input=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$input"
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
if [ "$(git rev-parse --git-dir 2>/dev/null)" != "$(git rev-parse --git-common-dir 2>/dev/null)" ]; then exit 0; fi
LINE=$(pp_clear_line 2>/dev/null) || LINE=
LINE=${LINE:-${COMMANDECK_CLEAR_LINE:-200000}}   # the helper did not load
TPL=$(cd "$(dirname "$0")/../templates" && pwd)
# shellcheck source=lib/context-size.sh
. "$(dirname "$0")/lib/context-size.sh"
ctx=$(context_size "$transcript") || exit 0
[ "${ctx:-0}" -gt "$LINE" ] 2>/dev/null || exit 0
HOOK_FIRE_ADVISE=1
# 40K past the line the step is over: a session that kept "finishing the step"
# reached 320K, so past this point the checkpoint Write is the next tool call.
if [ "$ctx" -gt $((LINE + 40000)) ]; then
  echo "CONTEXT $((ctx / 1000))K is $(((ctx - LINE) / 1000))K PAST the $((LINE / 1000))K line: the NEXT tool call is the checkpoint Write (~/.claude/checkpoints/<session>.md from $TPL/checkpoint.md), then end the turn; the Stop hook restarts main. Never type /clear. No other look first."
  exit 0
fi
echo "CONTEXT $((ctx / 1000))K is over the $((LINE / 1000))K line: finish this step, write ~/.claude/checkpoints/<session>.md from $TPL/checkpoint.md, then end the turn; the Stop hook restarts main ($TPL/main-session.md, Main never compacts)."
