#!/usr/bin/env bash
# main-watch.sh wakes main, and the panes that wait on it, only when there is
# something to wake for: mail unread 2 minutes with main idle, main blocked on
# its own question (the relay hears once), and a 5-minute Builder waiting on a
# background job (one WARM line before its cache lapses, up to a budget).
# The fixture is the one main-watch-helper-hold.test.sh uses.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
# The watcher posts only what finished after its first tick.
tick 5000

# Mail from another pane that sits unread while main is idle wakes main: two orders once sat
# 13 minutes with main idle, because only this watcher's own posts ever typed a wake. A heads-up
# note and main's own send are not news to main.
msg() { jq -nc --arg f "$1" --arg s "$2" '{to_handle: "run:run_test", from_handle: $f, read: 0, type: "status", subject: $s}'; }
inbox() { jq -sc '{ok: true, result: {messages: .}}' > "$F/inbox"; }
typed() { grep -c 'items are waiting in your Orca inbox' "$T/typed" 2>/dev/null || true; }
# The seats above are done with and their tasks closed, so nothing of theirs is pending.
rm -f "$S"/seat-*.txt "$S/main-watch/wake"; sed -i 's/ .*/ completed/' "$F/tasks"
M=30000; : > "$T/typed"
{ msg term_main "main's own note"; msg term_x "heads-up: 2 notes"; } | inbox
tick $M; tick $((M + 200))
[ "$(typed)" = 0 ] || fail "main was woken for a heads-up note or its own send"
{ msg term_main "main's own note"; msg term_x "heads-up: 2 notes"; msg term_wt-h1 "order from a Builder"; } | inbox
tick $((M + 300)); tick $((M + 360))
[ "$(typed)" = 0 ] || fail "main was woken for mail unread under 2 minutes"
tick $((M + 420))
[ "$(typed)" = 1 ] || fail "mail unread 2 minutes with main idle did not wake main (typed $(typed))"
tick $((M + 480))
[ "$(typed)" = 1 ] || fail "an unanswered main was woken again inside 2 minutes"
rm -f "$F/inbox"

# Issue 198: main idle with its own question open reads nothing, and main-watch gave up on it without a word. The
# relay hears once per wake episode, through main's run under main's handle: the service has no pane of its own.
unset ORCA_TERMINAL_HANDLE
rm -f "$S/main-watch/wake" "$S/main-watch/unread-since"; : > "$T/typed"; W=35000
printf 'Which release?\n> 1. 0.18.0\nEnter to select, Esc to cancel\n' > "$F/screen"
msg term_x "order from the relay" | inbox
tick $W; tick $((W + 120))
[ "$(typed)" = 0 ] || fail "main was typed into while its screen showed an open question"
[ "$(posts 'cos: main-watch')" = 0 ] || fail "the relay was told with no Chief-of-Staff worktree"
mkdir -p "$T/ws/Chief-of-Staff"; tick $((W + 180)); tick $((W + 240))
[ "$(posts 'cos: main-watch: main has not read finished work')" = 1 ] || fail "main blocked on a prompt with work unread: the relay was told $(posts 'cos: main-watch') times, not once"
grep 'cos: main-watch' "$T/sends" | grep -q -- '--to run:run_test.*--from term_main' || fail "the relay's note did not go to main's run under main's handle"
grep 'cos: main-watch' "$T/sends" | grep -q 'answer the prompt in main' || fail "the relay's note does not name the fix"
[ "$(typed)" = 0 ] || fail "main was typed into while its screen showed an open question"
rm -rf "$F/screen" "$F/inbox" "$T/ws/Chief-of-Staff" "$S/main-watch/wake" "$S/main-watch/unread-since"


