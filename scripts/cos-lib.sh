#!/usr/bin/env bash
# cos-lib.sh -- sourced by the Chief of Staff pane's watchers, never run.
# Their state lives under the plugin's own directory, one set of files per
# project, beside the saved state agent-startup-context.sh injects.
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
. "$PP_SCRIPTS/../hooks/lib/project.sh"; pp_cos_key "$PP_MAIN"
mkdir -p "${COS_KEY%/*}"
COS_DATA=${COMMANDECK_DASHBOARD_DIR:-$HOME/.commandeck/dashboard}/data.js
# cos_wait <seconds> <command...>: poll until the command finds something, then
# exit 0, which wakes the pane. COMMANDECK_WATCH_ONCE=1 polls once (self-tests).
# Its pid goes to <state>.<watcher>.pid: the pane's Stop hook
# (cos-inbox-waiter-stop.sh) reads it to tell this project's watcher from another's.
cos_wait() {
  local s=$1 n=${0##*/}; shift
  echo $$ > "$COS_KEY.${n%.sh}.pid"
  while :; do
    "$@" && exit 0
    [ -z "${COMMANDECK_WATCH_ONCE-}" ] || exit 1
    sleep "$s"
  done
}
