#!/usr/bin/env bash
# context_size must report the conversation's real size, not the size of one
# request that carried a transient payload. The numbers in case 3 are the real
# rows from main's transcript on 2026-09-13, when the Stop hook demanded a
# checkpoint at "336K" for a session that was actually at 170K.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
. "$ROOT/hooks/lib/context-size.sh"
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
pass=0; fail=0

row() { printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}}}\n' "$1" "$2" "$3"; }
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: expected $2, got $3" >&2; fi
}

# 1. A steady climb reports the last row.
F=$BOX/steady.jsonl; : > "$F"
row 2 621 157617 >> "$F"; row 2 984 158238 >> "$F"; row 2 835 164452 >> "$F"
check steady 165289 "$(context_size "$F")"

# 2. A lone spike is rejected in favour of the previous distinct value.
F=$BOX/spike.jsonl; : > "$F"
row 2 835 164452 >> "$F"; row 3185 1420 331994 >> "$F"
check spike 165289 "$(context_size "$F")"

# 3. The spike repeated by the streaming record is still rejected: dedupe runs
#    before the comparison, so four copies do not outvote the real value.
F=$BOX/spike-repeated.jsonl; : > "$F"
row 2 778 163674 >> "$F"; row 2 835 164452 >> "$F"
for _ in 1 2 3 4; do row 3185 1420 331994 >> "$F"; done
check spike-repeated 165289 "$(context_size "$F")"

# 4. Genuine growth under the reject line is accepted, so the hook still fires.
F=$BOX/growth.jsonl; : > "$F"
row 2 500 150000 >> "$F"; row 2 1000 180000 >> "$F"
check growth 181002 "$(context_size "$F")"

# 5. A single row is reported as-is: a fresh session has nothing to compare to.
F=$BOX/one.jsonl; : > "$F"; row 2 100 40000 >> "$F"
check single-row 40102 "$(context_size "$F")"

# 6a. The 3 MB tail can start mid-line. A cut usage line used to make jq stop
#     there and print nothing, so every gate fell back to bytes/4 (854K read
#     for a 270K session on 2026-09-27). The whole rows after it still count.
F=$BOX/cut-head.jsonl; : > "$F"
row 2 835 164452 | cut -c 30- >> "$F"; row 2 621 157617 >> "$F"; row 2 984 158238 >> "$F"
check cut-head 159224 "$(context_size "$F" || echo rc=$?)"

# 6. A transcript with no usage rows returns non-zero so callers can fall back.
F=$BOX/empty.jsonl; printf '{"type":"user"}\n' > "$F"
if context_size "$F" >/dev/null 2>&1; then fail=$((fail+1)); echo "FAIL no-usage: expected non-zero exit" >&2; else pass=$((pass+1)); fi

# 7. A missing file returns non-zero rather than printing a bogus number.
if context_size "$BOX/absent.jsonl" >/dev/null 2>&1; then fail=$((fail+1)); echo "FAIL absent: expected non-zero exit" >&2; else pass=$((pass+1)); fi

echo "context-size: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
