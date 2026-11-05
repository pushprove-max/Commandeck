#!/usr/bin/env bash
# Stop hook, lane panes only (Fast-lane, Research-lane), registered `asyncRewake`: it never blocks the stop. It starts the
# pane's inbox poller (`scripts/cos-watch-inbox.sh <handle> --lane <lane>`) as its own child when none runs for this pane, and
# waits on it. The poller exits when a message meant for the relay arrives; this hook then exits 2 with the
# poller's text on stderr, which wakes the pane with no re-arm turn (issue 575). A poller that ends with no
# text wakes nobody.
# The stop that ends a wake turn carries stop_hook_active true; it starts the next poller only when the wake
# left `$COS_KEY.inbox-woke`, so a second stop of one chain with no wake before it starts none. A TERM, HUP or
# INT ends the poller. cos-inbox-waiter-stop.sh keeps blocking for the other watchers: an asyncRewake hook cannot block.
# Every other pane, the relay (its poller runs under scripts/cos-supervise.sh), a reviewer and Codex start none.
#
# Self-tests: bash scripts/run-shell-tests.sh hooks/__tests__/cos-inbox-waiter-stop*.test.sh
set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Retire when: Claude Code wakes an idle pane on a background job's exit itself, or no Chief-of-Staff pane in 90 days of rows
[ "${AGENT_KIND:-claude}" = codex ] && exit 0
[ "${COMMANDECK_REVIEWER:-}" = 1 ] && exit 0
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)}
GITDIR=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
COMMON=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
TOP=$(git -C "${ROOT:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
. "${BASH_SOURCE[0]%/*}/lib/project.sh"
# A lane (Fast-lane, Research-lane: issue 614), which keeps its own poller and state key. The relay's poller runs
# under scripts/cos-supervise.sh (issue 584): a relay Stop starting one too would run a second beside it.
[ "$GITDIR" != "$COMMON" ] || exit 0
case ${TOP##*/} in Fast-lane|Research-lane) ;; *) exit 0 ;; esac
LANE=${TOP##*/}; LANE=${LANE,,}
# Without the handle there is no pane to wake.
H=${ORCA_TERMINAL_HANDLE:-}
[ -n "$H" ] || exit 0

# Only a JSON true counts: the text "true" or junk reads as not active.
ACTIVE=0
jq -e '.stop_hook_active == true' <<<"$INPUT" >/dev/null 2>&1 && ACTIVE=1
pp_cos_key "$ROOT"; [ -z "$LANE" ] || COS_KEY=$COS_KEY.lane-$LANE
# The mark belongs to the wake before this stop: read it and clear it, so it serves one stop.
WOKE=0; [ -e "$COS_KEY.inbox-woke" ] && WOKE=1
rm -f "$COS_KEY.inbox-woke"
[ "$ACTIVE" = 0 ] || [ "$WOKE" = 1 ] || exit 0

PLUGIN=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
[ "$(readlink -f "$HOME/.commandeck/plugin" 2>/dev/null)" != "$(readlink -f "$PLUGIN")" ] || PLUGIN=$HOME/.commandeck/plugin
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
  exit 0
done < <(ps -axo command= 2>/dev/null)

OUT=$(mktemp "${TMPDIR:-/tmp}/cos-inbox-arm.XXXXXX") || exit 0
cd "$ROOT" 2>/dev/null
bash "$PLUGIN/scripts/cos-watch-inbox.sh" "$H" ${LANE:+--lane "$LANE"} >"$OUT" 2>/dev/null &
POLLER=$!
stop() { kill "$POLLER" 2>/dev/null; wait "$POLLER" 2>/dev/null; rm -f "$OUT"; exit 0; }
trap stop TERM HUP INT
wait "$POLLER" 2>/dev/null
if [ -s "$OUT" ]; then
  : >"$COS_KEY.inbox-woke"
  { echo "The inbox poller for this pane woke it:"; cat "$OUT"; } >&2
  rm -f "$OUT"
  HOOK_FIRE_REASON=inbox-woke
  exit 2
fi
rm -f "$OUT"
exit 0
