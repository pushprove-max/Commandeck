#!/usr/bin/env bash
# A Builder's question to main is waited on by its own reply: the wait skips old unacknowledged mail,
# never takes another question's answer or a status that only carries the same title, ends at 9
# minutes however many calls it takes, and acknowledges the answer's batch so it is not shown twice.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
# The cases rewrite Orca's pane list between calls seconds apart: each lookup reads it fresh, not the 20 s stored map.
export PP_PANE_MAP_FRESH=1
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
  # --all: every message for the handle, read or not, with no batch and no ack (the full view); $T/extra.jsonl holds
  # messages only that view still shows (an answer whose batch was acknowledged without being printed).
  "orchestration check") echo "\$*" >> "$T/checks.log"; cat "$T/scratch/ask-main/"*.asking >> "$T/asking.log" 2>/dev/null
    case " \$* " in *" --all "*) { jq -c '.messages[]' "$T/batches.jsonl" 2>/dev/null; cat "$T/extra.jsonl" 2>/dev/null; } | jq -sc '{ok: true, result: {messages: ., count: length, acknowledged: null}}'; exit 0 ;; esac
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
reset() { rm -rf "$T/batches.jsonl" "$T/extra.jsonl" "$T/asking.log" "$T/checks.log" "$T/sends.log" "$T/fail-ack" "$T/screen" "$T/scratch/ask-main"; }

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
check "a resume whose stored deadline has passed prints the give-up line and does not wait again" "3:1:0" \
  "$RC:$(grep -c '^no answer in 9 minutes' <<<"$OUT"):$(grep -c -- --wait "$T/checks.log")"

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

# Issue 351. A call that has returned leaves its question's state file and no wait token (answer-worker.sh --interrupt
# types into a pane only while a call holds one). Main is up again for the cases below.
jq -n --arg p "$T/p" '{result: {terminals: [{handle: "term_main", worktreePath: $p, agentIdentity: "claude"}]}}' > "$T/list.json"; mkdir -p "$T/scratch/handles"; echo term_main > "$T/scratch/handles/main"
reset; at 1000 "q" "b" >/dev/null
check "the returned call keeps its question's state file and leaves no wait token" "msg_q1" "$(ls "$T/scratch/ask-main")"
# Ask 1: an answer whose batch was acknowledged without being printed is still in the full view; the resume takes it
# before it waits again, so main's answer is not lost to a batch that an earlier read swallowed.
jq -cn '{id: "mx", thread_id: "msg_q1", type: "status", subject: "Re: q", body: "the answer an earlier read swallowed", from_handle: "term_main"}' > "$T/extra.jsonl"
: > "$T/checks.log"
OUT=$(at 1100 --resume msg_q1); RC=$?
check "a resume takes an answer from the full inbox view before waiting, and forgets the question" "0:1:0:0" \
  "$RC:$(grep -c '^the answer an earlier read swallowed$' <<<"$OUT"):$(grep -c -- --wait "$T/checks.log"):$([ -e "$T/scratch/ask-main/msg_q1" ] && echo 1 || echo 0)"
reset; at 1000 "q" "b" >/dev/null
jq -cn '{id: "mx", thread_id: "msg_other", type: "status", subject: "Re: other", body: "another question", from_handle: "term_main"}' > "$T/extra.jsonl"
: > "$T/checks.log"
OUT=$(at 1100 --resume msg_q1); RC=$?
check "another question's reply in the full view is not taken: the resume waits as before" "3:0:1" \
  "$RC:$(grep -c '^another question$' <<<"$OUT"):$(grep -c -- --wait "$T/checks.log")"
# Ask 3: past the deadline, main hears once that the question is unanswered, so a lost answer is told from none.
reset; at 1000 "q" "b" >/dev/null; : > "$T/sends.log"
OUT=$(at 1541 --resume msg_q1); RC=$?
at 1600 --resume msg_q1 >/dev/null
check "past its deadline the question is reported to main once, however many calls follow" "3:1:1" \
  "$RC:$(grep -c 'no answer in 9 minutes' <<<"$OUT"):$(grep -c -- '--type question --subject ask-main: msg_q1 unanswered' "$T/sends.log")"
# The note names the answer route that still works past the deadline: the pane has ended its wait, so --interrupt would
# refuse it. answer-worker-interrupt.test.sh runs this command end to end.
check "the unanswered note gives main the plain answer-worker.sh command by its path, without --interrupt" "1:0" \
  "$(grep -cF "did not reach the pane: bash $REAL/scripts/answer-worker.sh term_me \"<answer>\" msg_q1" "$T/sends.log"):$(grep 'unanswered' "$T/sends.log" | grep -c -- '--interrupt')"
