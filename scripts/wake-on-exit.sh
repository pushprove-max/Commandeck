#!/usr/bin/env bash
# wake-on-exit.sh [--print] [--cage <size>] <label> -- <command>...
#   -- run ANY long command as its own transient systemd user unit (a launchd
#      job on the Mac, see host-services.sh) and wake main
#      through the Orca inbox when it exits. Returns at once with the unit name
#      and the log path; it never blocks main.
#
# WHY. A long job -- a deploy watch, a long AWS script, a replay --
# had no sanctioned launcher and main hand-rolled one. On 2026-09-20 the
# hand-rolled shape was `tail -n 0 -f <log> | grep -q -m1 PATTERN` as a
# background Bash call. That pipeline CANNOT EXIT: grep leaves at the match, but
# tail -f never writes again so it never takes SIGPIPE, and bash waits for every
# pipeline member. The harness therefore never notified main, and the real tail
# sat alive for four hours while the chain it watched had passed 40 minutes in.
#
# A transient unit (never setsid or
# nohup) so it survives main's /clear, PATH and HOME forwarded because the unit
# starts from a bare environment, and the wake written to its own log because
# the run log has closed by the time it fires.
#
# NO run-use HERE. The wake goes through to-main.sh, which looks main's pane up at send time.
set -euo pipefail

usage() { cat <<'EOF'
usage: wake-on-exit.sh [--print] [--cage <size>] [--max <seconds>] (--ci <sha> [--event <name>] | <label> -- <command>...)
Run any long command as its own systemd user unit; wake main through the Orca inbox when it exits.
  --print          print the systemd-run command and exit; start nothing
  --cage <size>    MemoryMax for the unit (default 28G, the chain's box)
  --max <seconds>  lifetime cap for the command (default 14400, 4 h): past it the command is killed and the wake
                   reads FAILED exit 124. A longer watch passes a larger --max
  --ci <sha>       watch every GitHub Actions run of that commit as label ci-<sha12>; a failed run that is not a
                   deploy workflow gets ONE rerun of its failed jobs, a deploy-* run is only watched; no run for
                   the commit reads OK as "no CI started", a gh run list that keeps failing reads FAILED
  --event <name>   with --ci: list only runs of that GitHub event (workflow_dispatch for a deploy started by hand)
                   and wait up to WAKE_CI_WAIT_S for one even where no workflow starts on a push
  --ci-run <sha>   the --ci watch body, run inside the unit; never by hand
  <label>          names the unit, the log and the wake subject; [A-Za-z0-9._-]
  <command>...     everything after -- is run as given, argument by argument
example: scripts/wake-on-exit.sh deploy-watch -- gh run watch 1234567890
EOF
}
case "${1:-}" in --help|-h) usage; exit 0 ;; esac

# The body of --ci, run inside the unit. Both deploy workflows start by workflow_dispatch alone, so rerunning a CI run
# cannot start a deploy; a run whose workflow file is unreadable or named deploy-* is only watched all the same.
# shortcut: a rerun is watched after one WAKE_CI_POLL_S pause, so a watch that races the rerun's start reads the old
# attempt as red; poll for the new attempt's status if that shows up.
if [ "${1:-}" = --ci-run ]; then
  sha=${2:?--ci-run needs a sha} poll=${WAKE_CI_POLL_S:-30} wait=${WAKE_CI_WAIT_S:-600} red=0 waited=0 ids= seen=' ' due=0 event=
  if [ "${3:-}" = --event ]; then event=${4:?--event needs an event name}; fi
  # No run for the commit is "no CI started", never FAILED; a gh error is FAILED.
  # A run is due when a workflow at the commit has a push trigger (0, or 128 when the commit cannot be read): then
  # the watch waits up to WAKE_CI_WAIT_S for one. 1: both deploys here start by hand, so it need not wait.
  # shortcut: a line match on the workflow files, not a YAML parse; parse them if a trigger shape slips past it.
  git grep -qE -e '^[[:space:]]+push:' -e '^[[:space:]]+-[[:space:]]*push[[:space:]]*$' -e '^"?on"?:.*[^a-z_]push([^a-z_]|$)' \
    "$sha" -- .github/workflows 2>/dev/null || due=$?
  # --event names a run main started by hand: one is due whatever the push triggers say.
  [ -z "$event" ] || due=0
  # Only a listing that worked and came back empty proves no run: a failed one may be hiding a red run.
  until listed=0; ids=$(gh run list --commit "$sha" ${event:+--event "$event"} --json databaseId --jq '.[].databaseId') && listed=1 && [ -n "$ids" ]; do
    if [ "$listed" = 1 ] && { [ "$due" = 1 ] || [ "$waited" -ge "$wait" ]; }; then
      echo "no CI started for $sha$([ "$due" != 1 ] || echo ": no workflow at that commit starts on a push; to watch a deploy started by hand: wake-on-exit.sh --ci ${sha:0:12} --event workflow_dispatch")"; exit 0
    fi
    [ "$waited" -lt "$wait" ] || { echo "FAILED: the runs of $sha could not be listed in ${wait}s, so a run may be unwatched"; exit 1; }
    sleep "$poll"; waited=$((waited + poll + 1))
  done
  # A run can start after the first listing, so the list is read again after each sweep until it names no new run.
  while :; do
    new=; for id in $ids; do [[ $seen == *" $id "* ]] || new+=" $id"; done
    [ -n "$new" ] || break
    for id in $new; do
      seen+="$id "
      path=$(gh api "repos/:owner/:repo/actions/runs/$id" --jq .path 2>/dev/null) || path=
      name=${path##*/}; [ -n "$name" ] || name="run $id"
      if gh run watch "$id" --exit-status >/dev/null 2>&1; then echo "$name: green"; continue; fi
      jobs=$(gh run view "$id" --json jobs --jq '[.jobs[] | select(.conclusion == "failure") | .name] | join(", ")' 2>/dev/null) || jobs=
      case $path in
        ""|.github/workflows/deploy-*) red=1; echo "$name: failed ${jobs:-?}; watched, never rerun"; continue ;;
      esac
      gh run rerun "$id" --failed >/dev/null 2>&1 || { red=1; echo "$name: failed ${jobs:-?}; the rerun could not start"; continue; }
      sleep "$poll"
      if gh run watch "$id" --exit-status >/dev/null 2>&1; then echo "$name: failed ${jobs:-?}, rerun green"
      else red=1; echo "$name: failed ${jobs:-?}, rerun red"; fi
    done
    ids=$(gh run list --commit "$sha" ${event:+--event "$event"} --json databaseId --jq '.[].databaseId') \
      || { red=1; echo "the runs of $sha could not be listed again, so a later run may be unwatched"; break; }
  done
  exit "$red"
