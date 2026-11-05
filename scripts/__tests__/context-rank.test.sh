#!/usr/bin/env bash
# context-rank.test.sh -- context-rank.sh (issue 608): the coordinator panes fill with tool output nobody measured, so
# the removals (CF3 wakes, pp_cut_output) must follow a ranked table, not a guess. What this pins: the bytes of each
# tool result are charged to the key of the tool_use that the result's id matches (tool name, plus the script basename
# for Bash), summed per key and listed largest first with its count and share of all result bytes.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
R() { bash "$REAL/scripts/context-rank.sh" "$@"; }
use() { jq -cn --arg id "$1" --arg name "$2" --argjson input "$3" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:$name,input:$input}]}}'; }
res() { jq -cn --arg id "$1" --argjson n "$2" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:("x" * $n)}]}}'; }

# Two Bash scripts and a Read. board.sh is called twice (200 + 100 bytes), dump.sh once (1000), Read once (50): a key
# is the tool plus the script, so the two Bash scripts must not merge, and a bigger single result outranks a smaller sum.
{
  use t1 Bash '{"command":"bash /p/scripts/board.sh --full"}'; res t1 200
  use t2 Bash '{"command":"bash /p/scripts/dump.sh"}'; res t2 1000
  use t3 Read '{"file_path":"/p/README.md"}'; res t3 50
  use t4 Bash '{"command":"bash /p/scripts/board.sh"}'; res t4 100
} > "$T/s.jsonl"

out=$(R "$T/s.jsonl" | grep "$(printf '\tresult\t')")
check "tool result bytes are ranked by tool key" \
  "$(printf '1000\t1\t74.1\tresult\tBash dump.sh\n300\t2\t22.2\tresult\tBash board.sh\n50\t1\t3.7\tresult\tRead')" \
  "$out"

# A log that cannot be read must stop the rank with its name: a table built from the rest would rank a pane by part of
# its context and look whole.
out=$(R "$T/s.jsonl" "$T/missing.jsonl" 2>&1); rc=$?
check "unreadable log is named not skipped" "1:1:0" \
  "$rc:$(grep -c "cannot read log: $T/missing.jsonl" <<<"$out"):$(grep -c "$(printf '\tresult\t')" <<<"$out")"

# Inbound messages (a watcher's or the checker's line typed into the pane) are keyed by their first words, so the
# routine wakes CF3 holds show as one row each, summed, not as one row per message.
msg() { jq -cn --arg t "$1" '{type:"user",message:{role:"user",content:$t}}'; }
{ msg "cos-check: 2 watchers down"; msg "cos-check: 1 missed message"; msg "main-watch: Builder u1 stopped"; } > "$T/m.jsonl"
out=$(R "$T/m.jsonl" | grep "$(printf '\tmessage\t')" | cut -f2,5)
check "inbound messages are ranked by first words" "$(printf '2\tcos-check:\n1\tmain-watch:')" "$out"

# A real Claude log carries rows with no message (`cost-state`, `summary`): one of them before a tool call stopped the
# whole rank with a jq error, so the live measure of main's pane printed nothing.
{ use t5 Bash '{"command":"bash /p/scripts/board.sh"}'; echo '{"type":"cost-state","totalCostUSD":1}'; res t5 70; } > "$T/c.jsonl"
out=$(R "$T/c.jsonl" 2>&1); rc=$?
check "a row with no message is skipped, not fatal" "0:1" "$rc:$(grep -c "$(printf '70\t1\t100\tresult\tBash board.sh')" <<<"$out")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
