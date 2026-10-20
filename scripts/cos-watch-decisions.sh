#!/usr/bin/env bash
# cos-watch-decisions.sh -- waits until the decision ledger holds an open
# decision the Chief of Staff has not put to the owner yet, prints it and
# exits, which wakes the pane (run it in the background).
# Seen marks live in <state>/<project>.decisions-seen; the watcher appends a
# decision's printed `seen` value the moment it fires it (the pane's own later
# append is a harmless duplicate). The mark is the id and when it was asked,
# so a reopened decision is put to the owner again.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -u
. "$(dirname "${BASH_SOURCE[0]}")/cos-lib.sh"
SEEN=$COS_KEY.decisions-seen
touch "$SEEN"
poll() {
  local new
  new=$(bash "$PP_SCRIPTS/decision.sh" list 2>/dev/null \
    | jq -c --rawfile seen "$SEEN" '($seen | split("\n")) as $s | .[] | select(.answeredAt == null and .waitsOn != "main") | .seen = "\(.id)@\(.askedAt)" | select(.seen | IN($s[]) | not)' 2>/dev/null)
  [ -n "$new" ] || return 1
  printf '%s\n' "$new"
  # Mark on fire, not on ask: a restart before the pane writes its mark would fire the same decision again.
  jq -r '.seen' <<<"$new" >> "$SEEN"
}
cos_wait 20 poll