# Issue 203, WARM: a 5-minute Builder at its prompt waiting on a background job gets one "." line just before its own
# cache lapses, up to a cost-bound budget. Orca reads such a pane working or done, so the gate is the session record's
# end_turn marker, not the label. A ping never posts to main and never counts as an episode toward the third-episode post.
rm -f "$S"/seat-*.txt; : > "$T/sends"; : > "$T/typed"
W=90000
bts() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
wfile() { printf '%s' "$T/home/.claude/projects/$(printf '%s' "$T/ws/$1" | sed 's/[^a-zA-Z0-9]/-/g')/s.jsonl"; }
wlog() { # unit epoch stop [read write] -- one main-thread request and its reply in the unit's session record, its mtime following
  local f; f=$(wfile "$1"); mkdir -p "${f%/*}"
  printf '{"type":"user","isSidechain":false,"timestamp":"%s","message":{}}\n' "$(bts "$2")" >> "$f"
  printf '{"type":"assistant","isSidechain":false,"timestamp":"%s","message":{"stop_reason":"%s","usage":{"input_tokens":2,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":0}}}}\n' \
    "$(bts "$2")" "$3" "${4:-95000}" "${5:-5000}" "${5:-5000}" >> "$f"
  touch -d "@$2" "$f"
}
wseat() { # unit handle state [read write last-stop] -- a Builder whose last reply, 230 s before W, left a background job running
  bseat "$1" "$2" "t_$1" $((W - 4000)); state "$2" "$3"
  printf '{"ts":"%s","event":"tool-start","use":"o1","tool":"Bash","kind":"shell","call":"o1"}\n{"ts":"%s","event":"tool-end","use":"o1","ok":true}\n' \
    "$(bts $((W - 3000)))" "$(bts $((W - 2999)))" > "$T/ws/$1/.claude/builder-events.jsonl"
  wlog "$1" $((W - 400)) tool_use "${4:-95000}" "${5:-5000}"
  printf '{"type":"user","toolUseResult":{"stdout":"","backgroundTaskId":"bW"}}\n' >> "$(wfile "$1")"
  wlog "$1" $((W - 230)) "${6:-end_turn}" "${4:-95000}" "${5:-5000}"
}
warms() { grep -c -- "--terminal $1 --text Signal WARM: keep-alive while you wait. Reply with one . and end your turn." "$T/typed" || true; }
wseat wt-w1 term_w1 working
wseat wt-w2 term_w2 done
wseat wt-w3 term_w3 working 95000 5000 tool_use
wseat wt-w5 term_w5 waiting
wseat wt-w7 term_w7 working 500 498
tick $W
[ "$(warms term_w1)" = 1 ] || fail "warm: a Builder reading working, its log ending on end_turn with a job open, got $(warms term_w1) WARM lines, not one"
[ "$(warms term_w2)" = 1 ] || fail "warm: the same Builder reading done did not get its first WARM"
[ "$(warms term_w3)" = 0 ] || fail "warm: a Builder whose newest reply is a tool_use (blocked inside a call) was pinged"
[ "$(warms term_w5)" = 0 ] || fail "warm: a pane reading waiting was pinged"
[ "$(posts wt-w)" = 0 ] || fail "warm: a ping posted to main"
tick $((W + 10))
[ "$(warms term_w1)" = 1 ] || fail "warm: the next tick in the same window sent a second ping"
wlog wt-w1 $((W + 30)) end_turn; wlog wt-w7 $((W + 30)) end_turn 500 498
tick $((W + 260))
[ "$(warms term_w1)" = 2 ] || fail "warm: after the Builder's own . reply the next window did not get a ping (got $(warms term_w1))"
[ "$(warms term_w7)" = 2 ] || fail "warm: a 1000-token context should have pinged twice by now (got $(warms term_w7))"
wlog wt-w7 $((W + 290)) end_turn 500 498; tick $((W + 520))
[ "$(warms term_w7)" = 2 ] || fail "warm: a third ping went past the budget of 2 for one anchor"
# After two WARMs the Builder's first QUIET is still its first episode: WARM keeps its own history.
H1=$S/main-watch/builder-wt-w1-term_w1
[ "$(grep -c . "$H1.warm")" = 2 ] && ! grep -q WARM "$H1" 2>/dev/null || fail "warm: the pings were not kept apart from the episode history"
# The job ends (its notification row), so the idle Builder is QUIET.
printf '{"type":"queue-operation","content":"<task-notification>\\n<task-id>bW</task-id>\\n</task-notification>"}\n' >> "$(wfile wt-w1)"
touch -d "@$((W + 30))" "$(wfile wt-w1)"; tick $((W + 560))
[ "$(grep -c '^QUIET ' "$H1")" = 1 ] && [ "$(posts 'wt-w1 is QUIET')" = 0 ] || fail "warm: after two WARMs the first QUIET was not episode 1, or was posted"

