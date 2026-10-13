#!/usr/bin/env bash
# cos-lib.sh -- sourced by the Chief of Staff pane's watchers, never run.
# Their state lives under the plugin's own directory, one set of files per
# project, beside the saved state agent-startup-context.sh injects.
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
. "$PP_SCRIPTS/../hooks/lib/project.sh"; pp_project "$PP_MAIN"
COS_KEY=$HOME/.commandeck/chief-of-staff/$PP_PROJECT
mkdir -p "${COS_KEY%/*}"
COS_DATA=${COMMANDECK_DASHBOARD_DIR:-$HOME/.commandeck/dashboard}/data.js
# cos_wait <seconds> <command...>: poll until the command finds something, then
# exit 0, which wakes the pane. COMMANDECK_WATCH_ONCE=1 polls once (self-tests).
cos_wait() {
  local s=$1; shift
  while :; do
    "$@" && exit 0
    [ -z "${COMMANDECK_WATCH_ONCE-}" ] || exit 1
    sleep "$s"
  done
}
