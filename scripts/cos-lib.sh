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
# A find goes to its own <state>.<watcher>-wake-<time>-<pid>.txt. Up to 600 bytes print whole (the relay reads the last
# 600 characters of a watcher's output); a longer one prints one line (issue 229): what woke, the count, the file.
# shortcut: the wake files are never pruned; prune by age if the folder grows.
cos_wait() {
  local s=$1 n=${0##*/} f; shift
  n=${n%.sh}; echo $$ > "$COS_KEY.$n.pid"
  while :; do
    f=$COS_KEY.$n-wake-$(date +%s)-$$.txt
    if "$@" > "$f"; then
      if [ "$(wc -c < "$f")" -le 600 ]; then cat "$f"
      else echo "$n woke: $(grep -c . "$f") records, $(wc -c < "$f" | tr -d ' ') bytes; whole text: $f"; fi
      pp_wake_log "$n" chief-of-staff "$(grep -c . "$f") line(s)" woke
      exit 0
    fi
    rm -f "$f"
    [ -z "${COMMANDECK_WATCH_ONCE-}" ] || exit 1
    sleep "$s"
  done
}
