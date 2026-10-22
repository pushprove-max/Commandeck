#!/usr/bin/env bash
# Issue 318, both wake sources at once: main-watch's typed wake and Orca's nudge (the real cos-own-echo.sh hook in
# main's checkout). Two actionable messages 10 s apart cost main one turn, at the window's close (60 s); a window that
# holds only status notes costs none, and they are still unread, so the next real wake's drain shows them. The claim's
# races are main-watch-wake-race.test.sh; both left main-watch-wake.test.sh, which ran past the runner's cap under load.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
# The watcher posts only what finished after its first tick; the fixture's seats are done with and their tasks closed.
tick 5000; rm -f "$S"/seat-*.txt "$S/main-watch/wake"; sed -i 's/ .*/ completed/' "$F/tasks"
: > "$T/typed"; : > "$F/inbox.jsonl"; touch "$F/live-inbox"; : > "$T/passed"
wakes() { echo $(( $(typed) + $(grep -c . "$T/passed") )); }
unread() { jq -s '[.[] | select(.read == 0)] | length' "$F/inbox.jsonl"; }
# 2,001 processes: main-watch posts an item at C, through flush, to the run.
printf '#!/usr/bin/env bash\ncase "$*" in *lstart=*) exec /bin/ps "$@" ;; esac\n[ ! -e %q ] || cat %q\n' "$F/procs" "$F/procs" > "$T/bin/ps"
for i in $(seq 1 2001); do echo "$(id -u) $i 1 00:01 /bin/sleep"; done > "$F/procs"
C=40000; tick $C; rm -f "$F/procs"; nudge $C
[ "$(grep -c 'processes for this user' "$F/inbox.jsonl")" = 1 ] || fail "combined: main-watch did not post the process item: $(cat "$F/inbox.jsonl")"
ask $((C + 10)) term_main; nudge $((C + 10)); tick $((C + 30)); nudge $((C + 59)); tick $((C + 59))
[ "$(wakes)" = 0 ] || fail "combined: main woke inside the window (typed $(typed), nudges passed $(cat "$T/passed"))"
# A nudge right after main-watch's wake, before main drains, is the same wake: one claim per window serves both sources.
tick $((C + 60)); nudge $((C + 60))
[ "$(wakes)" = 1 ] && [ "$(unread)" = 2 ] || fail "combined: not one wake at the window's close with both messages unread for its drain (wakes $(wakes), unread $(unread))"
drained; nudge $((C + 60)); tick $((C + 120)); nudge $((C + 120))
[ "$(wakes)" = 1 ] || fail "combined: two actionable messages 10 s apart cost $(wakes) wakes, not one"
D=50000; : > "$T/typed"; : > "$T/passed"
jq -nc --argjson at $D '{to_handle: "run:run_test", from_handle: "term_x", read: 0, type: "status", subject: "merge still running", created_at: ($at | todate)}' >> "$F/inbox.jsonl"
tick $D; nudge $D; tick $((D + 60)); nudge $((D + 60)); tick $((D + 120))
[ "$(wakes)" = 0 ] || fail "combined: a window holding only a status note woke main ($(wakes))"
ask $((D + 200)) run:run_test; nudge $((D + 200)); tick $((D + 200)); tick $((D + 260))
[ "$(wakes)" = 1 ] && [ "$(unread)" = 2 ] || fail "combined: the next question's wake did not come once with the held note still unread for its drain (wakes $(wakes), unread $(unread))"
# The other order: Orca's nudge at the window's close starts the turn, and main-watch's tick then types nothing.
E=60000; drained; tick $E; : > "$T/typed"; : > "$T/passed"
ask $E run:run_test; tick $E; nudge $((E + 60)); tick $((E + 60)); tick $((E + 90))
[ "$(wakes)" = 1 ] && [ "$(grep -c . "$T/passed")" = 1 ] || fail "combined: a nudge and main-watch's tick both woke main at the window's close (typed $(typed), nudges passed $(cat "$T/passed"))"
# The held wake retries whatever state is lost between ticks: its wake file gone, the next tick re-arms and types once
# the claim's window has passed; the claim gone, the next tick takes the wake at once.
rm -f "$S/main-watch/wake"; tick $((E + 120))
[ "$(typed)" = 1 ] || fail "combined: with its wake file gone, the unread question was not typed a window after the nudge (typed $(typed))"
rm -f "$S/main-watch/unread-since"; tick $((E + 121))
[ "$(typed)" = 2 ] || fail "combined: with the claim gone, the unread question was not typed at the next tick (typed $(typed))"

# Issue 321: Orca lists main's pane with agentIdentity null and the run's coordinator is a live pane in another
# checkout. main-watch, a service with no terminal, refused on every task-create and send: it now sends as that
# coordinator, and types nothing into it.
G=70000; drained; rm -f "$S/main-watch/item-"* "$S/main-watch/wake" "$T/creates" "$T/refused"; : > "$T/typed"; : > "$T/sends"
touch "$F/no-identity" "$F/need-from"; echo term_coord > "$F/coord"; state term_coord working
for i in $(seq 1 2001); do echo "$(id -u) $i 1 00:01 /bin/sleep"; done > "$F/procs"; tick $G; rm -f "$F/procs"
[ "$(grep -c -- '--from term_coord' "$T/creates" 2>/dev/null)" = 1 ] && [ "$(grep -c -- '--from term_coord' "$T/sends")" = 1 ] && [ ! -s "$T/refused" ] \
  || fail "main's pane listed with agentIdentity null and the run's coordinator live elsewhere: task-create and send did not carry --from term_coord (refused: $(cat "$T/refused" 2>/dev/null))"
! grep -q -- '--terminal term_coord' "$T/typed" || fail "the coordinator outside the main checkout was typed into"

echo "PASS main-watch-wake-sources.test.sh"
