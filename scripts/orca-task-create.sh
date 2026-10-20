#!/usr/bin/env bash
# orca-task-create.sh <orca-ide orchestration task-create args, without --json>
# Prints only the new task id. The one task-create path: every site used to
# parse the id itself and drop Orca's reason, so two loops died on 2026-09-24
# with "no task id" and nothing to act on. task-create sometimes answers with
# no id (seat.sh, 2026-09-12), so a miss is retried once; a second miss prints
# Orca's .error.message (or the raw reply) to stderr and exits 1.
#
# THE SENDER IS RE-READ BEFORE EACH ATTEMPT. A driver launched before a main
# /clear still carries the old pane's handle, and Orca refused its create with
# "no longer bound to Run" (2026-09-30). run-bound.sh names the run's live
# coordinator without moving the run; an explicit --run pins which run, and a
# caller's --from is replaced by that handle, never doubled.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
args=("$@") run=""
for ((i = 0; i < ${#args[@]}; i++)); do [ "${args[i]}" != --run ] || run=${args[i+1]:-}; done
refresh_sender() {
  local h
  # A process with no terminal of its own (main-watch.sh, which resolves the
  # coordinator itself and passes --from) has nothing to refresh, and must
  # never run-use: that fences main's inbox.
  [ -n "${ORCA_TERMINAL_HANDLE:-}" ] || return 0
  h=$(COMMANDECK_RUN=${run:-${COMMANDECK_RUN:-}} "$(dirname "$0")/run-bound.sh" 2>/dev/null) && [ -n "$h" ] || return 0
  export ORCA_TERMINAL_HANDLE=$h
  for ((i = 0; i < ${#args[@]}; i++)); do [ "${args[i]}" != --from ] || args[i+1]=$h; done
}
for attempt in 1 2; do
  refresh_sender
  reply=$(orca-ide orchestration task-create "${args[@]}" --json)
  # The reply's top-level id is the request's; the task id is the task_ one.
  id=$(jq -r 'first(.. | objects | .id? | strings | select(startswith("task_"))) // empty' <<<"$reply" 2>/dev/null)
  [ -z "$id" ] || { echo "$id"; exit 0; }
done
echo "task-create failed after $attempt attempts: $(jq -r '.error.message // .' <<<"$reply" 2>/dev/null || echo "$reply")" >&2
exit 1
