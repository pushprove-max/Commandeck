#!/usr/bin/env bash
# A Builder's question to main is waited on by its own reply: the wait skips old unacknowledged mail,
# never takes another question's answer or a status that only carries the same title, ends at 9
# minutes however many calls it takes, and acknowledges the answer's batch so it is not shown twice.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ws"
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
# Orca: a send returns id msg_q1; the inbox is batches.jsonl, one {deliveryId, messages} per line, oldest first.
# A check replays the oldest batch unless --ack names it (and every batch before it), as the real one does; with
# nothing left it times out empty. Every check call is logged.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "terminal list") cat "$T/list.json" ;;
  "orchestration send") echo "\$*" >> "$T/sends.log"; echo '{"ok":true,"result":{"message":{"id":"msg_q1"}}}' ;;
  "orchestration check") echo "\$*" >> "$T/checks.log"
    ack=; while [ \$# -gt 0 ]; do [ "\$1" != --ack ] || ack=\$2; shift; done
    if [ -n "\$ack" ]; then
      [ "\$ack" != "\$(cat "$T/fail-ack" 2>/dev/null)" ] || exit 1
      n=\$(jq -s --arg a "\$ack" 'map(.deliveryId) | index(\$a) // -1' "$T/batches.jsonl" 2>/dev/null || echo -1)
      [ "\$n" -lt 0 ] || { tail -n +\$((n + 2)) "$T/batches.jsonl" > "$T/b.new"; mv "$T/b.new" "$T/batches.jsonl"; }
    fi
    b=\$(head -1 "$T/batches.jsonl" 2>/dev/null)
    if [ -n "\$b" ]; then jq -c '{ok: true, result: {deliveryId: .deliveryId, messages: .messages}}' <<<"\$b"
    else echo '{"ok":true,"result":{"messages":[],"timedOut":true}}'; fi ;;
  "terminal read") jq -Rn '{ok: true, result: {terminal: {tail: [inputs]}}}' "$T/screen" 2>/dev/null || echo '{"ok":true}' ;;
  "orchestration inbox") echo '{"ok":true}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
jq -n --arg p "$T/p" '{result: {terminals: [{handle: "term_main", worktreePath: $p, agentIdentity: "claude"}]}}' > "$T/list.json"
# batch <deliveryId> <thread_id|-> <subject> <body> -- append a one-message batch.
batch() { jq -cn --arg d "$1" --arg t "$2" --arg s "$3" --arg b "$4" \
  '{deliveryId: $d, messages: [{id: ("m" + $d), thread_id: (if $t == "-" then null else $t end), type: "status", subject: $s, body: $b, from_handle: "term_x"}]}' >> "$T/batches.jsonl"; }
