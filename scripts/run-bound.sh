#!/usr/bin/env bash
# Bind this terminal to the Orca run before any task-create or dispatch.
# The binding belongs to the TERMINAL handle, and main's handle changes on
# every /clear: a driver launched from the old pane then gets "No Run is
# bound" (task=null, orphan pane, no handles) at its next dispatch. A dead
# handle can still rebind, so rebind on every call unless another live pane
# coordinates the run (then act as that pane, below).
# The run id is COMMANDECK_RUN, pinned by loop-run.sh at launch so a driver
# stays on its own run after main switches to another; then the project's
# run file (board.sh writes it); run-current is the last fallback.
#
# Prints the handle the caller must act as; every caller exports it as
# ORCA_TERMINAL_HANDLE. A DEAD PANE NEVER TAKES THE RUN. Binding a closed
# pane's handle moved the run away from main's live pane and left main's inbox
# waiter fenced for 12 minutes on 2026-09-19. A shell whose pane is
# gone acts as the run's live coordinator instead: that is exactly the handle a
# driver launched from main's live pane carries, and it moves no binding.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
RUN=${COMMANDECK_RUN:-}
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 2
[ -n "$RUN" ] || RUN=$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE" || true)
[ -n "$RUN" ] || RUN=$(orca-ide orchestration run-current --json 2>/dev/null | jq -r '.result.run.id // empty')
[ -n "$RUN" ] || { echo "NO RUN BOUND: orca-ide orchestration run-use --id <run_id> before launching (run-list shows the ids)" >&2; exit 2; }
ME=${ORCA_TERMINAL_HANDLE:-}
# Closed only on Orca's own answer, the one its CLI uses for the same question:
# an Orca that cannot answer is not proof the pane is gone.
closed() {
  orca-ide terminal show --terminal "$1" --json 2>/dev/null \
    | jq -e '.ok == false and (.error.code | IN("terminal_handle_stale", "terminal_gone", "terminal_not_found"))' >/dev/null 2>&1
}
COORD=$(orca-ide orchestration run-list --json 2>/dev/null \
  | jq -r --arg r "$RUN" '.result.runs[]? | select(.id == $r) | .coordinator_handle // empty' 2>/dev/null)
# AN OPEN PANE NEVER TAKES THE RUN FROM A LIVE COORDINATOR either: after
# a context-clear restart the old main pane stayed open, its drivers ran run-use
# as the old handle on every seat launch, and the new main's inbox was fenced.
if [ -n "$COORD" ] && [ "$COORD" != "$ME" ] && ! closed "$COORD"; then echo "$COORD"; exit 0; fi
if [ -n "$ME" ] && closed "$ME"; then
  echo "NO RUN BOUND: pane $ME is closed and run $RUN has no live coordinator to act as; main runs run-use --id $RUN, then relaunch" >&2
  exit 2
fi
orca-ide orchestration run-use --id "$RUN" --json 2>/dev/null | jq -e '.ok' >/dev/null \
  || { echo "NO RUN BOUND: run-use --id $RUN failed for terminal ${ME:-unset}" >&2; exit 2; }
echo "$ME"
