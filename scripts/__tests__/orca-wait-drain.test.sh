#!/usr/bin/env bash
# Issue 571 (partial): a main-watch item for a merge that landed is done once it is posted, so the wake closes its task and
# leaves it out of the task listing. Every other open task stays: a failure, stall, question or seat-finished item
# (main-watch re-posts open items) and every dispatch task. covers: scripts/orca-wait.sh
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home" "$T/ws"; git init -q -b main "$T/p"
LAND='main-watch item: main-watch: u1 merged into local main at abc1234. Nothing more to do.'
jq -nc --arg land "$LAND" '{ok: true, result: {tasks: [
  {id: "t_land", status: "pending", spec: $land},
  {id: "t_fail", status: "pending", spec: "main-watch item: main-watch: u2 failed: the check is red"},
  {id: "t_stall", status: "pending", spec: "main-watch item: main-watch: u3 stalled for 30 minutes"},
  {id: "t_done", status: "pending", spec: "main-watch item: main-watch: u4 seat finished"},
  {id: "t_quote", status: "pending", spec: ("main-watch item: main-watch: u5 failed; " + $land)},
  {id: "t_dispatch", status: "pending", spec: "Build unit u6 per its brief"},
  {id: "t_empty", status: "pending", spec: ""},
  {id: "t_old", status: "completed", spec: $land}]}}' > "$T/tasks.json"
jq -nc '{ok: true, result: {deliveryId: "d1", messages: [{id: "m1", from_handle: "term_w", type: "question", subject: "turn complete: QUESTION", body: "which one?"}]}}' > "$T/batch.json"
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"orchestration check"*"--ack"*) echo '{"ok":true,"result":{"messages":[]}}' ;;
  *"orchestration check"*) cat "$T/batch.json" ;;
  *"orchestration inbox"*) cat "$T/page.json" 2>/dev/null || echo '{"ok":true}' ;;
  *"orchestration task-list"*) cat "$T/tasks.json" ;;
  *"orchestration task-update"*) echo "\$*" >> "$T/updates"; echo '{"ok":true}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
wake() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/sc" ORCA_TERMINAL_HANDLE=term_main timeout 60 bash "$REAL/scripts/orca-wait.sh" "$@" 2>&1); }
OUT=$(wake --full)
closed() { grep -o -- '--id [a-z_]*' "$T/updates" 2>/dev/null | cut -d' ' -f2 | sort | tr '\n' ' '; }
check "a read merge-landed item's task closes on the wake" "t_land " "$(closed)"
check "and is not in the task listing" "0" "$(grep -c 'task t_land' <<<"$OUT")"
check "a failure, stall or seat-finished item's task stays open after the wake" "1 1 1 1" \
  "$(grep -c 'task t_fail' <<<"$OUT") $(grep -c 'task t_stall' <<<"$OUT") $(grep -c 'task t_done' <<<"$OUT") $(grep -c 'task t_quote' <<<"$OUT")"
check "a Builder dispatch task never closes on the wake" "t_dispatch t_empty" \
  "$(grep -c 'task t_dispatch' <<<"$OUT" | sed 's/1/t_dispatch/') $(grep -c 'task t_empty' <<<"$OUT" | sed 's/1/t_empty/')"
: > "$T/updates"; echo '{"ok":false}' > "$T/tasks.json"; OUT=$(wake --full)
check "an absent or junk task-list closes nothing" "0" "$(grep -c . "$T/updates")"
# Issue 642: the drain classes each row by the one wake rule against the inbox page (read rows included). An OK status
# is shown under held notes and starts main's 30-minute batch clock; the same question again within 10 minutes, even
# one main read and acked a delivery ago, is a repeat: kept in hidden.jsonl, never printed or woken for again.
N0=1800000000
# m <id> <type> <subject> <at> [read] -- the one inbox row builder for these cases.
m() { jq -nc --arg id "$1" --arg t "$2" --arg s "$3" --argjson at "$4" --argjson rd "${5:-0}" '{id: $id, from_handle: "term_w", to_handle: "run:r",
  type: $t, subject: $s, body: "b", read: $rd, created_at: ($at | todate)}'; }
batch() { jq -sc '{ok: true, result: {deliveryId: "d2", messages: .}}' > "$T/batch.json"; }
page() { jq -sc '{ok: true, result: {messages: .}}' > "$T/page.json"; }
{ m a1 question 'which file?' "$N0"; m s1 status 'tests: exit 0' "$N0"; } | batch; { m a1 question 'which file?' "$N0"; m s1 status 'tests: exit 0' "$N0"; } | page
OUT=$(COMMANDECK_NOW=$N0 wake)
check "drain sets batch clock" "$N0" "$(cat "$T/sc/main-watch/batch-at" 2>/dev/null)"
check "drain shows batch held" "1 1" "$(sed '/^held notes/,$d' <<<"$OUT" | grep -c '| which file?') $(sed -n '/^held notes/,$p' <<<"$OUT" | grep -c '| tests: exit 0')"
HID=$T/sc/main-watch/messages/hidden.jsonl; : > "$HID"
{ m a2 question 'which file?' $((N0 + 300)); m b1 question 'merge u7?' $((N0 + 300)); } | batch
{ m a1 question 'which file?' "$N0" 1; m s1 status 'tests: exit 0' "$N0" 1; m a2 question 'which file?' $((N0 + 300)); m b1 question 'merge u7?' $((N0 + 300)); } | page
OUT=$(COMMANDECK_NOW=$((N0 + 300)) wake)
# The clock stays at the first drain's time: a drain with no held note sets none.
check "acked question repeat dropped later" "0 1 a2 $N0" "$(grep -c '| which file?' <<<"$OUT") $(grep -c '| merge u7?' <<<"$OUT") $(jq -r .id "$HID" 2>/dev/null | paste -sd' ' -) $(cat "$T/sc/main-watch/batch-at" 2>/dev/null)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
