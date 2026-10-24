#!/usr/bin/env bash
# Issue 331: every attempt of main-watch.sh to wake main leaves one line in the wake log with that attempt's result, so a
# night of unwoken mail can be read back. Also the log's own upkeep: the wake log rotates at 1 MiB, the watcher's log is
# cut in place, and a failure repeated every tick leaves one line and a count. The 10-minute alert is in
# main-watch-wake-streak.test.sh.
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
nlog() { jq -rs --arg r "$1" '[.[] | select(.result == $r)] | length' "$WL" 2>/dev/null || echo 0; }
reset() { rm -f "$ST/wake" "$ST/wake-told" "$ST/unread-since" "$ST/wake-streak" "$ST/wake-alert" "$F/no-turn" "$F/read-fail" "$F/screen"; : > "$T/typed"; : > "$T/sends"; }
nopane() { awk '$1 != "term_main"' "$F/agents" > "$F/agents.new"; mv "$F/agents.new" "$F/agents"; }
mail() { msg term_x "order from the relay" question "$1" | inbox; }
gaveup() { # <start> -- unread mail, then three typed wakes that start no turn, then the give-up tick
  mail "$1"
  tick "$1"; tick $(($1 + 120)); tick $(($1 + 180)); tick $(($1 + 240))
  [ "$(typed)" = 3 ] || fail "wake log: expected 3 typed wakes before the give-up, got $(typed)"
}
export COMMANDECK_OPTIONS='{"wakeWindowSeconds":120}'; mkdir -p "$T/ws/Chief-of-Staff"; rm -f "$WL"; B=200000
reset; mail $B; tick $B; tick $((B + 120))
[ "$(lastwake)" = turn_started ] || fail "wake log: a wake that started a turn logged $(lastwake)"
[ ! -e "$ST/wake-streak" ] || fail "wake log: a wake that started a turn left a failure streak"
B=$((B + 1000)); reset; touch "$F/no-turn"; mail $B; tick $B; tick $((B + 120))
[ "$(lastwake)" = no_turn ] || fail "wake log: a typed wake with no turn started logged $(lastwake)"
B=$((B + 1000)); reset; printf 'Pick one\nEnter to select, Esc to cancel\n' > "$F/screen"; mail $B; tick $B; tick $((B + 120))
[ "$(lastwake)" = blocked ] || fail "wake log: main with an open prompt logged $(lastwake)"
B=$((B + 1000)); reset; touch "$F/read-fail"; mail $B; tick $B; tick $((B + 120))
[ "$(lastwake)" = unreadable ] || fail "wake log: a screen that cannot be read logged $(lastwake)"
# Unread mail alone arms the wake for a main that is not listed, so it logs no_pane and the 10-minute alert can fire.
B=$((B + 1000)); reset; nopane; mail $B; tick $((B + 120))
[ "$(lastwake)" = no_pane ] || fail "wake log: no pane for main logged $(lastwake)"
jq -rs '[.[] | select(.result == "no_pane")] | last | .error' "$WL" | grep -q 'no live pane' || fail "wake log: the no_pane line does not say why"
state term_main idle
B=$((B + 1000)); reset; touch "$F/no-turn"; G=$B; gaveup $G; tick $((G + 300))
[ "$(lastwake)" = gave_up ] || fail "wake log: out of tries logged $(lastwake)"
[ "$(nlog no_turn)" -ge 3 ] || fail "wake log: the three typed wakes that started no turn were not each logged"

jq -es 'all(.[]; has("at") and has("from") and has("to") and has("reason") and has("result") and has("error") and (.at | test("Z$")))' "$WL" >/dev/null \
  || fail "wake log: a line lacks at, from, to, reason, result or error, or its time is not UTC"
[ "$(jq -rs '[.[] | select(.reason | startswith("tell relay")) | .result] | unique | join(",")' "$WL")" = sent ] \
  || fail "wake log: the relay's notes (blocked, gave_up) are not sent lines: $(grep 'tell relay' "$WL")"

# A flush main takes is a sent line to main's run, one a refused send is a refused line.
finish() { # <unit> <epoch> -- a plan-author seat that was working at <epoch> - 100 and is done at <epoch>
  mkdir -p "$T/ws/$1-plan"; printf 'handle=term_%s\ntask=task_%s\nrole=plan-author\nunit=%s\nlaunched=%s\nworktree=%s-plan\n' "$1" "$1" "$1" $(($2 - 1400)) "$1" > "$S/seat-$1-plan-author.txt"
  echo "task_$1 running" >> "$F/tasks"; state term_$1 working; tick $(($2 - 100)); echo PLAN-DONE > "$F/verdict-term_$1"; state term_$1 done; tick "$2"; }
reset; rm -f "$WL"; B=$((B + 5000)); finish fl1 $B
[ "$(jq -rs '[.[] | select(.reason == "flush 1 item(s)" and .to == "run:run_test")] | map(.result) | join(",")' "$WL")" = sent ] \
  || fail "wake log: a flush Orca took is not one sent line to main's run: $(cat "$WL")"
touch "$F/refuse-sends"
B=$((B + 5000)); finish fl2 $B
[ "$(jq -rs '[.[] | select(.reason == "flush 1 item(s)" and .result == "refused")] | length' "$WL")" -ge 1 ] \
  || fail "wake log: a flush Orca refused is not a refused line: $(cat "$WL")"
rm -f "$F/refuse-sends"

# The wake log is rotated by size: past 1 MiB the file moves to .1 and the live file restarts.
head -c 1100000 /dev/zero | tr '\0' x > "$WL"; rm -f "$WL.1"
(COMMANDECK_SCRATCH=$S bash -c '. "$0/scripts/paths.sh" && pp_wake_log rot test probe sent' "$REPO")
[ "$(wc -c < "$WL.1")" -ge 1048576 ] && [ "$(grep -c . "$WL")" = 1 ] || fail "wake log: past 1 MiB it did not move to .1 and restart ($(grep -c . "$WL") lines live)"
# The watcher's own log is cut in place (launchd holds it open) to its last 512 KiB past 1 MiB, its last line kept.
LOGF=$S/scratchpad/main-watch.log; mkdir -p "${LOGF%/*}"
{ head -c 2000000 /dev/zero | tr '\0' y | fold -w 100; echo; echo "LAST LINE"; } > "$LOGF"; INO=$(ls -i "$LOGF" | cut -d' ' -f1)
tick $((B + 20000))
[ "$(wc -c < "$LOGF")" -le 524288 ] && [ "$(ls -i "$LOGF" | cut -d' ' -f1)" = "$INO" ] && [ "$(tail -1 "$LOGF")" = "LAST LINE" ] \
  || fail "log trim: main-watch.log is $(wc -c < "$LOGF") bytes, or changed inode, or lost its last line"
# Identical failures in the running loop leave one line and a repeated count.
reset; nopane; NOWS=$(date +%s); mail $((NOWS - 1000)); tick $((NOWS - 500))
COMMANDECK_NOW= COMMANDECK_MAIN_WATCH_MAX_TICKS=6 COMMANDECK_MAIN_WATCH_TICK_S=0 mw 2> "$T/loop.err" || fail "the running loop exited non-zero"
[ "$(grep -c 'no main pane to wake' "$T/loop.err")" = 1 ] && grep -q '^(repeated 5 times)$' "$T/loop.err" \
  || fail "log dedupe: 6 identical failures did not leave one line and a repeated count: $(sort "$T/loop.err" | uniq -c | head -5)"

echo "PASS main-watch-wake-log.test.sh"
