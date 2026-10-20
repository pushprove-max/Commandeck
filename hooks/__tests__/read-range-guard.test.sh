#!/usr/bin/env bash
# Issue 247: a Builder that reads a long file whole carries every line of it on every later turn of the build.
# What this pins: in a Builder, an unranged Read of a file over 400 lines is refused with a range to read; a ranged
# Read, a short file, a subagent and a seat that is no Builder pass.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/read-range-guard.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
seq 500 > "$T/long.txt"; seq 100 > "$T/short.txt"
# read <tool_input json> [extra payload json] -- the hook's exit code in a Builder, its message in $T/err
read_() { jq -cn --argjson i "$1" --argjson x "${2:-{\}}" '{tool_name: "Read", tool_input: $i} + $x' \
  | COMMANDECK_BUILDER=1 bash "$HOOK" 2>"$T/err"; echo $?; }
check "an unranged Read of a 500-line file is refused" 2 "$(read_ "{\"file_path\": \"$T/long.txt\"}")"
check "the refusal names the file's length and a range to read" "1 1" \
  "$(grep -c '500 lines' "$T/err") $(grep -c 'offset 1, limit 200' "$T/err")"
check "a ranged Read of it passes, by offset or by limit" "0 0" \
  "$(read_ "{\"file_path\": \"$T/long.txt\", \"offset\": 100, \"limit\": 50}") $(read_ "{\"file_path\": \"$T/long.txt\", \"limit\": 50}")"
check "a 100-line file passes whole" 0 "$(read_ "{\"file_path\": \"$T/short.txt\"}")"
check "a subagent's Read passes" 0 "$(read_ "{\"file_path\": \"$T/long.txt\"}" '{"agent_id": "a1"}')"
check "a seat that is no Builder passes" 0 \
  "$(jq -cn --arg f "$T/long.txt" '{tool_name: "Read", tool_input: {file_path: $f}}' | env -u COMMANDECK_BUILDER bash "$HOOK" 2>/dev/null; echo $?)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
