#!/usr/bin/env bash
# paths-cut-output.test.sh -- pp_cut_output (issue 608, DF10): a dump that #608's ranking names in a coordinator pane's
# top 10 is cut in the script that prints it. What this pins: past the cap the pane gets the head and one line naming
# the whole output's file (nothing is lost, only moved out of the pane); under the cap the pane gets every line and no
# file is left behind, so a short read costs nothing and the scratch folder does not fill with copies.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
cut_out() { (cd "$T" && env -u COMMANDECK_UNCUT HOME="$T/home" COMMANDECK_MAIN="$T" COMMANDECK_SCRATCH="$T/scratch" \
  bash -c '. "$1/scripts/paths.sh" && pp_cut_output dump' _ "$REAL"); }

# 100 lines of 60 bytes (6,100 bytes with newlines): over the cap.
for i in $(seq 1 100); do printf 'line %03d %s\n' "$i" "$(printf 'x%.0s' $(seq 1 51))"; done > "$T/big"
out=$(cut_out < "$T/big")
last=$(tail -1 <<<"$out"); file=$(sed -n 's/.*(whole: \(.*\))$/\1/p' <<<"$last")
check "dump over the cap is cut with a pointer to the whole file" "1:1:yes:same" \
  "$(grep -c '^dump: cut at 3,000 bytes (whole: ' <<<"$last"):$([ "$(head -n -1 <<<"$out" | wc -c)" -lt 2800 ] && echo 1 || echo 0):$([ -f "$file" ] && echo yes || echo no):$(cmp -s "$file" "$T/big" && echo same || echo differs)"

rm -rf "$T/scratch"; printf 'one\ntwo\nthree\n' > "$T/small"
out=$(cut_out < "$T/small")
check "output under the cap passes whole and saves no file" "same:0" \
  "$([ "$out" = "$(cat "$T/small")" ] && echo same || echo differs):$(ls "$T/scratch" 2>/dev/null | grep -c '^dump-')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
