#!/usr/bin/env bash
# cos-tell.sh <text...> | cos-tell.sh --handle | cos-tell.sh --note <subject> <body>
# Sends text (arguments or stdin) to the Chief of Staff pane, for a dictation
# shortcut or any script. --handle prints the pane's handle and sends nothing.
# The pane is found by its worktree, not a saved handle: handles change on restart.
# --note is main's note to the relay: sent to main's run (run:<id>), the durable
# mailbox the relay's inbox watcher reads. A pane handle is a live-only mailbox,
# and notes sent there while the pane was busy never reached it. Exits 1, saying
# so, unless Orca confirms a stored message.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -u
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
if [ "${1:-}" = --note ]; then
  [ $# = 3 ] || { echo "usage: cos-tell.sh --note <subject> <body>" >&2; exit 2; }
  RUN=$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE")
  [ -n "$RUN" ] || { echo "cos-tell: NOT sent: no run recorded in $PP_RUN_FILE, so the relay has no durable mailbox" >&2; exit 1; }
  SENT=$(date +%s)
  # A service caller (the dashboard's) has no pane: it sends as main's or the coordinator's (pp_sender, issue 321).
  FROM=$(pp_sender) || FROM=
  OUT=$(orca-ide orchestration send --run "$RUN" ${FROM:+--from "$FROM"} --to "run:$RUN" --type status --subject "$2" --body "$3" --json 2>&1)
  jq -e '.ok == true and ([.. | strings | select(test("^msg_"))] | length > 0) and (tostring | test("not durable") | not)' <<<"$OUT" >/dev/null 2>&1 \
    || { pp_wake_log cos-tell "run:$RUN" "note: ${2:0:60}" refused "$(head -c 200 <<<"$OUT")"; echo "cos-tell: NOT sent: Orca did not confirm a stored message to run:$RUN: $(head -c 300 <<<"$OUT")" >&2; exit 1; }
  pp_wake_log cos-tell "run:$RUN" "note: ${2:0:60}" sent
  # The owner's message to main has its reply (to-main.sh), when main sent this: a worker's note is not one,
  # and neither is this note to a message marked while it was being sent.
  [ "$(git rev-parse --show-toplevel 2>/dev/null)" -ef "$PP_MAIN" ] && pp_owed_clear "$SENT"
  echo "cos-tell: note stored in run:$RUN for the Chief of Staff"; exit 0
fi
HANDLE=$(pp_pane_of "$PP_WORKSPACES/Chief-of-Staff")
[ -n "$HANDLE" ] || { echo "Chief of Staff pane not found (no claude pane in $PP_WORKSPACES/Chief-of-Staff)" >&2; exit 1; }
[ "${1:-}" != --handle ] || { echo "$HANDLE"; exit 0; }
TEXT=${*:-$(cat)}
[ -n "$TEXT" ] || { echo "nothing to send" >&2; exit 1; }
OUT=$(orca-ide terminal send --terminal "$HANDLE" --text "[dictated] $TEXT" --enter --json 2>&1)
# accepted:false: Orca took the request and typed nothing (a paired phone can hold the pane's keyboard).
if jq -e 'any(.. | objects | select(has("accepted")) | .accepted; . == false)' >/dev/null 2>&1 <<<"$OUT"; then
  pp_wake_log cos-tell "$HANDLE" dictation refused "accepted:false"
  echo "cos-tell: NOT sent: Orca took no input in the relay pane (accepted:false); a paired phone may hold its keyboard. Main's notes go with --note, which does not type" >&2; exit 1
fi
jq -e '.ok == true' >/dev/null 2>&1 <<<"$OUT" || { pp_wake_log cos-tell "$HANDLE" dictation refused "$(head -c 200 <<<"$OUT")"; echo "cos-tell: NOT sent: $(head -c 300 <<<"$OUT")" >&2; exit 1; }
pp_wake_log cos-tell "$HANDLE" dictation sent
echo "Sent to the Chief of Staff"
