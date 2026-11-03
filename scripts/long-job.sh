#!/usr/bin/env bash
# long-job.sh start <name> [--repo <repo>] -- <command...> | run <name> [--max S=25] -- <command...> | wait <name> [max-seconds] | list | prune [--older-than <days>]
# -- main's long jobs (coverage runs, full suites, merges) in their own Orca terminal in the main checkout, so a
# restart of main's pane never kills one. bash-guardrails.sh blocks the direct forms
# in main's pane.
#   start  opens a `job:<name>` pane through open_pane; the pane runs `_run`, which holds <name>.lock with flock for
#          the job's whole life (the command inherits the descriptor, so the kernel frees it when the last process of
#          the job dies, KILL included), runs the command under hs_cage with output to <name>.log, writes <name>.rc
#          and exits, closing the pane. Refused while the job runs, while an unread <name>.rc is left, and from
#          any tree but the main checkout (a worktree uses the Bash tool's run_in_background); wait and list work anywhere.
#          --repo opens the pane in the checkout of the one repo Orca lists under that display name, for a job of
#          another repo (a Commandeck merge); the caller is still main's checkout, and the job's files stay in $JOBS.
#   run    start, then wait inline up to --max seconds (default 25): the result as
#          wait prints it and exit 0, or the still-running line and exit 3. A <name>.inline marker holds back the
#          done message while the waiter waits; the waiter removes it, then looks at <name>.rc once more, so a result
#          at the edge is printed twice at worst, never lost. A crash leaves the marker; the next run rewrites it.
#   wait   blocks until <name>.rc exists, at most max-seconds (default 240, or 540 on the 1-hour cache), with
#          wait-test-run.sh's exit contract: 0 done (prints rc=N and the log's last 20 lines; the job's own rc is in
#          the output), 3 still running at the limit, 1 died (lock free, no rc). Optional: a finished job (not a
#          seat-* one, which seat.sh collect reports) sends main a `question` with its rc and log tail, and an
#          accepted send marks the result read; a refused one leaves it unread for wait. Main runs wait only in the
#          background; a restart kills only this waiter, never the job.
#   list   one line per job: running, done rc=N (unread), done rc=N, read, read and cleared, or died.
#   prune  moves a job's .rc, .log and .read to a new $JOBS/archive/<name>-<mtime>.XXXXXX/ once main READ its
#          result more than <days> (default 1) ago, and frees its lock and pid files. Reading is printing the result: wait does, and so does start's
#          refusal over an unread rc (main then rm's the rc). An unread result, a running job and a job being started
#          are never touched, whatever their age. start runs the default prune first.
# Liveness is the lock, never Orca's pane list: open_pane's reuse check stops seeing a shell pane 120 s after launch.
# Files live in $PP_SCRATCH/long-jobs (COMMANDECK_SCRATCH overrides it).
# Self-test: bash scripts/run-shell-tests.sh scripts/__tests__/long-job.test.sh
set -uo pipefail
# A wait past the 5-minute prompt cache rewrites it: 240 s unless the cache is the 1-hour one, as wait-test-run.sh.
DEFAULT=240; [ "${CLAUDE_CODE_PROMPT_CACHE_TTL:-}" = 1h ] && DEFAULT=540
USAGE="usage: long-job.sh start <name> [--repo <repo>] -- <command...> | run <name> [--max S=25] -- <command...> | wait <name> [max-seconds, default $DEFAULT; optional] | list | prune [--older-than <days>]"
case ${1:-} in
  --help|-h) printf '%s\nexample: long-job.sh start suite -- npm run test:unit\n' "$USAGE"; exit 0 ;;
