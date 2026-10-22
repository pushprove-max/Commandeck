#!/usr/bin/env bash
# Issue 318: the window's one wake claim, raced by main-watch's typed wake and Orca's nudge (the real cos-own-echo.sh
# hook in main's checkout). Only its own taker gives a claim back, and an unproven wake is retried whatever state is
# lost between two ticks. Both sources in order are main-watch-wake-sources.test.sh.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
# The watcher posts only what finished after its first tick; the fixture's seats are done with and their tasks closed.
tick 5000; rm -f "$S"/seat-*.txt "$S/main-watch/wake"; sed -i 's/ .*/ completed/' "$F/tasks"
: > "$T/typed"; : > "$F/inbox.jsonl"; touch "$F/live-inbox"; : > "$T/passed"; touch "$F/no-turn"
export COMMANDECK_OPTIONS='{"wakeWindowSeconds":5}'
# overlap: a nudge that takes the claim while the watcher's send waits for its receipt keeps it. The watcher's give-back
# of its unproven wake removes only its own claim, so the next nudge is held, and the wake retries once that window passes.
X=70000; ask $X run:run_test; tick $X
{ declare -p T F S REPO SOURCE; declare -f nudge; echo "nudge $((X + 11))"; } > "$F/flip-send"
tick $((X + 5)); nudge $((X + 12)); tick $((X + 12))
[ "$(typed)" = 1 ] && [ "$(grep -c . "$T/passed")" = 1 ] || fail "overlap: the watcher's give-back freed a nudge's claim (typed $(typed), nudges passed $(cat "$T/passed"))"
tick $((X + 17))
[ "$(typed)" = 2 ] || fail "overlap: the unproven wake was not retried once the nudge's window passed (typed $(typed))"
# state lost: each piece of the wake's state removed between two ticks, the unproven wake is still retried.
for p in wake unread-since unread-since.lock wake-first wake-told; do
  X=$((X + 1000)); drained; : > "$T/typed"; rm -f "$S/main-watch/wake" "$S/main-watch/unread-since" "$S/main-watch/wake-first"
  ask $X run:run_test; tick $((X + 5)); rm -f "$S/main-watch/$p"; tick $((X + 6))
  [ "$(typed)" = 2 ] || fail "state lost: with $p removed between two ticks the unproven wake was not retried (typed $(typed))"
done
# empty read: a nudge that claims after the watcher read an inbox with nothing actionable keeps its claim.
X=$((X + 1000)); drained; : > "$T/passed"; rm -f "$S/main-watch/wake" "$S/main-watch/unread-since"
{ declare -p T F S REPO SOURCE; declare -f ask nudge; echo "ask $((X - 10)) run:run_test; nudge $X"; } > "$F/flip-inbox"
tick $X; nudge $((X + 1))
[ "$(cat "$T/passed")" = "$X" ] || fail "empty read: the watcher's empty inbox read freed a nudge's newer claim (nudges passed $(cat "$T/passed"))"

echo "PASS main-watch-wake-race.test.sh"
