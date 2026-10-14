#!/usr/bin/env bash
set -euo pipefail

result=$(
  (
    set +e
    exec 3>&1
    BASE=(); ERRF=/dev/null
    MSGDIR=/dev/null/messages
    FULL=0; TOTAL=0
    KEEP='.result.messages[]?'
    RENDER='[.subject, (.body | .[0:200]),
      ($mdir + "/" + .id + ".md")] | join(" | ")'

    checked() { return 0; }
    driver_units() { echo '[]'; }
    handle_units() { echo '{}'; }
    warn_codex_budget() { :; }
    enrich() { :; }
    serve() { :; }
    orca-ide() {
      case " $* " in
        (*' --ack '*)
          echo ACK_SENT >&3
          echo '{"result":{"messages":[],"deliveryId":null}}'
          ;;
        (*)
          printf '{"result":{"deliveryId":"d1","messages":[
            {"id":"m1","subject":"ask","body":"%sTAIL"}]}}\n' \
            "$(printf 'x%.0s' {1..250})"
          ;;
      esac
    }

    eval "$(sed -n '/^drain() {/,/^}/p' scripts/orca-wait.sh)"
    drain
    echo "rc=$?"
  ) 2>/dev/null
) || true

case "$result" in
  *ACK_SENT*) echo "FAIL: acknowledged an unsaved message" >&2; exit 1 ;;
esac
case "$result" in
  *'orca-wait: could not save message bodies to /dev/null/messages; not acknowledged'*) ;;
  *) echo "FAIL: an unsaved message printed no clear line: $result" >&2; exit 1 ;;
esac
case "$result" in
  *rc=0*) echo "FAIL: drain returned zero with an unsaved message" >&2; exit 1 ;;
esac
echo "PASS: an unsaved message remains unacknowledged"