esac
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/codex-helpers.sh" || exit 1
. "$HERE/host-services.sh"
JOBS=$PP_SCRATCH/long-jobs
die() { echo "long-job: $1" >&2; exit "${2:-1}"; }
# .start is reserved: <name>.start.lock is <name>'s start lock, and list skips it.
name_ok() {
  [[ ${1-} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "a job name is letters, digits, . _ and - only: '${1-}'" 2
  [[ $1 != *.start ]] || die "a job name may not end .start (reserved for start locks): '$1'" 2
}
running() { ! flock -n "$JOBS/$1.lock" true 2>/dev/null; }
# Printing a result to main is the acknowledgment: <name>.read keeps its first-read time, and _run clears it for a rerun.
result() { echo "long-job: $1 done rc=$(cat "$JOBS/$1.rc"); last 20 lines of $JOBS/$1.log:"; tail -20 "$JOBS/$1.log" 2>/dev/null; [ -e "$JOBS/$1.read" ] || : > "$JOBS/$1.read"; }
prune_jobs() { # <days>
  local f N
  for f in $(find "$JOBS" -maxdepth 1 -name '*.read' -mmin "+$(($1 * 1440))" 2>/dev/null); do
    N=${f##*/}; N=${N%.read}
    ( flock -n 9 || exit 0
      running "$N" && exit 0
      m=$(stat -c %Y "$f") || exit 0
      # The record is copied into a directory no one else has (mktemp -d) before any live file goes, so nothing already
      # in archive/ can block a step and no rerun can rewrite an archived file. A failed step drops that directory and
      # leaves the whole live record where list, wait and start's refusal find it; the next prune retries on .read,
      # which goes last.
      mkdir -p "$JOBS/archive" && A=$(mktemp -d "$JOBS/archive/$N-$m.XXXXXX") || exit 0
      for e in rc log read; do [ ! -e "$JOBS/$N.$e" ] || cp "$JOBS/$N.$e" "$A/" || { pp_rm_rf "$A"; exit 0; }; done
      # <name>.start.lock stays: a starter waiting on its inode must meet the next starter on the same file.
      rm -f "$JOBS/$N.rc" "$JOBS/$N.log" "$JOBS/$N.lock" "$JOBS/$N.pid" "$JOBS/$N.inline" "$JOBS/$N.read" ) 9>>"$JOBS/$N.start.lock"
  done
}
command -v flock >/dev/null || die "flock is not installed; nothing started"
VERB=${1:-}; shift
case "$VERB" in
  start)
    N=${1-}; name_ok "$N"; shift
    unset REPO
    if [ "${1-}" = --repo ]; then [ $# -ge 2 ] || die "$USAGE" 2; REPO=$2; shift 2; fi
    [ "${1-}" = -- ] && shift
    [ $# -gt 0 ] || die "$USAGE" 2
    # The job's rc is the exit code of exactly what runs, so a command beside the suite (`; echo`, `& echo`,
    # `| tee`) would stand in for its result. Any word holding a separator, quoted or nested in shell text, is
    # refused; redirects (2>&1, >&2, &>) are not separators.
    for W in "$@"; do
      W=$(printf '%s' "$W" | sed -E 's/[0-9]*>&[0-9-]*|&>>?//g')
      [[ $W == *[\;\&\|$'\n']* ]] && die "run one command, the suite on its own: long-job.sh records the exit code of what it runs, so a command beside it would stand in for its result. Refused: $*" 2
    done
    # The pane opens in main's checkout whoever asks, so from a worktree the job would run main's code.
    [ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$PP_MAIN" && pwd -P)" ] \
      || die "start runs main's jobs in the main checkout; from a worktree run the command with the Bash tool's run_in_background instead" 2
    DIR=$PP_MAIN
    # The flag's presence decides, not its value: an empty name from an unset variable would run another repo's job here.
    if [ -n "${REPO+set}" ]; then
      [[ $REPO =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "a repo name is letters, digits, . _ and - only: '$REPO'" 2
      DIR=$(orca-ide repo list --json 2>/dev/null | jq -er --arg n "$REPO" '[.result.repos[] | select(.displayName == $n) | .path] | if length == 1 then .[0] else empty end' 2>/dev/null) \
        || die "Orca does not list exactly one repo named $REPO (orca-ide repo list --json); nothing started" 2
      # A path that no longer exists fails both sides; left to the comparison, the two empty answers would match.
      TOP=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) && [ "$TOP" = "$(cd "$DIR" && pwd -P)" ] \
        || die "Orca lists $REPO at $DIR, which is not the top of a checkout; nothing started" 2
    fi
    mkdir -p "$JOBS" || die "cannot make $JOBS"
    prune_jobs 1
    # One start of a name at a time, from the check until the runner holds the job's lock.
    exec {SL}>>"$JOBS/$N.start.lock"
    flock -w 60 "$SL" || die "another start of $N has held $JOBS/$N.start.lock for 60 s; nothing started"
    running "$N" && die "$N is running (pid $(cat "$JOBS/$N.pid" 2>/dev/null)); wait with: bash $HERE/long-job.sh wait $N"
    [ -f "$JOBS/$N.rc" ] && { result "$N"; die "$N has a result nobody cleared; read it above, then rm $JOBS/$N.rc to run it again"; }
    rm -f "$JOBS/$N.pid"
    # A merge run as a job starts a chain that wakes main's pane, but this job's own pane handle is not main's.
    CMD="COMMANDECK_SCRATCH=$(printf %q "$PP_SCRATCH") LONG_JOB_HANDLE=$(printf %q "${ORCA_TERMINAL_HANDLE-}") exec bash $(printf %q "$HERE/long-job.sh") _run $(printf %q "$N") --$(printf ' %q' "$@")"
    H=$(open_pane "path:$DIR" "job:$N" "$CMD" {SL}>&-); rc=$?
    [ "$rc" = 3 ] && die "a live pane titled job:$N already exists ($H); nothing started"
    [ "$rc" = 0 ] && [ -n "$H" ] || die "Orca did not open a terminal for $N; nothing started, nothing ran in this pane"
    for _ in $(seq 300); do [ -s "$JOBS/$N.pid" ] && break; sleep 0.1; done
    if [ ! -s "$JOBS/$N.pid" ]; then
      pp_pane_close "$H" "long-job: runner did not start" >/dev/null 2>&1 \
        && die "the runner in $H did not start $N within 30 s; that pane was closed"
      die "the runner in $H did not start $N within 30 s; closing that pane was refused too: $PP_CLOSE_RES"
    fi
    echo "long-job: $N running in $H; log $JOBS/$N.log; wait with: bash $HERE/long-job.sh wait $N"
    ;;
  _run)
    N=${1-}; name_ok "$N"; shift
    [ "${1-}" = -- ] && shift
    mkdir -p "$JOBS" || exit 1
    exec {L}>>"$JOBS/$N.lock"
    flock -n "$L" || { echo "long-job: $N is already running" >&2; exit 75; }
    rm -f "$JOBS/$N.rc" "$JOBS/$N.read"
    echo $$ > "$JOBS/$N.pid"
    if hs_cage 28G; then
      "${HS_CAGE[@]}" "$@" > "$JOBS/$N.log" 2>&1; rc=$?
    else
      echo "long-job: no memory cage on this host (systemd-run missing); $N did not run" > "$JOBS/$N.log"; rc=2
    fi
    echo "$rc" > "$JOBS/$N.rc.tmp" && mv "$JOBS/$N.rc.tmp" "$JOBS/$N.rc"
    # Main is told it finished. A question, because orca-wait.sh hides `status`. A seat job is reported by
    # seat.sh collect. The result counts as read once to-main.sh sent or queued the message (exit 0 or 3); a refused
    # one (1) stays unread for wait.
    if [[ $N != seat-* && ! -e "$JOBS/$N.inline" ]]; then
      MSG="$JOBS/$N.log
$(tail -20 "$JOBS/$N.log" 2>/dev/null)"
      timeout 60 bash "$HERE/to-main.sh" question "long-job $N done rc=$rc" "$MSG" >/dev/null 2>&1; case $? in
        0|3) : > "$JOBS/$N.read" ;;
        *) echo "long-job: the done message to main was refused; the result stays unread for wait" >> "$JOBS/$N.log" ;;
      esac
    fi
    ;;
  run)
    N=${1-}; name_ok "$N"; shift
    MAX=25
    [ "${1-}" = --max ] && { MAX=${2-}; [[ $MAX =~ ^[0-9]+$ ]] || die "$USAGE" 2; shift 2; }
    [ "${1-}" = -- ] && shift
    [ $# -gt 0 ] || die "$USAGE" 2
    # start's own refusals and start itself; its done message is held back while this waiter is still waiting.
    mkdir -p "$JOBS" || die "cannot make $JOBS"
    : > "$JOBS/$N.inline"
    S=$(bash "$HERE/long-job.sh" start "$N" -- "$@" 2>&1); rc=$?
    [ "$rc" = 0 ] || { rm -f "$JOBS/$N.inline"; printf '%s\n' "$S"; exit "$rc"; }
    END=$((SECONDS + MAX))
    while [ ! -f "$JOBS/$N.rc" ] && running "$N" && [ "$SECONDS" -lt "$END" ]; do sleep 1; done
    rm -f "$JOBS/$N.inline"
    # The job can end between the last look and the marker's removal with its done message held back: look once more.
    [ -f "$JOBS/$N.rc" ] && { result "$N"; exit 0; }
    if running "$N"; then echo "long-job: $N still running after ${MAX}s; wait with: bash $HERE/long-job.sh wait $N"; exit 3; fi
    echo "long-job: $N died: its lock is free and it wrote no rc; last 20 lines of $JOBS/$N.log:"
    tail -20 "$JOBS/$N.log" 2>/dev/null
    exit 1
    ;;
  wait)
    N=${1-}; name_ok "$N"
    MAX=${2:-$DEFAULT};[[ $MAX =~ ^[0-9]+$ ]] || die "$USAGE" 2
    [ -e "$JOBS/$N.lock" ] || die "no job named $N in $JOBS" 2
    END=$((SECONDS + MAX))
    while :; do
      [ -f "$JOBS/$N.rc" ] && { result "$N"; exit 0; }
      # A runner can write its rc and exit between the two reads; the lock is free only after the rc is in place.
      if ! running "$N"; then
        [ -f "$JOBS/$N.rc" ] && { result "$N"; exit 0; }
        echo "long-job: $N died: its lock is free and it wrote no rc; last 20 lines of $JOBS/$N.log:"
        tail -20 "$JOBS/$N.log" 2>/dev/null
        exit 1
      fi
      [ "$SECONDS" -lt "$END" ] || { echo "long-job: $N still running after ${MAX}s; wait again"; exit 3; }
      sleep 1
    done
    ;;
  list)
    for f in "$JOBS"/*.lock; do
      [ -e "$f" ] || continue
      N=${f##*/}; N=${N%.lock}
      case "$N" in *.start) continue ;; esac
      if [ -f "$JOBS/$N.rc" ]; then echo "$N: done rc=$(cat "$JOBS/$N.rc")$([ ! -e "$JOBS/$N.read" ] || echo ', read')"
      elif [ -e "$JOBS/$N.read" ] && ! running "$N"; then echo "$N: read and cleared"
      elif running "$N"; then echo "$N: running (pid $(cat "$JOBS/$N.pid" 2>/dev/null)), log $JOBS/$N.log"
      else echo "$N: died, no rc; log $JOBS/$N.log"; fi
    done
    ;;
  prune)
    D=1
    case "${1-}" in
      --older-than) D=${2-}; [[ $D =~ ^[0-9]+$ ]] || die "$USAGE" 2 ;;
      "") ;;
      *) die "$USAGE" 2 ;;
    esac
    prune_jobs "$D"
    ;;
  *) die "$USAGE" 2 ;;
esac
