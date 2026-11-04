#!/usr/bin/env bash
# Emit an event whenever a dispatched agent changes state, and a heartbeat at
# least every 10 minutes so a quiet board is still confirmed rather than assumed.
#
# Silence is not success (Monitor's coverage rule): this reports every terminal
# state, not just the good ones -- a verdict either way, a worker going idle, a
# pane vanishing mid-run, and the poll itself failing. If the whole board goes
# empty while work was expected, that is an event, not quiet.
#
# It runs with --no-drain on purpose. Acking the message queue here would consume
# a worker's report before the interactive poll could ever show it.
#
# Usage: watch-agents.sh [poll_seconds] [heartbeat_seconds]

set -uo pipefail
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "${0}"; exit 0 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 2

POLL=${1:-60}
HEARTBEAT=${2:-600}
POLLER="$HERE/poll-agents.sh"
. "$HERE/paths.sh" || exit 2

shown=""
prev=""
pending=""
last_beat=0
fails=0

while true; do
  now=$(date +%s)

  # A BLOCKED worker is worse than an idle one: it waits on an answer, the ask
  # times out, and the work silently proceeds on a default. That cost a real
  # escalation once -- a worker asking whether to touch an out-of-scope file
  # went unanswered because nothing surfaced questions. Emit those loudly and
  # immediately, before anything else this cycle.
  # Issue 642: what wakes main is the one wake rule's (pp_inbox_actionable: now,
  # or a batch that is due), read off the inbox page, which marks nothing read:
  # the consuming check here took main's mail from its drain. Each row is shown
  # once per id. Heartbeats are not acked here: the nudge hook holds those
  # nudges (cos-own-echo.sh). A failed or junk read is no news.
  acts=$(pp_inbox_actionable "$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE")" "${ORCA_TERMINAL_HANDLE:-}" 2>/dev/null) || acts='[]'
  while IFS= read -r m; do
    id=$(jq -r '.id // empty' <<<"$m")
    [ -n "$id" ] && ! grep -qxF "$id" <<<"$shown" || continue
    shown+="$id"$'\n'
    jq -r '"ANSWER NEEDED [\(.type // "")] \(.subject // "")", ((.body // "" | gsub("^\\s+|\\s+$"; "")) as $b
      | if $b == "" then empty else "  " + ($b[0:900] | gsub("\n"; "\n  ")) end)' <<<"$m"
  done < <(jq -c 'if type == "array" then .[] else empty end' <<<"$acts" 2>/dev/null)

  cur=$(bash "$POLLER" --signature 2>/dev/null)
  rc=$?

  if [ $rc -ne 0 ]; then
    # Don't die on one bad call, but don't hide a persistent outage either.
    fails=$((fails + 1))
    if [ $fails -ge 3 ]; then
      echo "POLL FAILING: $POLLER exited $rc three times running -- agent state is UNKNOWN"
      fails=0
      last_beat=$now
    fi
    sleep "$POLL"
    continue
  fi
  fails=0

  # Debounce: a Claude pane shows no "working" marker in the gap BETWEEN tool
  # calls, so a single reading catches healthy agents mid-blink and flaps
  # idle -> working -> idle. Require the same reading twice before believing it.
  # A real transition is simply reported one cycle later; a blink never is.
  if [ "$cur" != "$prev" ] && [ "$cur" != "$pending" ]; then
    pending="$cur"
    sleep "$POLL"
    continue
  fi

  if [ "$cur" != "$prev" ]; then
    # Report what actually changed, so a notification is readable on its own.
    # Ignore a title-only change: Claude renames its own pane when it picks up a
    # task, and reporting that as an event is noise.
    while IFS='|' read -r h wt title model state verdict; do
      [ -z "${h:-}" ] && continue
      grep -qxF "$h|$wt|$model|$state|$verdict" <<<"$(cut -d'|' -f1,2,4,5,6 <<<"$prev")" && continue
      case "$state" in
        DONE)  echo "DONE  $wt / $model${verdict:+  VERDICT: $verdict}" ;;
        working|booting) echo "start $wt / $model  ($state)" ;;
        *)     echo "idle  $wt / $model  ($state)" ;;
      esac
    done <<< "$cur"

    # A pane that disappeared is a failure signal, not an absence of one. Key
    # this on the HANDLE only -- it is the sole stable identity. Keying it on the
    # title made a rename look like one pane vanishing and another appearing,
    # which raised a false GONE on a perfectly healthy agent.
    while IFS='|' read -r h wt title model state verdict; do
      [ -z "${h:-}" ] && continue
      grep -qxF "$h" <<<"$(cut -d'|' -f1 <<<"$cur")" \
        || echo "GONE  $wt / $model ($title) -- pane vanished; was $state"
    done <<< "$prev"

    prev="$cur"
    last_beat=$now
  elif [ $((now - last_beat)) -ge "$HEARTBEAT" ]; then
    if [ -z "$cur" ]; then
      echo "heartbeat: NO agent panes on the board"
    else
      echo "heartbeat: $(printf '%s\n' "$cur" | wc -l) pane(s), unchanged for $((HEARTBEAT / 60))m"
      printf '%s\n' "$cur" | while IFS='|' read -r _h wt _t model state verdict; do
        echo "  $wt / $model  $state${verdict:+  $verdict}"
      done
    fi
    last_beat=$now
  fi

  sleep "$POLL"
done
