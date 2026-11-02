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
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
