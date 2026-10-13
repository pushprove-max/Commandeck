#!/usr/bin/env bash
# cos-watch-decisions.sh -- waits until the decision ledger holds an open
# decision the Chief of Staff has not put to the owner yet, prints it and
# exits, which wakes the pane (run it in the background).
# Seen marks live in <state>/<project>.decisions-seen; the pane appends a
# decision's printed `seen` value once it has asked the owner. The mark is the
# id and when it was asked, so a reopened decision is put to the owner again.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/cos-lib.sh"
SEEN=$COS_KEY.decisions-seen
touch "$SEEN"
poll() {
  local new
  new=$(bash "$PP_SCRIPTS/decision.sh" list 2>/dev/null \
    | jq -c --rawfile seen "$SEEN" '($seen | split("\n")) as $s | .[] | select(.answeredAt == null) | .seen = "\(.id)@\(.askedAt)" | select(.seen | IN($s[]) | not)' 2>/dev/null)
  [ -n "$new" ] && printf '%s\n' "$new"
}
cos_wait 20 poll
