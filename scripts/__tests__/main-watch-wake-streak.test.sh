#!/usr/bin/env bash
# Issue 331: the same wake failure for 10 minutes tells the relay once ("restart main"); a woken pane clears it, a new
# failure restarts the clock, and mail Orca takes (a flush to main's run) neither starts, restarts nor clears it.
# The wake log's lines are in main-watch-wake-log.test.sh.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
# The watcher posts only what finished after its first tick; the fixture's seats are done with and their tasks closed.
tick 5000; rm -f "$S"/seat-*.txt "$S/main-watch/wake"; sed -i 's/ .*/ completed/' "$F/tasks"
: > "$T/typed"; : > "$T/sends"
msg() { jq -nc --arg f "$1" --arg s "$2" --arg t "${3:-question}" --argjson at "${4:-0}" \
  '{to_handle: "run:run_test", from_handle: $f, read: 0, type: $t, subject: $s, created_at: ($at | todate)}'; }
inbox() { jq -sc '{ok: true, result: {messages: .}}' > "$F/inbox"; }
WL=$S/wake-log.jsonl ST=$S/main-watch
lastwake() { jq -rs '[.[] | select(.from == "main-watch" and .reason == "wake")] | last | .result // "none"' "$WL" 2>/dev/null || echo none; }
nopane() { awk '$1 != "term_main"' "$F/agents" > "$F/agents.new"; mv "$F/agents.new" "$F/agents"; }
mail() { msg term_x "order from the relay" question "$1" | inbox; }
restarts() { posts 'restart main'; }
clear_wake() { rm -f "$ST/wake" "$ST/wake-told" "$ST/unread-since" "$ST/wake-streak" "$ST/wake-alert" "$F/no-turn" "$F/read-fail" "$F/screen"; }
streak_start() { cut -d' ' -f1 "$ST/wake-streak" 2>/dev/null; }
finish() { # <unit> <epoch> -- a plan-author seat that was working at <epoch> - 100 and is done at <epoch>
  mkdir -p "$T/ws/$1-plan"; printf 'handle=term_%s\ntask=task_%s\nrole=plan-author\nunit=%s\nlaunched=%s\nworktree=%s-plan\n' "$1" "$1" "$1" $(($2 - 1400)) "$1" > "$S/seat-$1-plan-author.txt"
  echo "task_$1 running" >> "$F/tasks"; state term_$1 working; tick $(($2 - 100)); echo PLAN-DONE > "$F/verdict-term_$1"; state term_$1 done; tick "$2"; }
export COMMANDECK_OPTIONS='{"wakeWindowSeconds":120}'; mkdir -p "$T/ws/Chief-of-Staff"; rm -f "$WL"

# No pane for main, every tick from t0.
clear_wake; nopane; U=200000; mail $U; tick $U; tick $((U + 120)); s=$(streak_start)
[ -n "$s" ] || fail "streak: a no_pane wake started no streak"
tick $((s + 300)); tick $((s + 540))
[ "$(restarts)" = 0 ] || fail "streak: the relay was told 'restart main' at 9 minutes of no_pane"
tick $((s + 600))
[ "$(restarts)" = 1 ] || fail "streak: 10 minutes of no_pane did not tell the relay once (told $(restarts) times)"
tick $((s + 660))
[ "$(restarts)" = 1 ] || fail "streak: the same streak told the relay again (told $(restarts) times)"
[ "$(streak_start)" = "$s" ] || fail "streak: the start moved while the same failure repeated"
state term_main idle; tick $((s + 720))
[ "$(lastwake)" = turn_started ] && [ ! -e "$ST/wake-streak" ] && [ ! -e "$ST/wake-alert" ] || fail "streak: a wake that started a turn did not clear the streak and its alert"
# A new streak alerts again only 600 s after its own start.
nopane; clear_wake; U=$((U + 5000)); mail $U; tick $U; tick $((U + 120)); s=$(streak_start)
tick $((s + 540))
[ "$(restarts)" = 1 ] || fail "streak: a new streak alerted before its own 10 minutes (told $(restarts) times)"
tick $((s + 600))
[ "$(restarts)" = 2 ] || fail "streak: a new streak did not alert after its own 10 minutes (told $(restarts) times)"
# no_pane that turns to unreadable restarts the clock: the failure is another one.
clear_wake; U=$((U + 5000)); mail $U; tick $U; tick $((U + 120)); s=$(streak_start); tick $((s + 300))
state term_main idle; touch "$F/read-fail"; tick $((s + 360)); r=$(streak_start)
[ "$(cut -d' ' -f2 "$ST/wake-streak")" = unreadable ] && [ "$r" = $((s + 360)) ] || fail "streak: no_pane turning to unreadable did not restart the clock ($(cat "$ST/wake-streak"))"
tick $((s + 360 + 540))
[ "$(restarts)" = 2 ] || fail "streak: the clock of the first failure alerted for the second (told $(restarts) times)"
tick $((s + 360 + 600))
[ "$(restarts)" = 3 ] || fail "streak: 10 minutes of unreadable did not alert (told $(restarts) times)"
# Mail Orca takes (a flush to main's run) is not a woken pane: it neither starts, restarts nor clears a streak.
rm -f "$F/read-fail"; clear_wake; nopane; U=$((U + 5000)); mail $U; tick $U; tick $((U + 120)); s=$(streak_start)
finish mx1 $((s + 300)); finish mx2 $((s + 600))
[ "$(streak_start)" = "$s" ] || fail "streak: a flush Orca took moved the streak start ($(cat "$ST/wake-streak"))"
[ "$(restarts)" = 4 ] || fail "streak: with flushes between, the alert did not fire at the first tick past 10 minutes (told $(restarts) times)"
state term_main idle; tick $((s + 700))
[ ! -e "$ST/wake-streak" ] || fail "streak: a later turn_started did not clear the streak that flushes had crossed"

echo "PASS main-watch-wake-streak.test.sh"
