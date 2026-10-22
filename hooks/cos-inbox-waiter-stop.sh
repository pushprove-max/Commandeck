#!/usr/bin/env bash
# Stop hook, Chief-of-Staff pane only: that pane wakes only while its
# watchers run, so a turn may not end without each one alive: the inbox poller,
# `scripts/cos-watch-inbox.sh [<handle>]`, the decisions, alerts and limit
# watchers, and the timer check `scripts/cos-check.sh`. A live `orchestration check --wait` does not count: main's sends
# are addressed to the run, so `check --terminal <handle>` never returns them.
# The block names each missing watcher with its start command, by setup's
# stable link when it points here: the path the session instructions name, and
# the one setup and /commandeck:update keep current. Every other pane passes.
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
PLUGIN=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
[ "$(readlink -f "$HOME/.commandeck/plugin" 2>/dev/null)" != "$(readlink -f "$PLUGIN")" ] || PLUGIN=$HOME/.commandeck/plugin
S=$(printf '%q' "$PLUGIN")/scripts
MISSING=()
# runs <command> <script>: the script is the thing the command runs, directly or
# by a shell: an editor, a `cat` or a `tail -f` that only mentions it wakes nobody.
runs() {
  local run arg
  read -r run arg _ <<<"$1"
  case "${run##*/}" in bash|sh|zsh) run=$arg ;; esac
  [[ $run == */"$2" ]]
}

# Matched in bash, not grep, so no matcher process carries the pattern in its argv.
while IFS= read -r CMD; do
  runs "$CMD" cos-watch-inbox.sh || continue
  # A poller wakes only the pane it names, and it reads its first handle, so
  # every handle named must be this pane's. One that names none takes its
  # pane from its own environment, which the process list (the whole
  # machine's, every project's) does not show: it does not count.
  read -r -a WORDS <<<"$CMD"; NAMED=0
  for WORD in "${WORDS[@]}"; do
    case "$WORD" in *term_*) [ "$WORD" = "$H" ] || continue 2; NAMED=1 ;; esac
  done
  [ "$NAMED" = 1 ] || continue
  INBOX=1; break
done < <(ps -axo command= 2>/dev/null)
[ -n "${INBOX-}" ] || MISSING+=("No inbox poller is running for this pane ($H), so main's messages cannot wake it; orchestration check --wait is not enough, because main's sends go to the run and that waiter never sees them: bash $S/cos-watch-inbox.sh $H")

# The others take no handle, so the process list cannot tell this project's
# from another's: each records its pid per project (cos-lib.sh cos_wait), and
# counts while that pid still runs that watcher.
. "${BASH_SOURCE[0]%/*}/lib/project.sh"; pp_cos_key "$ROOT"
# The fifth, cos-check.sh, is the 50-minute timer check that names any of them down (issue 290).
for W in cos-watch-decisions:"open decisions for the owner" cos-watch-alerts:"dashboard alerts" cos-watch-limit:"the 7-day limit" \
  cos-check:"the 50-minute check that names a watcher down and messages missed"; do
  N=${W%%:*}
  PID=$(cat "$COS_KEY.$N.pid" 2>/dev/null)
  runs "$(ps -o command= -p "${PID:-0}" 2>/dev/null)" "$N.sh" || MISSING+=("The ${N#cos-watch-} watcher is not running (${W#*:}): bash $S/$N.sh")
done
[ ${#MISSING[@]} -gt 0 ] || exit 0

HOOK_FIRE_BLOCK=1
jq -n --arg r "Arm each missing watcher in the background (run_in_background) before ending the turn. $(printf '%s. ' "${MISSING[@]}")" \
  '{decision:"block", reason:$r}'
exit 0
