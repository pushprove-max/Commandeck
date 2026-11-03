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

prev=""
pending=""
last_beat=0
fails=0

while true; do
  now=$(date +%s)

  # Clear KEEPALIVES ONLY. Workers send periodic "alive" pings, and an unacked
  # queue makes the app announce a waiting message -- so the operator gets
  # interrupted for something with no content. Ack a delivery only when every
  # message in it is a heartbeat; anything real (worker_done, question,
  # escalation) is left untouched for the interactive poll to show in full.
  # A BLOCKED worker is worse than an idle one: it waits on an answer, the ask
  # times out, and the work silently proceeds on a default. That cost a real
  # escalation once -- a worker asking whether to touch an out-of-scope file
  # went unanswered because nothing surfaced questions. Emit those loudly and
  # immediately, before anything else this cycle.
  peek=$(orca-ide orchestration check --timeout-ms 2000 --json 2>/dev/null)
  printf '%s' "$peek" | python3 -c '
import json,sys
try: r=json.load(sys.stdin).get("result",{})
except Exception: raise SystemExit
for m in r.get("messages") or []:
    if m.get("type") in ("question","escalation"):
        print("ANSWER NEEDED [" + str(m.get("type")) + "] " + str(m.get("subject","")))
        body=(m.get("body") or "").strip()
        if body: print("  " + body[:900].replace("\n","\n  "))
' 2>/dev/null

  ack=$(printf '%s' "$peek" | python3 -c '
import json,sys
try: r=json.load(sys.stdin).get("result",{})
except Exception: raise SystemExit
msgs=r.get("messages") or []
if msgs and all(m.get("type")=="heartbeat" for m in msgs):
    print(r.get("deliveryId") or "")
' 2>/dev/null)
  [ -n "$ack" ] && orca-ide orchestration check --ack "$ack" --timeout-ms 2000 --json >/dev/null 2>&1

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
