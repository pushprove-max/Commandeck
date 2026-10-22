#!/usr/bin/env bash
# context_size (hooks/lib/context-size.sh): the number the clear line, the ceiling and the worker budget gate on.
# Issue 267: Claude Code's auto-compact counts the last turn's output too, so a count without it ran below the
# point compaction acts on. The spike filter (a row far above the previous distinct one is a transient payload)
# still holds under the new count.
set -u
ROOT=$(git rev-parse --show-toplevel)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$ROOT/hooks/lib/context-size.sh"
row() { printf '{"message":{"usage":{"cache_read_input_tokens":%s,"input_tokens":1,"cache_creation_input_tokens":0,"output_tokens":%s}}}\n' "$1" "$2"; }
{ row 100000 500; row 120000 12000; } > "$T/t.jsonl"
check "the last turn's output tokens are counted" 132001 "$(context_size "$T/t.jsonl")"
{ row 160000 1000; row 163000 1000; row 336000 1000; } > "$T/spike.jsonl"
check "a row far above the previous one is still a transient payload" 164001 "$(context_size "$T/spike.jsonl")"
{ row 160000 1000; row 163000 1000; row 336000 1000; row 171000 1000; } > "$T/after.jsonl"
check "and the row after it is read" 172001 "$(context_size "$T/after.jsonl")"
# One request recorded twice while it streams, its output growing, is still one spike row.
{ row 163000 1000; row 336000 1000; row 336000 2000; } > "$T/stream.jsonl"
check "a spike recorded twice with growing output is still rejected" 164001 "$(context_size "$T/stream.jsonl")"
{ row 160000 1000; row 163000 1000; row 163000 4000; } > "$T/grow.jsonl"
check "a request recorded twice counts its last output" 167001 "$(context_size "$T/grow.jsonl")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
