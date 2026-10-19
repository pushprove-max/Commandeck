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
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/calls"
[ ! -e "$T/down" ] || exit 1
jq -Rn '{ok: true, result: {deliveryId: "dl_1", messages: [inputs | {from_handle: ., subject: "s", body: "b"}]}}' < "$T/batch"
EOF
chmod +x "$T/bin/orca-ide"
PROMPT='You have 2 orchestration messages. Run `orca orchestration check --run run_abc123`.'
# hook <dir> [prompt] -- the hook's output for that prompt in a pane of that checkout, the relay's handle set.
hook() { : > "$T/calls"; jq -n --arg p "${2:-$PROMPT}" --arg c "$1" '{prompt: $p, cwd: $c, hook_event_name: "UserPromptSubmit"}' \
  | (cd "$1" && env -u CLAUDE_PROJECT_DIR ORCA_TERMINAL_HANDLE=term_cos PATH="$T/bin:$PATH" bash "$HOOK" 2>/dev/null); }
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
check "and in the main checkout" ':0' "$(hook "$T/p"):$(calls)"
check "the orca-ide spelling of the notice is the relay's echo too" block \
  "$(hook "$T/ws/Chief-of-Staff" 'You have 1 orchestration message. Run `orca-ide orchestration check --run run_abc123`.' | jq -r .decision 2>/dev/null)"
touch "$T/down"
check "Orca failing passes" "" "$(hook "$T/ws/Chief-of-Staff")"
rm "$T/down"; : > "$T/batch"
check "an empty batch passes, unacknowledged" ':0' "$(hook "$T/ws/Chief-of-Staff"):$(calls '--ack')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
