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
# pane included) are exempt, but for a Builder: past its own line (setup's
# Builder clear line, default 180K) it writes a handoff and builder-fresh-round.sh
# goes on in a fresh session of the same pane.
input=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$input"
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
if [ "$(git rev-parse --git-dir 2>/dev/null)" != "$(git rev-parse --git-common-dir 2>/dev/null)" ]; then
  [ "${COMMANDECK_BUILDER:-}" = 1 ] || exit 0
  . "${BASH_SOURCE[0]%/*}/lib/project.sh" && . "${BASH_SOURCE[0]%/*}/lib/context-size.sh" || exit 0
  LINE=$(pp_builder_clear_line 2>&1) || { echo "$LINE"; exit 0; }
  [ "$LINE" != off ] && ctx=$(context_size "$transcript") && [ "$ctx" -gt "$LINE" ] 2>/dev/null || exit 0
  HOOK_FIRE_ADVISE=1
  TOP=$(git rev-parse --show-toplevel); UNIT=${TOP##*/}; HAND=$TOP/.claude/briefs/$UNIT-handoff.md
  # The seat record takes the new session's id, so main-watch follows the new log; no record, no argument.
  REC=$(pp_run_file 2>/dev/null) && [ -f "${REC%/*}/seat-$UNIT-builder.txt" ] && REC=" $(printf '%q' "${REC%/*}/seat-$UNIT-builder.txt")" || REC=
  echo "CONTEXT $((ctx / 1000))K is over this Builder's $((LINE / 1000))K clear line: finish this step, then write $HAND for a fresh session of this pane: first the line 'Read .claude/briefs/$UNIT.md, then go on from here.', then decisions, unresolved findings, current commit, test evidence and what is left. Then start this in the background (run_in_background) and end the turn: bash $(printf '%q' "$(cd "${BASH_SOURCE[0]%/*}/../scripts" && pwd)")/builder-fresh-round.sh ${ORCA_TERMINAL_HANDLE:-<the handle of this pane>} $(printf '%q' "$HAND")$REC"
  exit 0
fi
# A /handoff whose restart did not finish keeps its marker (context-clear-restart.sh spends it only once a
# new main holds the resume prompt), and this pane is still main: the owner gets the reason in one line.
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
if [ -n "$sid" ] && [ -f "$HOME/.claude/checkpoints/$sid.handoff" ]; then
  why=$(grep -F " restart: " "$HOME/.claude/checkpoints/clear-hook.log" 2>/dev/null | grep -F -- "${ORCA_TERMINAL_HANDLE:-no handle}" | tail -1)
  echo "HANDOFF NOT DONE: this pane is still main. ${why:-No restart started: the Stop hook needs a checkpoint under 30 minutes old at ~/.claude/checkpoints/$sid.md.} Tell the owner this line first; fix what it names, then end the turn and the Stop hook tries again."
fi
LINE=$(pp_clear_line 2>/dev/null) || LINE=
LINE=${LINE:-${COMMANDECK_CLEAR_LINE:-200000}}   # the helper did not load
TPL=$(cd "$(dirname "$0")/../templates" && pwd)
# shellcheck source=lib/context-size.sh
. "$(dirname "$0")/lib/context-size.sh"
ctx=$(context_size "$transcript") || exit 0
[ "${ctx:-0}" -gt "$LINE" ] 2>/dev/null || exit 0
HOOK_FIRE_ADVISE=1
# Issue 275: pane-budget-gate.sh lets main past its line write only the checkpoint.
# A first run has no checkpoints folder; a marker not written lets every tool through, so that is said.
# The first crossing (no marker and no checkpoint yet) writes the skeleton once, about 6 s (measured), so main's one
# step past the line is the flagged call that fills it (#409).
CP=$HOME/.claude/checkpoints/$sid.md; first=0
[[ $sid =~ ^[A-Za-z0-9_-]+$ ]] && [ ! -e "$HOME/.claude/checkpoints/$sid.past-line" ] && [ ! -e "$CP" ] && first=1
[[ ! $sid =~ ^[A-Za-z0-9_-]+$ ]] || { mkdir -p "$HOME/.claude/checkpoints" && : > "$HOME/.claude/checkpoints/$sid.past-line"; } 2>/dev/null \
  || echo "Past-line marker NOT written ($HOME/.claude/checkpoints/$sid.past-line): no tool is held back, so the checkpoint Write is your next tool call."
SNAP=$(cd "${BASH_SOURCE[0]%/*}/../scripts" && pwd)/state-snapshot.sh
[ "$first" = 1 ] && bash "$SNAP" --out "$CP" >/dev/null 2>&1
STEP="bash $SNAP --out ${CP/#$HOME/\~} --goal '<one line>' --stage <unit>=<text> --next <unit>=<text> (stage and next for every live unit; --open-item '<text>' repeats; no quote or \$ inside a value; it writes the file first when none exists)"
# 40K past the line the step is over: a session that kept "finishing the step"
# reached 320K, so past this point the checkpoint Write is the next tool call.
# On a 200K window (standardContext) less than 40K is left before auto-compact,
# so that point is the line itself (issue 267).
PAST=$((LINE + 40000)); pp_flag standardContext 2>/dev/null && PAST=$LINE
if [ "$ctx" -gt "$PAST" ]; then
  echo "CONTEXT $((ctx / 1000))K is $(((ctx - LINE) / 1000))K PAST the $((LINE / 1000))K line: the NEXT tool call writes the checkpoint in ONE call: $STEP; then end the turn; the Stop hook restarts main. Never type /clear. No other look first."
  exit 0
fi
echo "CONTEXT $((ctx / 1000))K is over the $((LINE / 1000))K line: finish this step, write the checkpoint in ONE call: $STEP; then end the turn; the Stop hook restarts main ($TPL/main-session.md, Main never compacts)."
