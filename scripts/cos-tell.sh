#!/usr/bin/env bash
# cos-tell.sh <text...> | cos-tell.sh --handle
# Sends text (arguments or stdin) to the Chief of Staff pane, for a dictation
# shortcut or any script. --handle prints the pane's handle and sends nothing.
# The pane is found by its worktree, not a saved handle: handles change on restart.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
HANDLE=$(pp_pane_of "$PP_WORKSPACES/Chief-of-Staff")
[ -n "$HANDLE" ] || { echo "Chief of Staff pane not found (no claude pane in $PP_WORKSPACES/Chief-of-Staff)" >&2; exit 1; }
[ "${1:-}" != --handle ] || { echo "$HANDLE"; exit 0; }
TEXT=${*:-$(cat)}
[ -n "$TEXT" ] || { echo "nothing to send" >&2; exit 1; }
orca-ide terminal send --terminal "$HANDLE" --text "[dictated] $TEXT" --enter --json >/dev/null 2>&1 \
  && echo "Sent to the Chief of Staff" || { echo "Send failed" >&2; exit 1; }
