#!/usr/bin/env bash
# Issue 331: the relay's inbox watcher wakes its pane by exiting, and until now left no trace of it. Pinned: an exit with
# a message for the relay writes one woke line to the wake log; a poll that finds nothing writes none; an inbox Orca
# does not answer writes one refused line for the outage (a poll is every 20 s), and another for the next outage.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ws" "$T/scratch" "$T/home"
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
echo run_1 > "$T/scratch/current-run"; : > "$T/store.jsonl"
# Orca: the inbox lists $T/store.jsonl, and fails while $T/down exists; main's pane is the run's coordinator.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "orchestration inbox") [ ! -e "$T/down" ] || { echo '{"ok":false}'; exit 1; }
    jq -s '{ok: true, result: {messages: .}}' "$T/store.jsonl" 2>/dev/null || echo '{"ok":true,"result":{"messages":[]}}' ;;
  "orchestration run-list") echo '{"ok":true,"result":{"runs":[{"id":"run_1","coordinator_handle":"term_main"}]}}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
E=(env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch" PATH="$T/bin:$PATH")
watch() { (cd "$T/p" && "${E[@]}" COMMANDECK_WATCH_ONCE=1 bash "$REAL/scripts/cos-watch-inbox.sh" term_cos 2>&1); }
row() { jq -cn --argjson n $(( $(wc -l < "$T/store.jsonl") + 1 )) --arg f "$1" --arg to "$2" --arg t "$3" --arg s "$4" \
  '{sequence: $n, run_id: "run_1", from_handle: $f, to_handle: $to, subject: $s, body: "b", type: $t, created_at: "2026-10-15T10:00:00Z"}' >> "$T/store.jsonl"; }
WLJ=$T/scratch/wake-log.jsonl
logged() { jq -rs '[.[] | select(.from == "cos-watch-inbox") | .result] | join(",")' "$WLJ" 2>/dev/null; }

row term_main run:run_1 question "an old note"; watch >/dev/null   # the first poll marks what is there as read
check "the first poll finds nothing new and writes no line" "" "$(logged)"
row term_main run:run_1 question "0.9.0 is ready. OK to release?"
OUT=$(watch); RC=$?
check "a poll with a message for the relay exits 0, printing it" "0:1" "$RC:$(grep -c 'OK to release?' <<<"$OUT")"
check "and the exit writes one woke line" "woke" "$(logged)"
watch >/dev/null; RC=$?
check "a poll that finds nothing exits 1 and writes no line" "1:woke" "$RC:$(logged)"
touch "$T/down"; watch >/dev/null; watch >/dev/null
check "an inbox Orca does not answer writes one refused line, however many polls fail" "woke,refused" "$(logged)"
rm -f "$T/down"; watch >/dev/null
touch "$T/down"; watch >/dev/null
check "and the next outage, after a poll that read, writes its own" "woke,refused,refused" "$(logged)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