# Issue 238: three unproven wakes told the relay "restart main" although main had restarted itself in between.
# Main's session log written after the first try is a main at work again: nothing is told. Unmoved, the relay hears.
rm -f "$S"/seat-*.txt; sed -i 's/ .*/ completed/' "$F/tasks"; : > "$T/sends"; : > "$T/typed"
rm -f "$S/main-watch/wake" "$S/main-watch/wake-told" "$S/main-watch/unread-since"; mkdir -p "$T/ws/Chief-of-Staff"; : > "$F/no-turn"
MLOG=$T/home/.claude/projects/$(printf '%s' "$REPO" | sed 's/[^a-zA-Z0-9]/-/g')/m.jsonl
gaveup() { # <start> -- unread mail, then three typed wakes that start no turn, then the give-up tick
  msg term_x "order from the relay" | inbox
  tick "$1"; tick $(($1 + 120)); tick $(($1 + 180)); tick $(($1 + 240))
  [ "$(typed)" = 3 ] || fail "restart: expected 3 typed wakes before the give-up, got $(typed)"
}
G=100000; gaveup $G
mkdir -p "${MLOG%/*}"; echo '{}' > "$MLOG"; touch -d "@$((G + 200))" "$MLOG"
tick $((G + 300))
[ "$(posts 'restart main')" = 0 ] || fail "restart: the relay was told to restart a main whose session log moved after the first try"
[ ! -e "$S/main-watch/wake" ] || fail "restart: the wake was kept after main's log moved"
rm -f "$S/main-watch/unread-since" "$MLOG"; : > "$T/typed"; G=110000; gaveup $G
tick $((G + 300))
[ "$(posts 'restart main')" = 1 ] || fail "restart: three unproven wakes with main's log unmoved did not tell the relay"
rm -f "$F/no-turn" "$F/inbox" "$S/main-watch/wake" "$S/main-watch/wake-told" "$S/main-watch/unread-since"

# Issue 232: a picker open in the relay's own pane hid 9 messages for 38 minutes. While its screen shows a prompt and
# its mail waits, main-watch records since when; the dashboard raises it at 30 minutes, not before.
P=130000; PK=$S/main-watch/relay-picker.json
state term_cos idle; printf 'Pick one\nEnter to select, Esc to cancel\n' > "$F/screen-term_cos"
for i in 1 2; do jq -nc '{to_handle: "term_cos", from_handle: "term_x", read: 0, subject: "note"}'; done \
  | jq -sc '{ok: true, result: {messages: .}}' > "$F/inbox-term_cos"
tick $P; tick $((P + 60))
[ "$(jq -c . "$PK" 2>/dev/null)" = "{\"since\":$P,\"waiting\":2}" ] || fail "picker: the record is $(cat "$PK" 2>/dev/null), not since $P with 2 waiting"
pk() { jq -nc -f "$SOURCE/scripts/dashboard_alerts.jq" --argjson now "$1" --arg s7 2026-10-08 --argjson hasSe false --argjson se '[]' \
  --argjson parts "[{\"projects\": {\"p\": {\"chiefOfStaff\": {\"picker\": $(cat "$PK")}}}}]" --argjson srcs '[]' --argjson prev '{}' \
  | jq -r '.alerts[] | select(.id | startswith("relay-picker-p-")) | .text'; }
[ -z "$(pk $((P + 29 * 60)))" ] || fail "picker: raised at 29 minutes"
pk $((P + 31 * 60)) | grep -q 'relay picker open 31 min; 2 messages waiting' || fail "picker: not raised at 31 minutes: $(pk $((P + 31 * 60)))"
rm -f "$F/screen-term_cos"; tick $((P + 120))
[ ! -e "$PK" ] || fail "picker: the record outlived the picker"
rm -rf "$F/inbox-term_cos" "$T/ws/Chief-of-Staff"

echo "PASS main-watch-wake.test.sh"
