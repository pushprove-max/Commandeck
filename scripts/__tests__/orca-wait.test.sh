#!/usr/bin/env bash
# orca-wait.sh hides what its noise rules match, and once that was a real owner answer: the relay's "turn complete"
# echo carrying it had no marker, so main never saw it and nothing kept it. Pinned: a message citing a ruling id, or
# from the relay's pane (listed by Orca with only a worktreeId), always shows, even when it is "own" traffic; a plain
# echo is still hidden, but kept in hidden.jsonl, which the summary line names; a heartbeat is not kept.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
WS=$T/ws; mkdir -p "$T/bin" "$T/home" "$WS/Chief-of-Staff"
git init -q -b main "$T/p"
msg() { jq -nc --arg id "$1" --arg f "$2" --arg t "$3" --arg s "$4" --arg b "$5" '{id: $id, from_handle: $f, type: $t, subject: $s, body: $b}'; }
{ msg m1 term_cos status "turn complete" "Owner says proceed"
  msg m2 term_w status "turn complete" "the owner ruled r-19991017-101010-1-a1b2c3"
  msg m3 term_cos status "relay note" "plain words from the relay"
  msg m4 term_w status "turn complete" "just chatter"
  msg m5 term_w heartbeat "alive" ""; } | jq -sc '{ok: true, result: {deliveryId: "d1", messages: .}}' > "$T/batch.json"
# Orca: the first check answers the batch, an ack answers nothing more; the relay's pane has only a worktreeId.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"orchestration check"*"--ack"*) echo '{"ok":true,"result":{"messages":[]}}' ;;
  *"orchestration check"*) cat "$T/batch.json" ;;
  *"terminal list"*) jq -nc --arg w "id::$WS/Chief-of-Staff" '{ok: true, result: {terminals: [{handle: "term_cos", worktreeId: \$w}]}}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
OUT=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_SCRATCH="$T/sc" ORCA_TERMINAL_HANDLE=term_cos timeout 30 bash "$REAL/scripts/orca-wait.sh" 2>&1)
HID=$T/sc/main-watch/messages/hidden.jsonl
check "the relay pane's plain 'turn complete' echo, with no ruling id, is shown" 1 "$(grep -c '| Owner says proceed' <<<"$OUT")"
check "an echo with no marker that cites a ruling id is shown" 1 "$(grep -c '| the owner ruled r-19991017-101010-1-a1b2c3' <<<"$OUT")"
check "the relay pane's status, which the own-status rule would drop, is shown" 1 "$(grep -c '| plain words from the relay' <<<"$OUT")"
check "a plain echo is hidden" 0 "$(grep -c 'just chatter' <<<"$OUT")"
check "the summary names hidden.jsonl, which holds the echo and not the heartbeat" "1 m4" \
  "$(grep -c "all but heartbeats are kept in $HID" <<<"$OUT") $(jq -r .id "$HID" 2>/dev/null | paste -sd, -)"
# A batch too big for one argument (twelve 100,000-character questions, ~1.2 MB) must still show and be acknowledged:
# passing it to jq as an argument failed E2BIG, so the drain exited unacked and every retry hit the same batch.
BIG=$(head -c 100000 /dev/zero | tr '\0' x)
for i in $(seq 1 12); do msg "q$i" term_w question "big $i" "$BIG"; done | jq -sc '{ok: true, result: {deliveryId: "d2", messages: .}}' > "$T/batch.json"
rm -rf "$T/sc"
OUT=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_SCRATCH="$T/sc" ORCA_TERMINAL_HANDLE=term_cos timeout 60 bash "$REAL/scripts/orca-wait.sh" 2>&1); RC=$?
check "a 1.2 MB batch drains: exit 0, all twelve bodies saved whole" "0 12" \
  "$RC $(for i in $(seq 1 12); do f=$T/sc/main-watch/messages/q$i.md; [ -f "$f" ] && [ "$(wc -c < "$f" | tr -d ' ')" = 100000 ] && echo y; done | wc -l | tr -d ' ')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
