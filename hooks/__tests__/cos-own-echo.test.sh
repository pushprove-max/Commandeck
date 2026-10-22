#!/usr/bin/env bash
# Self-test for cos-own-echo.sh.
# Run directly: bash hooks/__tests__/cos-own-echo.test.sh
#
# Orca tells a pane "You have N orchestration messages" for the messages it sent
# to the run itself, and the relay pane spent a whole turn reading back its own
# sends. Pinned: a batch that is all this pane's own is acknowledged once and the
# prompt dropped; a batch holding one message from anyone else passes untouched
# and unacknowledged, since that message is real; any other prompt passes without
# an Orca call (the hook runs on every prompt in every pane); the same prompt in
# a pane that is not the relay passes; an Orca failure passes. The `orca-ide`
# stub logs every call, so the log is the proof of what was asked and acked.
set -u
SOURCE=$(git rev-parse --show-toplevel)
HOOK=$SOURCE/hooks/cos-own-echo.sh
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
mkdir -p "$T/bin"
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$T/p" worktree add -q "$T/ws/Chief-of-Staff" -b cos
git -C "$T/p" worktree add -q "$T/ws/u1" -b u1
# Orca: a check answers $T/batch (messages from the handles listed in it, one a line) with delivery dl_1,
# unless $T/down exists. Every call is logged.
# An inbox read answers $T/inbox, a JSON array of messages.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/calls"
[ ! -e "$T/down" ] || exit 1
[ "\$2" != inbox ] || [ ! -e "$T/stall" ] || sleep 20
[ "\$2" != inbox ] || { jq -c '{ok: true, result: {messages: .}}' "$T/inbox"; exit; }
jq -Rn '{ok: true, result: {deliveryId: "dl_1", messages: [inputs | {from_handle: ., subject: "s", body: "b"}]}}' < "$T/batch"
EOF
chmod +x "$T/bin/orca-ide"
PROMPT='You have 2 orchestration messages. Run `orca orchestration check --run run_abc123`.'
# hook <dir> [prompt] -- the hook's output for that prompt in a pane of that checkout, the relay's handle set.
hook() { : > "$T/calls"; jq -n --arg p "${2:-$PROMPT}" --arg c "$1" '{prompt: $p, cwd: $c, hook_event_name: "UserPromptSubmit"}' \
  | (cd "$1" && env -u CLAUDE_PROJECT_DIR ORCA_TERMINAL_HANDLE="${HANDLE:-term_cos}" CLAUDE_CONFIG_DIR="$T/cfg" COMMANDECK_MAIN="$T/p" \
    COMMANDECK_SCRATCH="$T/sc" PATH="$T/bin:$PATH" bash "$HOOK" 2>/dev/null); }
calls() { grep -c -e "${1:-.}" "$T/calls" 2>/dev/null || true; }

printf 'term_cos\nterm_cos\n' > "$T/batch"
OUT=$(hook "$T/ws/Chief-of-Staff")
check "a batch all of this pane's own is dropped, naming the count" 'block:2' \
  "$(jq -r '.decision' <<<"$OUT" 2>/dev/null):$(jq -r '.reason' <<<"$OUT" 2>/dev/null | grep -o 'own [0-9]*' | cut -d' ' -f2)"
check "and acknowledged once, by its delivery, in the run the prompt names" 1 "$(calls '--run run_abc123 --ack dl_1 --peek')"
printf 'term_cos\nterm_main\n' > "$T/batch"
check "a batch with one message from another pane passes, unacknowledged" ':0' "$(hook "$T/ws/Chief-of-Staff"):$(calls '--ack')"
printf 'term_cos\n' > "$T/batch"
check "another prompt passes and asks Orca nothing" ':0' "$(hook "$T/ws/Chief-of-Staff" 'is u1 merged?'):$(calls)"
check "a prompt that only quotes the notice passes and asks Orca nothing" ':0' \
  "$(hook "$T/ws/Chief-of-Staff" "Why do I see: $PROMPT"):$(calls)"
check "the same prompt in a pane that is not the relay passes and asks Orca nothing" ':0' "$(hook "$T/ws/u1"):$(calls)"

# Issue 318, main's checkout: main spent a turn on every nudge, progress notes and its own echoes included (three
# recaps in 90 s). A nudge with nothing actionable unread is dropped, nothing acked, so the notes wait for the next
# real wake; actionable messages inside one window are held while main-watch runs, so they wake main once at its close;
# a wake that passes carries the silent-wake line. now = 100000; the default window is 60 s.
SILENT='Silent wake: if nothing in this wake needs the owner to act or decide, handle it and end the turn with no text to the owner.'
im() { jq -nc --arg id "$1" --arg t "$2" --arg f "$3" --arg to "$4" --argjson at "$5" \
  '{id: $id, type: $t, from_handle: $f, to_handle: $to, read: 0, subject: "s", created_at: ($at | todate)}'; }
