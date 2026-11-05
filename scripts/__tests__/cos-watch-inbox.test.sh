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
# Each row carries the relay's recipient tag, as cos-tell.sh --note sends it (issue 643: the relay admits only those).
row() { jq -cn --argjson n $(( $(wc -l < "$T/store.jsonl") + 1 )) --arg f "$1" --arg to "$2" --arg t "$3" --arg s "$4" \
  '{sequence: $n, run_id: "run_1", from_handle: $f, to_handle: $to, subject: $s, body: "b", type: $t, created_at: "2026-10-15T10:00:00Z", payload: "{\"to\":\"chief-of-staff\"}"}' >> "$T/store.jsonl"; }
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
rm -f "$T/down"

# Pass 3: Orca's repeat of main's reply A, dropped by the wake rule, is no new reply from main: the owner's question
# marked owed after A (to-main.sh's mark) stays owed, so the relay keeps its unanswered-question wake.
# rowat <sent at> <row's arguments> -- one message, sent at that time.
rowat() { row "${@:2}"; jq -c --arg at "$1" --argjson n "$(wc -l < "$T/store.jsonl")" 'if .sequence == $n then .created_at = $at else . end' \
  "$T/store.jsonl" > "$T/store.new" && mv "$T/store.new" "$T/store.jsonl"; }
rowat 2026-11-04T10:00:00Z term_main run:run_1 status "Answer A"; watch >/dev/null
printf '%s\tnew question\n' "$(python3 -c 'import datetime; print(int(datetime.datetime(2026, 11, 4, 10, 1, tzinfo=datetime.timezone.utc).timestamp()))')" > "$T/scratch/cos-owed"
rowat 2026-11-04T10:02:00Z term_main run:run_1 status "Answer A"; OUT=$(watch)
check "a dropped repeat of main's reply keeps a newer owed question" "0:kept" \
  "$(grep -c '"Answer A"' <<<"$OUT"):$([ -e "$T/scratch/cos-owed" ] && echo kept || echo gone)"

# Issue 614: a lane (Fast-lane, Research-lane) is not the relay. Mail to its own handle wakes it, but a routine FYI note
# is held (each wake replays the pane's whole context) and prints with the next wake. The relay's rule that one sent to
# the pane's own handle is never held stays the relay's.
KEY=$(cd "$T/p" && "${E[@]}" bash -c '. "$1/hooks/lib/project.sh"; pp_cos_key; printf %s "$COS_KEY"' _ "$REAL")
mkdir -p "${KEY%/*}"; printf '0 enc\n' > "$KEY.lane-fast-lane.inbox-seq"
markread() { jq -c --arg s "$1" 'if .subject == $s then . + {read: 1} else . end' "$T/store.jsonl" > "$T/s.new" && mv "$T/s.new" "$T/store.jsonl"; }
lane() { (cd "$T/p" && "${E[@]}" COMMANDECK_WATCH_ONCE=1 bash "$REAL/scripts/cos-watch-inbox.sh" term_lane --lane fast-lane 2>&1); }
row term_main term_lane status "FYI lane note"
OUT=$(lane); RC=$?
check "lane FYI note stays held" "1:0" "$RC:$(grep -c 'FYI lane note' <<<"$OUT")"
row term_main term_lane question "lane order"
# pass 3: an order Orca already marks read is not replayed on any poll, also behind an unread one (it ran twice).
row term_main term_lane question "handled order"; markread "handled order"
OUT=$(lane); RC=$?
check "and prints under the held header with the next wake" "0:1:1:0" "$RC:$(grep -c 'lane order' <<<"$OUT"):$(grep -c 'HELD FYI NOTES' <<<"$OUT"):$(grep -c 'handled order' <<<"$OUT")"

# a lane's first poll delivers its unread order (pass 1): with no place saved yet, the first poll saved the newest
# row and printed nothing, so an order sent before the lane's first Stop was passed over for good. A row already read,
# or one to another pane, is not replayed.
rm -f "$KEY.lane-research.inbox-seq"
row term_main term_other question "not this lane's"
row term_main term_lane2 question "old read order"; markread "old read order"
row term_main term_lane2 question "first lane order"
row term_main term_lane2 question "later read order"; markread "later read order"
OUT=$( (cd "$T/p" && "${E[@]}" COMMANDECK_WATCH_ONCE=1 bash "$REAL/scripts/cos-watch-inbox.sh" term_lane2 --lane research 2>&1) ); RC=$?
check "a lane's first poll delivers its unread order" "0:1:0:0:0" \
  "$RC:$(grep -c 'first lane order' <<<"$OUT"):$(grep -c 'old read order' <<<"$OUT"):$(grep -c "not this lane's" <<<"$OUT"):$(grep -c 'later read order' <<<"$OUT")"

# The lane's fence is Orca's read flag on every poll, not its place (pass 2 design, pass 3 red: a read order behind an
# unread one ran again). Tick 1 cannot show its batch, then one piece of state is lost before tick 2, each
# in its own lane: tick 2 shows both unread orders, and no read one or another pane's, whichever piece went.
row term_main term_fence question "fence read A"; markread "fence read A"
row term_main term_fence question "fence order A"
row term_main term_fence question "fence read B"; markread "fence read B"
row term_main term_fence question "fence order B"
row term_main term_other question "fence other pane"
# The shim fails the show inside the poller: its batch goes to the wake file, so only Python's own stdout can fail.
PY=$(command -v python3); printf '#!/usr/bin/env bash\n[ -z "${FAIL_SHOW-}" ] || exec "%s" "$@" >/dev/full\nexec "%s" "$@"\n' "$PY" "$PY" > "$T/bin/python3"
chmod +x "$T/bin/python3"
GOT=
for lost in inbox-seq inbox-seq.lock inbox-seen-ids stray.new; do
  fl() { (cd "$T/p" && "${E[@]}" ${FAIL_SHOW:+FAIL_SHOW=1} COMMANDECK_WATCH_ONCE=1 bash "$REAL/scripts/cos-watch-inbox.sh" term_fence --lane "f-$lost" 2>/dev/null); }
  FAIL_SHOW=1 fl >/dev/null
  case $lost in stray.new) echo junk > "$KEY.lane-f-$lost.inbox-seq.new" ;; *) rm -f "$KEY.lane-f-$lost.$lost" ;; esac
  OUT=$(fl)
  GOT+="$lost:$(grep -c 'fence order' <<<"$OUT"):$(grep -c 'fence read' <<<"$OUT"):$(grep -c 'fence other' <<<"$OUT") "
done
check "a lane delivers every unread order and no read one, whatever state is lost" \
  "inbox-seq:2:0:0 inbox-seq.lock:2:0:0 inbox-seen-ids:2:0:0 stray.new:2:0:0 " "$GOT"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
