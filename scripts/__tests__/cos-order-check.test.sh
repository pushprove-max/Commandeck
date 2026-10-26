#!/usr/bin/env bash
# cos-order-check.test.sh -- cos-order-check.sh, the check the Chief of Staff runs on an order file before it sends the
# file to main (issue 360). The relay once passed its own additions to main as if they were the owner's words, so main
# built scope the owner never asked for. What this pins: the shipped template passes; a file whose first section is not
# the owner's words is flagged, with or without that section further down; an addition under any heading but the
# NOT-ordered one is flagged; text before the first section is flagged; the NOT-ordered section alone after the
# owner's words passes.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
# chk <file text> -- the check's exit status and its output on one line.
chk() { printf '%s\n' "$1" > "$T/order.md"; local o; o=$(bash "$REAL/scripts/cos-order-check.sh" "$T/order.md" 2>&1); printf '%s|%s' "$?" "${o:+$(tr '\n' ';' <<<"$o")}"; }
W="## The owner's words" A="## Chief of Staff additions -- NOT ordered"
check "the shipped template passes" "0" "$(bash "$REAL/scripts/cos-order-check.sh" "$REAL/templates/cos-order.md" >/dev/null 2>&1; echo $?)"
check "an order with only the owner's words passes" "0|" "$(chk "$W

Fix the export bug. (ruling x)")"
check "an order with the NOT-ordered section after the owner's words passes" "0|" "$(chk "$W

Fix the export bug.

$A

Also rename the helper.")"
check "an order with an addition outside the NOT-ordered section is flagged" "1|line 5: \"## Also do\" is outside \"$A\";" \
  "$(chk "$W

Fix the export bug.

## Also do

Rename the helper.")"
check "an order file without the owner's-words section is flagged" "1|the first section is \"$A\", not \"$W\";" \
  "$(chk "$A

Rename the helper.")"
check "an order that starts with the additions, owner's words after, is flagged" "1|the first section is \"$A\", not \"$W\";" \
  "$(chk "$A

Rename the helper.

$W

Fix the export bug.")"
check "text before the first section is flagged" "1|line 1: text before the first section;" "$(chk "Please build this.

$W

Fix the export bug.")"
check "a file with no section is flagged" "1|line 1: text before the first section;no section: the file must start with \"$W\";" "$(chk "Fix the export bug.")"
check "a second owner's-words section is flagged" "1|line 5: a second \"$W\" section;" "$(chk "$W

Fix the export bug.

$W

Rename the helper.")"
check "a file that cannot be read exits 2" "2" "$(bash "$REAL/scripts/cos-order-check.sh" "$T/none.md" >/dev/null 2>&1; echo $?)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
