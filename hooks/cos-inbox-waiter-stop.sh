#!/usr/bin/env bash
# Stop hook, Chief-of-Staff pane only: that pane wakes only while its
# watchers run, so a turn may not end without each one alive: the decisions,
# alerts and limit watchers, and the timer check `scripts/cos-check.sh`. The
# inbox poller (`scripts/cos-watch-inbox.sh`) is not checked here: cos-inbox-arm-stop.sh
# starts it, as an asyncRewake hook that never blocks (issue 575).
# The block names each missing watcher with its start command, by setup's
# stable link when it points here: the path the session instructions name, and
# the one setup and /commandeck:update keep current. Every other pane passes.
#
# Self-tests: bash scripts/run-shell-tests.sh hooks/__tests__/cos-inbox-waiter-stop*.test.sh
set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Retire when: no Chief-of-Staff pane in 90 days of rows from a project that installs the plugin
[ "$(jq -r '.stop_hook_active // false' <<<"$INPUT" 2>/dev/null)" = true ] && exit 0
[ "${COMMANDECK_REVIEWER:-}" = 1 ] && exit 0
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)}
GITDIR=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
COMMON=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
TOP=$(git -C "${ROOT:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ "$GITDIR" != "$COMMON" ] && [ "${TOP##*/}" = Chief-of-Staff ] || exit 0
# The owner reads this pane (issue 644): a reply of only verdicts, still-running lines or counts is held once
# (stop_hook_active above ends the second try). Any question, ask or news line passes it.
HOLD=; KINDS=; WORDS=
MSG=$(jq -r '.last_assistant_message // empty' <<<"$INPUT" 2>/dev/null)
if [ -n "$MSG" ]; then
  ASK='(approve|decide|confirm|choose|pick|reply|roll back)([^[:alnum:]]|$)' NL=$'\n'
  shopt -s nocasematch
  if [[ $MSG == *\?* || $MSG =~ (^|$NL)[[:space:]]*(QUESTION|BLOCKED): || $MSG =~ your\ call \
    || $MSG =~ (^|$NL)[[:space:]]*((-|\*|[0-9]+\.)[[:space:]]+)?([>][[:space:]]*)?(\*\*)?(please[[:space:]]+)?$ASK \
    || $MSG =~ (^|[^[:alnum:]])you[[:space:]]+$ASK ]]; then HOLD=
  else
    HOLD=1
    while IFS= read -r L; do
      [[ $L =~ [^[:space:]] ]] || continue
      K=
      [[ $L == *%* ]] || {
        shopt -u nocasematch
        [[ $L =~ (VERDICT:|(^|[^[:alnum:]-])(NO-GO|NARROWED\ GO|GO|PASS|FAIL)([^[:alnum:]-]|$)) ]] && { K=verdict; WORDS+=" ${BASH_REMATCH[3]:-VERDICT:}"; }
        shopt -s nocasematch
        [[ $L =~ (still\ running|still\ going|in\ progress|running|waiting\ on) ]] && { K+=" still-running"; WORDS+=" ${BASH_REMATCH[1]}"; }
        [[ $L =~ ([0-9]+\ of\ [0-9]+|[0-9]+/[0-9]+) ]] && { K+=" count"; WORDS+=" ${BASH_REMATCH[1]}"; }
      }
      [ -n "$K" ] && KINDS+=" $K" || { HOLD=; break; }
    done <<<"$MSG"
  fi
  shopt -u nocasematch
fi
if [ -n "$HOLD" ]; then
  KINDS=$(printf '%s\n' $KINDS | sort -u | paste -sd/ -)
  HOLD="Your reply is only $KINDS lines (matched:$WORDS). The owner reads this pane: if the owner must act, say what you need (a question, an ask or a decision); if nothing is needed from the owner, end the turn as is. "
fi
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

# The watchers take no handle, so the process list cannot tell this project's
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
[ ${#MISSING[@]} -gt 0 ] || [ -n "$HOLD" ] || exit 0

HOOK_FIRE_REASON=watcher-not-running
R=
if [ ${#MISSING[@]} -gt 0 ]; then R="Arm each missing watcher in the background (run_in_background) before ending the turn. $(printf '%s. ' "${MISSING[@]}")"; fi
[ -z "$HOLD" ] || { R+=$HOLD; HOOK_FIRE_REASON=owner-reply-${KINDS//\//-}; [ ${#MISSING[@]} -eq 0 ] || HOOK_FIRE_REASON=watcher-not-running; }
HOOK_FIRE_BLOCK=1
jq -n --arg r "$R" '{decision:"block", reason:$r}'
exit 0