inbox() { jq -sc . > "$T/inbox"; }
# Each case below is a fresh window: main woke for nothing before it, unless CLAIM keeps the last wake's claim.
mhook() { [ -n "${CLAIM:-}" ] || rm -f "$T/sc/main-watch/unread-since"; HANDLE=term_main COMMANDECK_NOW=${NOW:-100000} COMMANDECK_MAIN_WATCH_UP=${UP:-1} hook "$T/p" "$@"; }
{ im s1 status term_x run:run_abc123 99990; im s2 status term_main run:run_abc123 99000; im h1 heartbeat term_w run:run_abc123 99000
  im q0 question term_x run:run_abc123 90000 | jq -c '.read = 1'; im q9 question term_x run:run_other 90000; } | inbox
check "in the main checkout, a nudge for status notes only is dropped and nothing is acked" 'block:0:0' \
  "$(mhook | jq -r .decision 2>/dev/null):$(calls '--ack'):$(calls 'orchestration check')"
{ im q1 question term_x run:run_abc123 99990; im q2 question term_y run:run_abc123 100000; } | inbox
check "two questions 10 s apart inside the window: both nudges are held while main-watch runs" 'block:block' \
  "$(NOW=99990 mhook | jq -r .decision 2>/dev/null):$(mhook | jq -r .decision 2>/dev/null)"
check "and the first nudge at the window's close passes, with the silent-wake line" "$SILENT" "$(NOW=100050 mhook)"
for k in worker_done escalation question; do
  im k1 "$k" term_x run:run_abc123 99940 | inbox
  check "a $k past the window passes with the silent-wake line, and nothing is acked" "$SILENT:0" "$(mhook):$(calls '--ack')"
done
# Orca nudges for the same unread question again before main drains it, or main-watch typed its wake meanwhile:
# that is the wake already spent, so one claim per window serves both sources while main-watch runs.
check "a second nudge for the same question inside the window of the first wake is held" "$SILENT:block" \
  "$(mhook):$(CLAIM=1 NOW=100059 mhook | jq -r .decision 2>/dev/null)"
check "and one a window later passes" "$SILENT" "$(CLAIM=1 NOW=100060 mhook)"
mkdir -p "$T/sc/main-watch"; echo 100030 > "$T/sc/main-watch/unread-since"
check "a nudge after main-watch's own wake inside the window is held" block "$(CLAIM=1 mhook | jq -r .decision 2>/dev/null)"
check "but with main-watch down it passes" "$SILENT" "$(CLAIM=1 UP=0 mhook)"
# A stalled Orca must not hold the prompt: the inbox read is bounded (a timeout of 1 s here) and the nudge passes.
mkdir -p "$T/tbin"; printf '#!/usr/bin/env bash\nshift; exec %q 1 "$@"\n' "$(command -v timeout)" > "$T/tbin/timeout"; chmod +x "$T/tbin/timeout"
touch "$T/stall"; S0=$SECONDS
check "a stalled inbox read times out and the nudge passes, with the silent-wake line" "$SILENT:fast" \
  "$(PATH="$T/tbin:$PATH" mhook):$([ $((SECONDS - S0)) -lt 10 ] && echo fast || echo slow)"
rm "$T/stall"
im k2 question term_x run:run_abc123 100000 | inbox
check "with main-watch down, an actionable nudge passes at once" "$SILENT" "$(UP=0 mhook)"
check "and with a window of 0" "$SILENT" "$(COMMANDECK_OPTIONS='{"wakeWindowSeconds":0}' mhook)"
im k3 question term_main run:run_abc123 99900 | inbox
check "a question from main's own handle past the window passes" "$SILENT" "$(mhook)"
im k4 question term_x term_main 100000 | inbox
check "a question to main's terminal handle counts: held inside the window, passed after it" "block:$SILENT" \
  "$(mhook | jq -r .decision 2>/dev/null):$(NOW=100060 mhook)"
im k5 question term_x term_other 99000 | inbox
check "a question to another pane's handle does not wake main" block "$(mhook | jq -r .decision 2>/dev/null)"
check "main-watch's typed wake passes with the silent-wake line, asking Orca nothing" "$SILENT:0" \
  "$(mhook 'main-watch: items are waiting in your Orca inbox for run run_abc123; read them and handle each.'):$(calls)"
check "another prompt in the main checkout passes and asks Orca nothing" ':0' "$(mhook 'is u1 merged?'):$(calls)"
touch "$T/down"
check "Orca failing passes, with the silent-wake line" "$SILENT" "$(mhook)"
rm "$T/down"
check "the orca-ide spelling of the notice is the relay's echo too" block \
  "$(hook "$T/ws/Chief-of-Staff" 'You have 1 orchestration message. Run `orca-ide orchestration check --run run_abc123`.' | jq -r .decision 2>/dev/null)"
touch "$T/down"
check "Orca failing passes" "" "$(hook "$T/ws/Chief-of-Staff")"
rm "$T/down"; : > "$T/batch"
check "an empty batch passes, unacknowledged" ':0' "$(hook "$T/ws/Chief-of-Staff"):$(calls '--ack')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