fi

PRINT= CAGE=28G MAX=14400
while [ $# -gt 0 ]; do
  case "$1" in
    --print) PRINT=1; shift ;;
    --cage) CAGE=${2:?--cage needs a size}; shift 2 ;;
    --max) [[ ${2:-} =~ ^[1-9][0-9]*$ ]] || { echo "wake-on-exit: --max needs a number of seconds" >&2; exit 2; }
           MAX=$2; shift 2 ;;
    --ci) [[ ${2:-} =~ ^[0-9a-f]{7,40}$ ]] || { echo "wake-on-exit: --ci needs a commit sha" >&2; exit 2; }
          ev=()
          if [ "${3:-}" = --event ]; then
            [[ ${4:-} =~ ^[A-Za-z0-9_-]+$ ]] || { echo "wake-on-exit: --event needs a GitHub event name (workflow_dispatch)" >&2; exit 2; }
            ev=(--event "$4")
          fi
          set -- "ci-${2:0:12}" -- bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wake-on-exit.sh" --ci-run "$2" ${ev[@]+"${ev[@]}"}; break ;;
    *) break ;;
  esac
done
LABEL=${1:-}
[[ "$LABEL" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "wake-on-exit: missing or invalid <label>: '${LABEL}'" >&2; usage >&2; exit 2; }
shift
[ "${1:-}" = -- ] || { echo "wake-on-exit: the command must follow --" >&2; usage >&2; exit 2; }
shift
[ $# -gt 0 ] || { echo "wake-on-exit: no command after --" >&2; usage >&2; exit 2; }

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
. "$(dirname "${BASH_SOURCE[0]}")/host-services.sh"
SCRATCH=$PP_SCRATCH
MAIN=${ORCA_TERMINAL_HANDLE:?ORCA_TERMINAL_HANDLE, the main pane, is not set}

# A handle from before an Orca restart names a dead pane, and Orca then answers
# no_active_sender_terminal on the wake -- the silence this script exists to
# stop. Same check chain-run.sh and loop-run.sh make, for the same reason.
if [ -z "$PRINT" ]; then
  orca-ide terminal list --json 2>/dev/null \
    | jq -e --arg h "$MAIN" '(.result.terminals // [])[] | select(.handle == $h)' >/dev/null \
    || { echo "ORCA_TERMINAL_HANDLE $MAIN is not a live Orca pane (Orca restarted?). Relaunch from a pane 'orca-ide terminal list' shows." >&2; exit 2; }
fi

# The unit starts from a bare environment, so a binary missing from the PATH
# forwarded below costs the whole run. orca-ide sends the wake; jq feeds the
# liveness check above.
missing=()
for bin in orca-ide jq timeout; do command -v "$bin" >/dev/null || missing+=("$bin"); done
[ ${#missing[@]} -eq 0 ] || {
  printf 'PREFLIGHT FAIL: not on the PATH this unit will inherit: %s\n' "${missing[*]}" >&2
  echo "PATH=$PATH" >&2; exit 2; }

# The pid joins the second: two launches with the same label inside one second
# would otherwise take the same unit name, and the second would both be refused
# and overwrite the first one's command file.
STAMP=$(date +%s)-$$
NAME=wake-$LABEL-$STAMP
LOG=$SCRATCH/scratchpad/$NAME.log
SENDLOG=$SCRATCH/scratchpad/$NAME.send.log
CMD=$SCRATCH/scratchpad/$NAME.cmd.sh
mkdir -p "$(dirname "$LOG")"
# The unit writes its log here and cannot report a failure to create it, because
# the report goes through the same file.
: > "$LOG" 2>/dev/null || { echo "PREFLIGHT FAIL: cannot write $LOG" >&2; exit 2; }

# The inner command goes in a file rather than a -c string: the caller's command
# may carry quotes and the wake body carries a command substitution, and nesting
# those through systemd-run's quoting is how the hand-written versions kept
# going wrong. Every word is %q-quoted, so the command runs exactly as given.
# A push-*, ci-* or deploy job also sends the relay one event line from its exit status; a failed send is
# swallowed by pp_relay_event, so the job's exit code is the command's. main pushes as `push-<sha12> -- git push ...`.
RELAY= EV=
case $LABEL in
  push-*) EV=push DETAIL=${LABEL#push-} ;;
  ci-*) EV=ci DETAIL=${LABEL#ci-} ;;
  *deploy*) EV=deploy DETAIL=$LABEL ;;
esac
[ -z "$EV" ] || RELAY="( . $(printf '%q' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths.sh") && pp_relay_event $(printf '%q' "${PP_MAIN##*/}") $EV \$([ \$STATUS -eq 0 ] && echo ok || echo fail) \"$DETAIL exit \$STATUS\" ) || true"
cat > "$CMD" <<EOF
set -o pipefail
cd $(printf '%q' "$ROOT")
START=\$SECONDS
timeout --kill-after=30 $MAX $(printf '%q ' "$@")> $(printf '%q' "$LOG") 2>&1
STATUS=\$?
# 137 is a command that ignored the cap's TERM and took timeout's KILL; a KILL before the cap is not the cap.
if [ \$STATUS -eq 124 ] || { [ \$STATUS -eq 137 ] && [ \$((SECONDS - START)) -ge $MAX ]; }; then
  echo "wake-on-exit: ended by the $MAX s lifetime cap (--max)" >> $(printf '%q' "$LOG")
fi
# EXACTLY ONE wake, and it gets its OWN log: the main redirect has closed by
# now, so a send that fails here leaves no trace anywhere else and main waits on
# a silent inbox.
{
  # The exit line comes first, for a person reading the send log; no script reads it.
  echo "exit=\$STATUS"
  command -v orca-ide || echo "orca-ide NOT ON PATH -- no wake will be sent"
  # The same label and exit within the hour is sent once (the host's rule, copied as is): a repeat is taken for a loop
  # re-running the job, and nothing else re-sends the held-back wake. The stamp is written only after a send exits 0 or 3.
  LAST=$(printf '%q' "$SCRATCH/scratchpad/wake-last-$LABEL")-\$STATUS
  SENT=\$(cat "\$LAST" 2>/dev/null)
  if [ "\${SENT:-0}" -gt \$((\$(date +%s) - 3600)) ] 2>/dev/null; then
    echo "deduped: same result sent at \$SENT"
  else
    # to-main.sh exits 0 posted, 3 queued (both count as sent), else the send was refused.
    R=\$(bash $(printf '%q' "$HERE/to-main.sh") question \\
      "$LABEL: \$([ \$STATUS -eq 0 ] && echo OK || echo FAILED) exit \$STATUS" \\
      "$LABEL exited \$STATUS; log $LOG
\$(tail -5 $(printf '%q' "$LOG") | cut -c1-200)" 2>&1); RC=\$?
    case \$RC in 0) WL=posted ;; 3) WL=queued ;; *) WL=refused ;; esac
    case \$RC in 0|3) date +%s > "\$LAST" ;; esac
    echo "\$R"
    ( . $(printf '%q' "$HERE/paths.sh") && pp_wake_log wake-on-exit main $(printf '%q' "$LABEL") "\$WL" "\$([ "\$WL" = posted ] || echo "\${R:0:200}")" )
  fi
  $RELAY
} >$(printf '%q' "$SENDLOG") 2>&1
exit \$STATUS
EOF

envs=(HOME="$HOME" PATH="$PATH")
# ORCA_TERMINAL_HANDLE rides in here: it is what makes the wake deliverable. The paths.sh overrides ride with it, or
# the job reads the default folders, not the configured ones its caller resolved (main-watch's auto-merge).
while IFS='=' read -r k v; do envs+=("$k=$v"); done < <(env | grep -E '^(ORCA_|CODEX_HOME=|COMMANDECK_(MAIN|WORKSPACES|SCRATCH)=)')

if [ -n "$PRINT" ]; then
  HS_PRINT=1 hs_start "$NAME" "$CAGE" "${envs[@]}" -- bash "$CMD"
  printf 'cmd=%s\n' "$CMD"
  exit 0
fi

# A launcher that refuses is the same silence one step earlier, so say so: the
# job never started and nothing at all will wake main for it.
hs_start "$NAME" "$CAGE" "${envs[@]}" -- bash "$CMD" \
  || { echo "wake-on-exit: could not start $NAME; NOTHING will wake main for: $LABEL" >&2; exit 1; }
echo "unit=$NAME.service log=$LOG send=$SENDLOG"
echo "result: tail -3 $LOG; $(hs_log_hint "$NAME")"
