#!/usr/bin/env bash
# drift-guard-template.test.sh -- templates/drift-guard-example.sh (issue 516) is the worked example of the rule in
# templates/rules-details.md: a drift guard fails when two copies of one fact disagree, and says which two. The example
# is run here so the template itself is tested, not only described.
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P)
PASS=0 FAIL=0
trap 'rm -rf "$T"' EXIT
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
EX=$SOURCE/templates/drift-guard-example.sh
cd "$T" || exit 1
echo 'Retry limit: 3' > a.md; echo 'Retry limit: 5' > b.md; echo 'Retry limit: 3' > c.md

# Catches: a guard that passes when the copies differ, or fails without saying which two files drifted.
bash "$EX" a.md b.md > out 2>&1; RC=$?
DIFF="$RC $(grep -c 'a\.md' out) $(grep -c 'b\.md' out)"
# Catches: a guard that fails on copies that agree, so nobody trusts its red.
bash "$EX" a.md c.md > out 2>&1
check "the example fails on two copies that differ" "1 1 1|0" "$DIFF|$?"
# Catches: a rule that names a drift guard but no longer points at the runnable example.
check "the rules carry the section" "1 1" \
  "$(grep -c '^## Drift guard example' "$SOURCE/templates/rules-details.md") $(grep -c 'templates/drift-guard-example.sh' "$SOURCE/templates/rules-details.md")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
