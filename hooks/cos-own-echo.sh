#!/usr/bin/env bash
# UserPromptSubmit hook: Orca's "You have N orchestration messages. Run `orca orchestration check --run <run>`."
# nudge, in two panes.
# Main's checkout (issue 318): main spent a turn on every nudge, progress notes and its own echoes included. A nudge
# with no actionable message unread (pp_inbox_actionable: a wakeKinds type, to the run or to main's handle) is dropped
# and nothing acknowledged: the notes stay unread and orca-wait.sh shows them as held at the next real wake. One that
# is actionable is dropped too while its oldest is younger than wakeWindowSeconds and main-watch runs, so what arrives
# in one window wakes main once (Orca nudges again, and main-watch's tick wakes at the close); with main-watch up, a
# nudge also takes the window's one wake claim (pp_wake_claim), or is dropped when the watcher or a nudge took it. A
# nudge that passes, and main-watch's own typed wake, print the silent-wake line. Any Orca or jq failure passes.
# Chief-of-Staff pane: the relay spent a whole turn reading back its own sends. When every message of that batch is
# this pane's own, the batch is acknowledged and the prompt dropped. Any other prompt, pane or batch, and any Orca or
# jq failure, passes.
#
# Self-tests: bash scripts/run-shell-tests.sh hooks/__tests__/cos-own-echo.test.sh
set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# The cheap test first: this runs on every prompt in every pane.
[[ $INPUT == *"orchestration message"* || $INPUT == *"main-watch: "* ]] || exit 0
P=$(jq -r '.prompt // empty' <<<"$INPUT" 2>/dev/null)
RE='^[[:space:]]*You have [0-9]+ orchestration messages?\. Run `orca(-ide)? orchestration check --run (run_[A-Za-z0-9]+)`\.?[[:space:]]*$'
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)}
GITDIR=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
COMMON=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
if [ "$GITDIR" = "$COMMON" ]; then
  SILENT='Silent wake: if nothing in this wake needs the owner to act or decide, handle it and end the turn with no text to the owner.'
  # main-watch gates its typed wake on the same window itself.
  [[ $P == "main-watch: "* ]] && { echo "$SILENT"; exit 0; }
  [[ $P =~ $RE ]] || exit 0
  RUN=${BASH_REMATCH[2]}
  hold() { jq -cn --arg r "$1" '{decision: "block", reason: $r}'; exit 0; }
  HERE=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
  # main-watch.sh --status; COMMANDECK_MAIN_WATCH_UP (1 or 0) stands in for it in tests.
  up() { case ${COMMANDECK_MAIN_WATCH_UP:-} in 1) return 0 ;; 0) return 1 ;; esac; bash "$HERE/../scripts/main-watch.sh" --status >/dev/null 2>&1; }
  cd "${ROOT:-.}" && . "$HERE/../scripts/paths.sh" >/dev/null 2>&1 && A=$(pp_inbox_actionable "$RUN" "${ORCA_TERMINAL_HANDLE:-}") \
    || { echo "$SILENT"; exit 0; }
  [ "$A" != '[]' ] || hold "no actionable message: held unread for the next wake; no turn spent"
  NOW=${COMMANDECK_NOW:-$(date +%s)}
  if up; then
    ! pp_wake_window_open "$A" "$NOW" || hold "inside the wake window: one wake when it closes; no turn spent"
    pp_wake_claim "$NOW" || hold "main woke inside this wake window already; no turn spent"
  fi
  echo "$SILENT"; exit 0
fi
[[ $P =~ $RE ]] || exit 0
RUN=${BASH_REMATCH[2]}
TOP=$(git -C "${ROOT:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ "${TOP##*/}" = Chief-of-Staff ] || exit 0
H=${ORCA_TERMINAL_HANDLE:-}
[ -n "$H" ] || exit 0
OUT=$(timeout 10 orca-ide orchestration check --run "$RUN" --json 2>/dev/null) || exit 0
N=$(jq -er --arg h "$H" '.result.messages | select(type == "array" and length > 0 and all(.[]; .from_handle == $h)) | length' <<<"$OUT" 2>/dev/null) || exit 0
D=$(jq -er '.result.deliveryId | strings' <<<"$OUT" 2>/dev/null) || exit 0
timeout 10 orca-ide orchestration check --run "$RUN" --ack "$D" --peek --json >/dev/null 2>&1 || exit 0
jq -cn --arg n "$N" '{decision: "block", reason: "dropped Orca'"'"'s echo of this pane'"'"'s own \($n) message(s); no turn spent"}'
