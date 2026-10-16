#!/usr/bin/env bash
# cos-tell.sh <text...> | cos-tell.sh --handle | cos-tell.sh --note <subject> <body>
# Sends text (arguments or stdin) to the Chief of Staff pane, for a dictation
# shortcut or any script. --handle prints the pane's handle and sends nothing.
# The pane is found by its worktree, not a saved handle: handles change on restart.
# --note is main's note to the relay: sent to main's run (run:<id>), the durable
# mailbox the relay's inbox watcher reads. A pane handle is a live-only mailbox,
# and notes sent there while the pane was busy never reached it. Exits 1, saying
# so, unless Orca confirms a stored message.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
if [ "${1:-}" = --note ]; then
  [ $# = 3 ] || { echo "usage: cos-tell.sh --note <subject> <body>" >&2; exit 2; }
  RUN=$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE")
  [ -n "$RUN" ] || { echo "cos-tell: NOT sent: no run recorded in $PP_RUN_FILE, so the relay has no durable mailbox" >&2; exit 1; }
  SENT=$(date +%s)
  OUT=$(orca-ide orchestration send --run "$RUN" --to "run:$RUN" --type status --subject "$2" --body "$3" --json 2>&1)
  jq -e '.ok == true and ([.. | strings | select(test("^msg_"))] | length > 0) and (tostring | test("not durable") | not)' <<<"$OUT" >/dev/null 2>&1 \
    || { echo "cos-tell: NOT sent: Orca did not confirm a stored message to run:$RUN: $(head -c 300 <<<"$OUT")" >&2; exit 1; }
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
orca-ide terminal send --terminal "$HANDLE" --text "[dictated] $TEXT" --enter --json >/dev/null 2>&1 \
  && echo "Sent to the Chief of Staff" || { echo "Send failed" >&2; exit 1; }
