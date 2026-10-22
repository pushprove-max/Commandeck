#!/usr/bin/env bash
# PreToolUse hook on AskUserQuestion: a worker or reviewer seat (a linked git
# worktree) may not use it. The question draws in the pane's own TUI and never
# reaches main's Orca inbox, so the seat waits on nobody: part 7 of
# guest-seamless sat stalled until the owner spotted the pane (2026-09-23). Main (the
# main checkout) keeps AskUserQuestion; it is how main asks the owner.
#
# For main it stamps the picker's open time (ms) per session: ruling-log.sh
# reads it to flag an answer back in under 2 s, which may be an Orca nudge
# typed into the open picker rather than the owner. It also refuses a main
# question whose first option is not the decoy.
#
# Self-test: bash hooks/__tests__/worker-ask-guard.test.sh
set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT")}
GITDIR=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
COMMON=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
TOP=$(git -C "${ROOT:-.}" rev-parse --show-toplevel 2>/dev/null)
# The Chief-of-Staff worktree is the owner's relay pane (owner rulings 2026-10-09):
# the owner sits in it, so its picker reaches him and it asks under main's rules.
if [ "$GITDIR" = "$COMMON" ] || [ "${TOP##*/}" = Chief-of-Staff ]; then
  # Main's pickers must lead with the decoy: an Orca alert typed into
  # an open picker answers its first option, at any latency.
  . "${BASH_SOURCE[0]%/*}/lib/ask-decoy.sh"
  # Setup's own questions go without it (owner ruling Q5): setup.sh --questions begin leaves this
  # marker, and the end of setup, or --questions end, takes it away. One older than an hour is stale.
  ASKING=$(cat "$COMMON/commandeck-setup-questions" 2>/dev/null)
  if [ "$GITDIR" = "$COMMON" ] && [[ $ASKING =~ ^[0-9]+$ ]] && [ $(( $(date +%s) - ASKING )) -lt 3600 ]; then :
  elif ! ask_decoy_first "$INPUT"; then
    printf '%s\n' \
      "BLOCKED: every question's FIRST option must be the decoy, label exactly: \`$ASK_DECOY\`" \
      "An Orca alert typed into an open picker picks the first option; the decoy makes that pick void. Put it first (description: \"Stray keypress guard, never pick this\") and ask again." >&2
    exit 2
  fi
  OPEN="$(dirname "${COMMANDECK_RULING_LOG:-$HOME/.claude/rulings/x}")/ask-open"
  SID=$(jq -r '.session_id // empty' <<<"$INPUT")
  [ -n "$SID" ] && mkdir -p "$OPEN" 2>/dev/null && date +%s%3N > "$OPEN/$SID" 2>/dev/null
  exit 0
fi

# 240 s: under the prompt cache's life. Orca's CLI also caps an ask's --timeout-ms at 1,800,000 (30 min) whatever is
# asked, so a 60-minute ask ends at half its timeout (issue 305); a longer wait is a --resume, never a bigger number.
# Two steps, not ${X:-$( { ...; } )}: Bash 3.2 cannot parse a brace group there.
run=${COMMANDECK_RUN:-}
[ -n "$run" ] || run=$( { tr -d '[:space:]' < "$(. "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_run_file)"; } 2>/dev/null)
printf '%s\n' \
  "BLOCKED: AskUserQuestion in a worker pane is never seen: it draws in this pane only and does not reach main's inbox, so you would wait forever." \
  "Ask main instead, ONCE, with the question, the options and your recommendation in one line:" \
  "  orca-ide orchestration ask --from ${ORCA_TERMINAL_HANDLE:-<your terminal handle>}${run:+ --to run:$run} --timeout-ms 240000 --question '<question>. Options: A) ... B) ... Recommend: ...'" \
  "It waits and prints main's answer; on a timeout, rerun with --resume <message id>." \
  "If a reasonable default exists, take it, write it in your evidence, and carry on instead of asking." >&2
exit 2
