#!/usr/bin/env bash
# Main's notes to the relay went to its pane handle, a live-only mailbox: the
# relay later said none of main's recent reports had reached it. Pinned: a note
# sent with cos-tell.sh --note goes to main's run, waits there while the relay
# is busy, and its inbox watcher prints it at its next poll; a send Orca does
# not confirm as stored, or one with no run recorded, exits 1 and says so.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ws" "$T/scratch" "$T/home"
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
# Orca: a send to run:<id> is stored with its run and a sequence and answered with its message id, unless
# $T/live-only exists (then it answers the way a live-only mailbox does); the inbox lists what is stored.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "orchestration send") [ ! -e "$T/live-only" ] || { echo '{"ok":true,"result":{"warning":"live terminal-only mailbox, delivery is not durable"}}'; exit 0; }
    while [ \$# -gt 0 ]; do case \$1 in --run) r=\$2 ;; --to) to=\$2 ;; --subject) s=\$2 ;; --body) b=\$2 ;; --type) ty=\$2 ;; esac; shift; done
    n=\$(( \$(cat "$T/store.jsonl" 2>/dev/null | wc -l) + 1 ))
    jq -cn --argjson n \$n --arg r "\$r" --arg to "\$to" --arg s "\$s" --arg b "\$b" --arg t "\$ty" \
      '{sequence: \$n, run_id: \$r, from_handle: "term_main", to_handle: \$to, subject: \$s, body: \$b, type: \$t, created_at: "2026-10-15T10:00:00Z"}' >> "$T/store.jsonl"
    echo "{\"ok\":true,\"result\":{\"message\":{\"id\":\"msg_\$n\"}}}" ;;
  "orchestration run-list") echo '{"ok":true,"result":{"runs":[{"id":"run_1","coordinator_handle":"term_main"}]}}' ;;
  "orchestration inbox") jq -s '{ok: true, result: {messages: .}}' "$T/store.jsonl" 2>/dev/null || echo '{"ok":true,"result":{"messages":[]}}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
E=(env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch" PATH="$T/bin:$PATH")
note() { (cd "$T/p" && "${E[@]}" bash "$REAL/scripts/cos-tell.sh" --note "$1" "$2" 2>&1); }
watch() { (cd "$T/p" && "${E[@]}" COMMANDECK_WATCH_ONCE=1 bash "$REAL/scripts/cos-watch-inbox.sh" term_cos 2>&1); }

OUT=$(note "unit u1 merged" "u1 is on main"); RC=$?
check "with no run recorded the note is not sent, and says so" "1:1" "$RC:$(grep -c 'NOT sent: no run recorded' <<<"$OUT")"
check "and says only that: no shell error about the missing run file" 1 "$(grep -c . <<<"$OUT")"
echo run_1 > "$T/scratch/current-run"
note "first" "x" >/dev/null; watch >/dev/null   # the watcher's first poll marks what is already there as read
# The relay is busy: nothing polls while the note is sent.
OUT=$(note "unit u2 merged" "u2 is on main"); RC=$?
check "a note goes to main's run and is confirmed stored" "0:run:run_1" "$RC:$(jq -r 'select(.sequence == 2) | .to_handle' "$T/store.jsonl")"
check "and the relay's watcher prints it at its next poll" 1 "$(watch | grep -c 'unit u2 merged | u2 is on main')"
touch "$T/live-only"
OUT=$(note "unit u3 merged" "u3"); RC=$?
check "a send Orca does not confirm as stored exits 1 and says so" "1:1" "$RC:$(grep -c 'NOT sent: Orca did not confirm a stored message' <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
