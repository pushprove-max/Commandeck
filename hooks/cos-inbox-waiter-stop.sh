#!/usr/bin/env bash
# Stop hook, Chief-of-Staff pane only: that pane wakes on main's
# messages only while its inbox poller, `scripts/cos-watch-inbox.sh
# [<handle>]`, runs, so a turn may not end without one alive. A live
# `orchestration check --wait` does not count: main's sends are addressed to
# the run, so `check --terminal <handle>` never returns them. Every other pane
# passes.
#
# Self-tests: bash scripts/run-shell-tests.sh hooks/__tests__/cos-inbox-waiter-stop*.test.sh
set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
[ "$(jq -r '.stop_hook_active // false' <<<"$INPUT" 2>/dev/null)" = true ] && exit 0
[ "${COMMANDECK_REVIEWER:-}" = 1 ] && exit 0
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)}
GITDIR=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
COMMON=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
TOP=$(git -C "${ROOT:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ "$GITDIR" != "$COMMON" ] && [ "${TOP##*/}" = Chief-of-Staff ] || exit 0
# Without the handle there is no poller to name, and a block could never clear.
H=${ORCA_TERMINAL_HANDLE:-}
[ -n "$H" ] || exit 0

# Matched in bash, not grep, so no matcher process carries the pattern in its argv.
while IFS= read -r CMD; do
  # The script must be the thing run, directly or by a shell: an editor or a
  # `cat` that only mentions it wakes nobody.
  read -r RUN ARG _ <<<"$CMD"
  case "${RUN##*/}" in bash|sh|zsh) RUN=$ARG ;; esac
  case "$RUN" in */cos-watch-inbox.sh) ;; *) continue ;; esac
  # A poller wakes only the pane it names, and it reads its first handle, so
  # every handle named must be this pane's. One that names none takes its
  # pane from its own environment, which the process list (the whole
  # machine's, every project's) does not show: it does not count.
  read -r -a WORDS <<<"$CMD"; NAMED=0
  for WORD in "${WORDS[@]}"; do
    case "$WORD" in *term_*) [ "$WORD" = "$H" ] || continue 2; NAMED=1 ;; esac
  done
  [ "$NAMED" = 1 ] || continue
  exit 0
done < <(ps -axo command= 2>/dev/null)

HOOK_FIRE_BLOCK=1
POLLER=$(cd "${BASH_SOURCE[0]%/*}/../scripts" && pwd)/cos-watch-inbox.sh
jq -n --arg r "No inbox poller is running for this pane ($H), so main's messages cannot wake it; orchestration check --wait is not enough, because main's sends go to the run and that waiter never sees them. Arm the poller in the background (run_in_background) before ending the turn: bash $POLLER $H" \
  '{decision:"block", reason:$r}'
exit 0
