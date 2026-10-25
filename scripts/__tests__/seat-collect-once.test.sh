#!/usr/bin/env bash
# seat-collect-once.test.sh -- seat.sh collect tells main of a finish once. The send runs under the seat's delivery
# lock (the one main-watch.sh flush takes) and writes a receipt, the seat's session log and its size, only after
# Orca took it: a second collect of the same finish sends nothing, a collect that waits on a held lock sends after
# it, once, a send Orca refused leaves no receipt (the next collect tries again), and a seat with no session log
# has no receipt to read, so it sends: a duplicate, never silence. The setup is fixtures/seat-setup.sh.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"

# A collect outside main's foreground (no Claude session, no terminal) sends; a foreground one sends only a finish a wait claimed.
unset COMMANDECK_DRIVER CLAUDECODE
col() { touch "$T/pane-up"; COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 COMMANDECK_MAIN_WATCH_LOCK_S=${LOCK_S:-20} run collect builder seat-builder 2>&1; }
wakes() { grep -c 'orchestration send' "$T/wakes" 2>/dev/null || true; }
COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch builder seat-builder "$T/spec.md" >"$T/out" 2>&1
REC=$(ls "$HOME/.commandeck/scratch/"*/seat-seat-builder-builder.txt); SC=$(dirname "$REC")
TASK=$(sed -n 's/^task=//p' "$REC" | tail -1); RCP=$SC/main-watch/delivered-seat-h1-$TASK
LOGD=$HOME/.claude/projects/$(printf '%s' "$SWT" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$LOGD"
# The finished turn is in the session log, which outranks the screen. The log grows by a line per later turn.
turn() { jq -cn --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{type: "assistant", timestamp: $t, message: {content: [{type: "text", text: "Done.\nVERDICT: GO"}]}},
  {type: "system", subtype: "turn_duration", timestamp: $t}'; }
turn > "$LOGD/sid1.jsonl"; echo "session=sid1" >> "$REC"
grow() { turn >> "$LOGD/sid1.jsonl"; }

col >"$T/out"
check "the first collect of a finish tells main once and leaves its receipt" "1:2" "$(wakes):$(wc -l < "$RCP" 2>/dev/null | tr -d ' ')"
check "the receipt names the seat's session log and its size" "$LOGD/sid1.jsonl $(stat -c %s "$LOGD/sid1.jsonl")" "$(sed -n 1p "$RCP") $(sed -n 2p "$RCP")"
col >"$T/out"
check "a second collect of the same finish sends nothing" 1 "$(wakes)"
# A turn past the receipt is a new finish.
grow; col >"$T/out"
check "a collect after the log grew past the receipt tells main again" 2 "$(wakes)"
# A main-watch.sh post of the finish leaves the same receipt, and then collect sends nothing.
printf '%s\n%s\n' "$LOGD/sid1.jsonl" "$(stat -c %s "$LOGD/sid1.jsonl")" > "$RCP"; col >"$T/out"
check "a collect of a finish main-watch.sh already posted (its receipt) sends nothing" 2 "$(wakes)"
# A held lock is waited for, then the receipt is read again under it.
grow
( exec 8>>"$RCP.lock"; flock 8; sleep 3; stat -c %s "$LOGD/sid1.jsonl" > /dev/null; printf '%s\n%s\n' "$LOGD/sid1.jsonl" "$(stat -c %s "$LOGD/sid1.jsonl")" > "$RCP" ) &
HOLD=$!; sleep 1; LOCK_S=15 col >"$T/out"; wait "$HOLD"
check "a collect waiting on a held lock reads the receipt the holder wrote and sends nothing" 2 "$(wakes)"
grow
( exec 8>>"$RCP.lock"; flock 8; sleep 3 ) & HOLD=$!; sleep 1; LOCK_S=15 col >"$T/out"; wait "$HOLD"
check "a collect waiting on a held lock sends after it, once" 3 "$(wakes)"
# Orca refusing the send leaves no receipt: the next collect tries again.
grow; touch "$T/send-refuses"; col >"$T/out"; rm "$T/send-refuses"
check "a send Orca refused is said and leaves the old receipt" "1:4" "$(grep -c 'could not wake main' "$T/out"):$(wakes)"
col >"$T/out"
check "the next collect after a refusal sends" 5 "$(wakes)"
# No session log: no receipt can be read, so every collect sends.
sed -i '/^session=/d' "$REC"; rm -f "$LOGD/sid1.jsonl"; printf 'Done.\nVERDICT: GO\n' > "$T/screen"; col >"$T/out"; col >"$T/out"
check "a seat with no session log sends on each collect: a duplicate, never silence" 7 "$(wakes)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
