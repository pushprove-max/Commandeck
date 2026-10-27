#!/usr/bin/env bash
# usage: bgrun.sh [--max S=25] [--lines N=20] -- <command...> | bgrun.sh wait <log> [--max S] [--lines N=20]
# -- a worker's slow command as a plain child, with the command's own exit code and output coming back. Done within
# S: prints rc=<n> and the last N lines, exits with the command's code. Else exit 3 and the line to wait with.
# wait is the reader wait-test-run.sh cannot be: that one returns 0 only on a test-summary footer and never the
# command's code. Exit 3 means still running (a command that itself exits 3 is read from the rc= line);
# exit 1: no such log, or the job died without writing an exit code (its whole process group gone, not just the wrapper).
# Files: $PP_SCRATCH/bgrun/<epoch>-<pid>.log, .pid and .rc (each written to .tmp, then mv, so a reader never sees half of one).
# .pid holds the job's process group id, not one process: the command outlives a killed wrapper, and a retry on "died" would repeat its side effects.
# Self-test: bash scripts/__tests__/bgrun.test.sh
set -uo pipefail
# A wait past the 5-minute prompt cache rewrites it: the limit wait-test-run.sh uses (270 s; 540 s on the 1-hour cache).
DEFAULT=270; [ "${CLAUDE_CODE_PROMPT_CACHE_TTL:-}" = 1h ] && DEFAULT=540
USAGE="usage: bgrun.sh [--max S=25] [--lines N=20] -- <command...> | bgrun.sh wait <log> [--max S, default $DEFAULT] [--lines N=20]"
case ${1:-} in
  --help|-h) printf '%s\nexample: bgrun.sh --max 25 -- npm run build\n' "$USAGE"; exit 0 ;;
esac
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh" || exit 1
D=$PP_SCRATCH/bgrun
die() { echo "bgrun: $1" >&2; exit "${2:-1}"; }
num() { [[ ${1-} =~ ^[0-9]+$ ]] || die "$USAGE" 2; }

# <log> <seconds> <lines>: returns only when the command ended (the command's code is the exit) or the limit passed.
await() {
  local log=$1 end=$((SECONDS + $2)) pid
  pid=$(cat "$log.pid" 2>/dev/null)
  while [ ! -f "$log.rc" ]; do
    # The child can write its rc and exit between the two reads; the rc is in place before it exits.
    # .pid names the job's process group: the command outlives a killed wrapper, and only the group says it is gone.
    # An empty pid names no job; `kill -0 -- -` would test group 0, this script's own, and read it alive.
    if [ -z "$pid" ] || ! kill -0 -- -"$pid" 2>/dev/null; then
      [ -f "$log.rc" ] && break
      echo "bgrun: died with no exit code; last $3 lines of $log:"; tail -n "$3" "$log" 2>/dev/null; exit 1
    fi
    [ "$SECONDS" -lt "$end" ] || { echo "bgrun: still running pid=$pid log=$log; wait with: bash $HERE/bgrun.sh wait $log"; exit 3; }
    sleep 0.2
  done
  echo "rc=$(cat "$log.rc")"; tail -n "$3" "$log" 2>/dev/null
  exit "$(cat "$log.rc")"
}

if [ "${1:-}" = wait ]; then
  LOG=${2:-}; [ -n "$LOG" ] || die "$USAGE" 2; shift 2
  MAX=$DEFAULT LINES=20
  while [ $# -gt 0 ]; do
    case $1 in
      --max) num "${2-}"; MAX=$2; shift ;;
      --lines) num "${2-}"; LINES=$2; shift ;;
      *) die "$USAGE" 2 ;;
    esac
    shift
  done
  [ -e "$LOG.pid" ] || [ -f "$LOG.rc" ] || die "no such bgrun log: $LOG"
  await "$LOG" "$MAX" "$LINES"
fi

MAX=25 LINES=20
while [ $# -gt 0 ]; do
  case $1 in
    --max) num "${2-}"; MAX=$2; shift ;;
    --lines) num "${2-}"; LINES=$2; shift ;;
    --) shift; break ;;
    *) die "$USAGE" 2 ;;
  esac
  shift
done
[ $# -gt 0 ] || die "$USAGE" 2
mkdir -p "$D" || die "cannot make $D"
LOG=$D/$(date +%s)-$$.log
# HUP ignored: the child outlives the Bash call that started it.
# set -m makes the wrapper its own process group (id = its pid, inherited by the command): .pid names that group.
set -m
( trap '' HUP; "$@" > "$LOG" 2>&1 </dev/null; rc=$?; echo "$rc" > "$LOG.rc.tmp" && mv "$LOG.rc.tmp" "$LOG.rc" ) >/dev/null 2>&1 &
set +m
echo $! > "$LOG.pid.tmp" && mv "$LOG.pid.tmp" "$LOG.pid" || die "cannot record the job's pid in $LOG.pid"
await "$LOG" "$MAX" "$LINES"
