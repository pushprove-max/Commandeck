#!/usr/bin/env bash
# to-main.sh [--unit <unit>] <type> <subject> <body> -- send one message to main
# (or to the Builder of <unit>), the one way a script or the relay reaches it.
# The pane is looked up by its worktree at send time (pp_pane_of), never taken
# from a saved handle: a restart gives the pane a new one, and a send to the old
# handle is lost. With no live pane the message is queued, and the pane's next
# session shows it first (inbox-drain.sh, at session start). A send Orca refuses because the
# pane closed after the lookup is looked up once more, then queued. The sent line ends with the
# message id (ask-main.sh waits on it). Exit 0: sent; 3: queued, said on stderr; 1: the send failed.
# A message the Chief of Staff sends main is the owner's, and owed a reply to the
# relay: marked in $PP_SCRATCH/cos-owed until main sends one (cos-tell.sh --note)
# or the relay's watcher flags main's turn ending without it (cos-watch-inbox.sh);
# main's Stop hook (ask-stop-records-decision.sh) holds such a turn once.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
KEY=main WT=$PP_MAIN WHO=main
owed() {
  [ "$KEY" = main ] && [ "$(git rev-parse --show-toplevel 2>/dev/null)" -ef "$PP_WORKSPACES/Chief-of-Staff" ] || return 0
  # Under the lock pp_owed_clear holds from its read to its removal: a mark written between them would be removed.
  mkdir -p "$PP_SCRATCH" && { flock -w 10 9 && printf '%s\t%s\n' "$(date +%s)" "${1//[$'\t\n']/ }" > "$PP_SCRATCH/cos-owed"; } 9>>"$PP_SCRATCH/cos-owed.lock" \
    || echo "to-main: the reply main owes \"$1\" was not marked: main's Stop hook will not hold for it" >&2
}
if [ "${1:-}" = --unit ]; then
  [[ ${2:-} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "to-main: --unit takes a unit name" >&2; exit 2; }
  # unit-<name>: a Builder named "main" must not share main's queue.
  KEY=unit-$2 WT=$PP_WORKSPACES/$2 WHO="the Builder of $2"; shift 2
fi
[ $# = 3 ] || { echo "usage: to-main.sh [--unit <unit>] <type> <subject> <body>" >&2; exit 2; }
queue() {
  mkdir -p "$PP_SCRATCH/queue" && jq -cn --arg at "$(date +%FT%T)" --arg t "$1" --arg s "$2" --arg b "$3" '{at: $at, type: $t, subject: $s, body: $b}' >> "$PP_SCRATCH/queue/$KEY.jsonl" \
    || { echo "to-main: $WHO is not running, and the message could not be queued: it is lost" >&2; exit 1; }
  echo "to-main: $WHO is not running; message queued ($PP_SCRATCH/queue/$KEY.jsonl), shown first when it starts again" >&2
  # Issue 368: a queue is read by a main session that starts in this checkout, so a main running elsewhere never sees it.
  [ "$KEY" != main ] || echo "to-main: no main pane was found in ${COMMANDECK_MAIN_PANE_DIR:-$WT}, so main does not see this queue until a main session starts in $PP_MAIN. A main running in another checkout must be told another way." >&2
  pp_wake_log to-main "$KEY" "$1: ${2:0:60}" queued
  owed "$2"; exit 3
}
H=$(pp_seat_pane "$KEY" "$WT")
[ -n "$H" ] || queue "$@"
# A service caller (the dashboard's) has no pane: it sends as main's or the coordinator's (pp_sender, issue 321).
FROM=$(pp_sender) || FROM=
send() { OUT=$(orca-ide orchestration send ${FROM:+--from "$FROM"} --to "$H" --type "$1" --subject "$2" --body "$3" --json 2>/dev/null); }
sent() { jq -e '.ok' >/dev/null 2>&1 <<<"$OUT"; }
# Orca's code for a pane that closed after the lookup.
gone() { [ "$(jq -r '.error.code // empty' 2>/dev/null <<<"$OUT")" = terminal_not_found ]; }
send "$@"
# Look once more and retry on a different live pane; none left means queued, not lost.
if ! sent && gone; then
  H2=$(pp_seat_pane "$KEY" "$WT")
  if [ -n "$H2" ] && [ "$H2" != "$H" ]; then H=$H2; send "$@"; fi
  if ! sent && gone; then queue "$@"; fi
fi
sent \
  || { ERR=$(jq -r '.error.message // tostring' 2>/dev/null <<<"$OUT" || head -c 300 <<<"$OUT")
       echo "to-main: the send to $WHO ($H) failed: $ERR; the message was not delivered" >&2
       pp_wake_log to-main "$H" "$1: ${2:0:60}" refused "${ERR:0:200}"; exit 1; }
MID=$(jq -r '.result.message.id // empty' 2>/dev/null <<<"$OUT"); MID=${MID:+ id $MID}
owed "$2"
# A pane with its own question or permission prompt open reads nothing until that prompt is answered there.
if orca-ide terminal read --terminal "$H" --screen --json 2>/dev/null | jq -r '.result.terminal.tail | if type == "array" then .[] else error end' 2>/dev/null | grep -Eq "$PROMPT_BLOCKED"; then
  pp_wake_log to-main "$H" "$1: ${2:0:60}" sent_blocked
  echo "to-main: sent to $WHO ($H)$MID, but its pane shows an open question or permission prompt: it reads this only after that prompt is answered in its own pane"
else
  pp_wake_log to-main "$H" "$1: ${2:0:60}" sent
  echo "to-main: sent to $WHO ($H)$MID"
fi
