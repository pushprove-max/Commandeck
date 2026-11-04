#!/usr/bin/env bash
# UserPromptSubmit hook: Orca's "You have N orchestration messages. Run `orca orchestration check --run <run>`."
# nudge, or its bare `orca orchestration check` form (D22: main takes the run from its run file), in two panes.
# Main's checkout (issue 318): main spent a turn on every nudge, progress notes and its own echoes included. A nudge
# with no actionable message unread (pp_inbox_actionable: a wakeKinds type, to the run or to main's handle) is dropped
# and nothing acknowledged: the notes stay unread and orca-wait.sh shows them as held at the next real wake. One that
# is actionable is dropped too while its oldest is younger than wakeWindowSeconds and main-watch runs, so what arrives
# in one window wakes main once (Orca nudges again, and main-watch's tick wakes at the close); with main-watch up, a
# nudge also takes the window's one wake claim (pp_wake_claim), or is dropped when the watcher or a nudge took it. A
# nudge that passes, and main-watch's own typed wake, print the silent-wake line. Any Orca or jq failure passes.
# Chief-of-Staff pane: the relay spent a whole turn reading back its own sends and main's mail (issue 643). The hook
# reads the batch with a peek (a consuming check would mark main's rows read) and the inbox page (the repeat history),
# and drops the prompt unless the batch holds a message addressed to this pane (its handle, or the relay tag) that the
# one wake rule (wake_class, "relay") wakes it for now. Nothing is acknowledged: a peek gives no delivery id (Builder
# check P5), so the batch stays unread and the inbox watcher still reads its own. Any other prompt or pane, and any
# Orca or jq failure, passes.
#
# Self-tests: bash scripts/run-shell-tests.sh hooks/__tests__/cos-own-echo.test.sh
set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Retire when: zero fires across 90 days from a project that installs the plugin, with Orca nudges present
# The cheap test first: this runs on every prompt in every pane.
[[ $INPUT == *"orchestration message"* || $INPUT == *"main-watch: "* ]] || exit 0
P=$(jq -r '.prompt // empty' <<<"$INPUT" 2>/dev/null)
RE='^[[:space:]]*You have [0-9]+ orchestration messages?\. Run `orca(-ide)? orchestration check( --run (run_[A-Za-z0-9]+))?`\.?[[:space:]]*$'
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)}
GITDIR=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
COMMON=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
if [ "$GITDIR" = "$COMMON" ]; then
  SILENT='Silent wake: if nothing in this wake needs the owner to act or decide, handle it and end the turn with no text to the owner.'
  # main-watch gates its typed wake on the same window itself.
  [[ $P == "main-watch: "* ]] && { echo "$SILENT"; exit 0; }
  [[ $P =~ $RE ]] || exit 0
  RUN=${BASH_REMATCH[3]}
  hold() { jq -cn --arg r "$1" '{decision: "block", reason: $r}'; exit 0; }
  HERE=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
  # main-watch.sh --status; COMMANDECK_MAIN_WATCH_UP (1 or 0) stands in for it in tests.
  up() { case ${COMMANDECK_MAIN_WATCH_UP:-} in 1) return 0 ;; 0) return 1 ;; esac; bash "$HERE/../scripts/main-watch.sh" --status >/dev/null 2>&1; }
  # The bare nudge names no run: main's is its run file's; with none recorded the prompt passes.
  cd "${ROOT:-.}" && . "$HERE/../scripts/paths.sh" >/dev/null 2>&1 && RUN=${RUN:-$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE")} \
    && [ -n "$RUN" ] && A=$(pp_inbox_actionable "$RUN" "${ORCA_TERMINAL_HANDLE:-}") \
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
RUN=${BASH_REMATCH[3]}
TOP=$(git -C "${ROOT:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ "${TOP##*/}" = Chief-of-Staff ] || exit 0
H=${ORCA_TERMINAL_HANDLE:-}
[ -n "$H" ] || exit 0
. "${BASH_SOURCE[0]%/*}/../scripts/paths.sh" >/dev/null 2>&1 || exit 0
# The check the nudge named, as a peek (D22): the bare form names no run.
OUT=$(timeout 10 orca-ide orchestration check ${RUN:+--run "$RUN"} --peek --full --json 2>/dev/null) || exit 0
# A page not read is no repeat history (the rule's own default): never a reason to pass or to hold.
ALL=$(timeout 10 orca-ide orchestration inbox --limit 500 --full --json 2>/dev/null | jq -c '.result.messages | arrays' 2>/dev/null) || ALL='[]'
# Issue 319: its own sends carry the name it was given (chiefOfStaff.name) as well as its handle, in any case.
NAME=$(jq -r '.chiefOfStaff.name // empty' "${COMMON%/.git}/.claude/commandeck.json" 2>/dev/null)
# The page goes through a file, not an argument: a full page of long bodies is past the one-argument limit.
R=$(jq -er --arg h "$H" --arg n "$NAME" --slurpfile all <(printf '%s' "${ALL:-[]}") "$PP_JQ_WAKES"'$all[0] as $all | .result.messages | arrays
  | [.[] | objects | (.from_handle // "" | ascii_downcase) as $f | $f == ($h | ascii_downcase) or ($n != "" and $f == ($n | ascii_downcase))] as $own
  | [.[] | objects | select((.from_handle // "" | ascii_downcase) as $f | ($f == ($h | ascii_downcase) or ($n != "" and $f == ($n | ascii_downcase))) | not)
      | select(.to_handle == $h or recipient == "chief-of-staff")
      | select(wake_class([]; []; $all; "relay") as $c | $c == "now" or ($c == "batch" and .to_handle == $h))] as $mail
  | if ($mail | length) > 0 then "pass"
    elif ($own | length) > 0 and all($own[]; .) then "dropped Orca'"'"'s echo of this pane'"'"'s own \($own | length) message(s), left unread; no turn spent"
    else "no message for this pane that wakes it now (\(length) in the batch), left unread; no turn spent" end' <<<"$OUT" 2>/dev/null) || exit 0
[ "$R" = pass ] || jq -cn --arg r "$R" '{decision: "block", reason: $r}'