reset; at 1000 "q" "b" >/dev/null; : > "$T/sends.log"
jq -cn '{id: "mx", thread_id: "msg_q1", type: "status", subject: "Re: q", body: "a late answer", from_handle: "term_main"}' > "$T/extra.jsonl"
OUT=$(at 1541 --resume msg_q1); RC=$?
check "an answer found in the full view after the deadline is returned, and main is told nothing" "0:1:0" \
  "$RC:$(grep -c '^a late answer$' <<<"$OUT"):$(grep -c 'unanswered' "$T/sends.log")"

# A call keeps <id>.asking (pid= and pane=) from its first inbox wait until it returns, gaps between waits included:
# answer-worker.sh finds the question's thread there (issue 454). Two waits: an unrelated batch, then the answer.
reset; batch d1 - "other" "unrelated"; batch d2 msg_q1 "Re: q" "the answer"
OUT=$(ask "q" "b"); RC=$?
check "a waiting call names its pane in <id>.asking at each inbox read and leaves none once it returns" "0:2:1:" \
  "$RC:$(grep -c -- --wait "$T/checks.log"):$(( $(grep -cx 'pane=term_me' "$T/asking.log") == $(wc -l < "$T/checks.log") )):$(ls "$T/scratch/ask-main" | paste -sd' ' -)"

# Issue 588 (D23): Orca 1.4.246's check without --full drops body, thread_id and from_handle from each message (and
# dispatchId from the result). A stand-in in front of the stub gives that concise view: the answer still reaches the asker.
mkdir -p "$T/cbin"
cat > "$T/cbin/orca-ide" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *" orchestration check "*" --full "*|*" --full "*" orchestration check "*) exec "$T/bin/orca-ide" "\$@" ;;
  *" orchestration check "*) "$T/bin/orca-ide" "\$@" | jq -c 'del(.result.dispatchId) | .result.messages |= map(del(.body, .thread_id, .from_handle))' ;;
  *) exec "$T/bin/orca-ide" "\$@" ;;
esac
EOF
chmod +x "$T/cbin/orca-ide"
reset; batch d1 msg_q1 "Re: q" "the answer only the full view carries"
OUT=$(cd "$T/p" && "${E[@]}" PATH="$T/cbin:$T/bin:$PATH" bash "$REAL/scripts/ask-main.sh" "q" "b" 2>&1); RC=$?
check "ask-main prints an answer only Orca's full check view carries (issue 588)" "0:1" \
  "$RC:$(grep -c '^the answer only the full view carries$' <<<"$OUT")"

# Issue 639: another reader on this pane (a stray watcher) took main's reply and Orca marked it read, so the wait's own
# check never returns it. The wait finds it in the full view by its thread id after a pass with no reply; a read reply
# to another question is never taken for this one.
reset; batch d1 - "other" "unrelated"
jq -cn '{id: "mr", thread_id: "msg_q1", type: "reply", subject: "Re: q", body: "taken by a stray watcher", from_handle: "term_main", read: 1}' > "$T/extra.jsonl"
OUT=$(ask "q" "b"); RC=$?
check "reply marked read by another reader still arrives" "0:1:1" \
  "$RC:$(grep -c '^taken by a stray watcher$' <<<"$OUT"):$(grep -c -- --wait "$T/checks.log")"
reset
jq -cn '{id: "mr", thread_id: "msg_other", type: "reply", subject: "Re: other", body: "another question read elsewhere", from_handle: "term_main", read: 1}' > "$T/extra.jsonl"
OUT=$(at 1000 "q" "b"); RC=$?
check "another question's read reply is not taken" "3:0:1" \
  "$RC:$(grep -c 'another question read elsewhere' <<<"$OUT"):$([ -e "$T/scratch/ask-main/msg_q1" ] && echo 1 || echo 0)"
# Issue 638: main runs in another checkout (a host project's): no recorded handle, no pane in this one. It is the
# coordinator of the run this checkout is bound to, the pane main-watch wakes: the question reaches it and the call waits.
mkdir -p "$T/rbin" "$T/host"
cat > "$T/rbin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "orchestration run-list") jq -n '{ok: true, result: {runs: [{id: "run_c", coordinator_handle: "term_host"}]}}' ;;
  *) exec "$T/bin/orca-ide" "\$@" ;;
esac
EOF
chmod +x "$T/rbin/orca-ide"
reset; rm -rf "$T/scratch/handles" "$T/scratch/pane-map.json"; echo run_c > "$T/scratch/current-run"
jq -n --arg h "$T/host" '{result: {terminals: [{handle: "term_host", worktreePath: $h, agentIdentity: "claude"}]}}' > "$T/list.json"
batch d1 msg_q1 "Re: q" "the host main's answer"
OUT=$(cd "$T/p" && "${E[@]}" PATH="$T/rbin:$T/bin:$PATH" bash "$REAL/scripts/ask-main.sh" "q" "b" 2>&1); RC=$?
check "main found only as run coordinator gets the question" "0:1:1" \
  "$RC:$(grep -c -- '--to term_host --type question' "$T/sends.log"):$(grep -c "^the host main's answer$" <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