E=(env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch" ORCA_TERMINAL_HANDLE=term_me PATH="$T/bin:$PATH")
mkdir -p "$T/scratch/handles"; echo term_main > "$T/scratch/handles/main"
ask() { (cd "$T/p" && "${E[@]}" bash "$REAL/scripts/ask-main.sh" "$@" 2>&1); }
at() { local t=$1; shift; (cd "$T/p" && "${E[@]}" COMMANDECK_ASK_MAIN_NOW="$t" bash "$REAL/scripts/ask-main.sh" "$@" 2>&1); }
reset() { rm -rf "$T/batches.jsonl" "$T/checks.log" "$T/sends.log" "$T/fail-ack" "$T/screen" "$T/scratch/ask-main"; }

reset
OUT=$(ask "which db" "sqlite or postgres?")
check "ask-main.sh sends through to-main.sh to main's resolved handle and prints the message id" "1:1" \
  "$(grep -c -- '--to term_main --type question --subject which db' "$T/sends.log"):$(grep -c 'id msg_q1' <<<"$OUT")"

reset; batch d1 - "old 1" "stale one"; batch d2 msg_other "Re: other" "another question's answer"; batch d3 - "answer from main" "an old status"; batch d4 msg_q1 "Re: which db" "use sqlite"
OUT=$(ask "which db" "sqlite or postgres?"); RC=$?
check "with three old unacknowledged messages in the inbox, the wait blocks until the reply threaded to the new question arrives, then prints that reply" "0:1" \
  "$RC:$(grep -c '^use sqlite$' <<<"$OUT")"

reset; printf 'Allow this command?\nEnter to select, Esc to cancel\n' > "$T/screen"; batch d1 msg_q1 "Re: q" "use sqlite"
OUT=$(ask "q" "b"); RC=$?
check "main's pane shows a prompt: the send's warning follows the id, and the wait still takes the answer" "0:1:1" \
  "$RC:$(grep -c 'open question or permission prompt' <<<"$OUT"):$(grep -c '^use sqlite$' <<<"$OUT")"

reset; batch d1 - "answer from main" "a status that only carries the title"
OUT=$(ask "q" "b"); RC=$?
check "a status titled answer from main with another thread_id is not taken for the answer" "3:0:1" \
  "$RC:$(grep -c '^a status that only carries the title$' <<<"$OUT"):$(grep -c 'no answer yet: resume with ask-main.sh --resume msg_q1' <<<"$OUT")"

reset; jq -cn '{deliveryId: "d1", messages: [{id: "ma", thread_id: null, type: "worker_done", subject: "unit done", body: "side news", from_handle: "term_w"}, {id: "mb", thread_id: "msg_q1", type: "status", subject: "Re: q", body: "the answer", from_handle: "term_main"}]}' >> "$T/batches.jsonl"
OUT=$(ask "q" "b")
check "a message from another sender in the same batch is printed under also in your inbox" "1:1" \
  "$(grep -c '^the answer$' <<<"$OUT"):$(grep -A1 '^also in your inbox:' <<<"$OUT" | grep -c 'side news')"

reset; batch d1 - "unrelated" "news"
OUT=$(at 1000 "q" "b"); RC=$?
check "slice 1 has no reply and exits 3" 3 "$RC"
batch d2 msg_q1 "Re: q" "the late answer"
OUT=$(at 1100 --resume msg_q1); RC=$?
check "the resume passes slice 1's deliveryId as --ack and the reply in slice 2 is printed" "0:1:1" \
  "$RC:$(grep -c '^the late answer$' <<<"$OUT"):$(grep -- '--wait' "$T/checks.log" | tail -1 | grep -c -- '--ack d1')"
reset; at 1000 "q" "b" >/dev/null; : > "$T/checks.log"
OUT=$(at 1541 --resume msg_q1); RC=$?
check "a resume whose stored deadline has passed prints the give-up line and makes no check call" "3:1:0" \
  "$RC:$(grep -c '^no answer in 9 minutes' <<<"$OUT"):$(wc -l < "$T/checks.log" | tr -d ' ')"

reset; at 1000 "q" "b" >/dev/null; at 1240 --resume msg_q1 >/dev/null; at 1480 --resume msg_q1 >/dev/null; at 1540 --resume msg_q1 >/dev/null
check "slice timeouts at the boundary: 240000, 240000 and 60000, and the fourth call makes no check call" "240000 240000 60000" \
  "$(grep -o 'timeout-ms [0-9]*' "$T/checks.log" | awk '{printf "%s%s", sep, $2; sep=" "}')"

reset; batch d1 msg_q1 "Re: q" "the answer"; batch d2 - "later" "queued behind it"
ask "q" "b" >/dev/null
check "after the answer, the batch is acked: the last check call carries --ack <the answer batch's deliveryId>, and the next read returns none of that batch" "1:1" \
  "$(tail -1 "$T/checks.log" | grep -c -- '--ack d1'):$(head -1 "$T/batches.jsonl" | grep -c '"d2"')"

reset; batch d1 msg_q1 "Re: q" "the answer"; echo d1 > "$T/fail-ack"
OUT=$(ask "q" "b"); RC=$?
check "a failed ack call prints the warning and still exits 0 with the answer" "0:1:1" \
  "$RC:$(grep -c '^the answer$' <<<"$OUT"):$(grep -c '^warning: the answer.s batch was not acknowledged' <<<"$OUT")"

reset; jq -n --arg p "$T/p" '{result: {terminals: []}}' > "$T/list.json"; rm -rf "$T/scratch/handles"
OUT=$(ask "q" "b"); RC=$?
check "main down: the question is queued and the line says the answer arrives typed" "3:1:0" \
  "$RC:$(grep -c 'answer is typed into your pane' <<<"$OUT"):$([ -e "$T/checks.log" ] && echo 1 || echo 0)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
