#!/usr/bin/env bash
# merge-rules.test.sh -- an owner's "keep mine" decision is saved by rule id, and
# the id is a hash of the rule's wording. What this pins: a release that rewords
# a rule still leaves out every rule the owner kept their own wording for, and a
# rule made from several is left out only when the owner keeps all of them (a
# duplicate rule beats a lost one).
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
MS() { python3 "$REAL/scripts/merge-rules.py" "$REAL/templates/main-session.md" "$@"; }
drops() { for i; do printf -- '--drop %s ' "$i"; done; }

# Every rule id of 0.7.1's main-session.md (merge-rules.py --units).
V071='1a205d56 18cd2c62 1f85d44e 58d81ff4 c89a261a 28c31a4a 6d119e42 34ec1023 57eadb12 32d46d9b c99218c7 f0729b8f 8fc96d58 00709c21 f0558144
f7c75c86 8361fb71 8ade2fb3 f6e2fbb0 2848b779 48b02596 a4d1bca5 6743a4ac 5f6ba6aa a78ec6d6 911bac3f 04adb41d c539053c 55bf03c0 426b85c6'
# shellcheck disable=SC2046
check "an owner who kept their own wording for every 0.7.1 main rule gets none of this release's" \
  "0 plugin rules kept" "$(MS $(drops $V071) --report | head -1 | cut -d, -f1)"
check "the relay rule an owner kept their own wording for in 0.7.1 stays out" 0 \
  "$(MS --drop 34ec1023 | grep -c 'goes to the relay pane')"
check "a rule reworded alone stays out under its 0.7.1 id" 0 \
  "$(MS --drop c99218c7 | grep -c 'Stated limits')"
check "a rule made from two 0.7.1 rules stays in when the owner kept only one" 1 \
  "$(MS --drop 18cd2c62 | grep -c 'Main plans with the owner')"
check "and goes when the owner kept both" 0 \
  "$(MS --drop 18cd2c62 --drop 8fc96d58 | grep -c 'Main plans with the owner')"
# The owner's newer, explicit answer for the reworded rule beats the one saved for the rule it was made from.
check "keep both for a reworded rule loads it, though keep mine was saved for its 0.7.1 id" 1 \
  "$(MS --drop c99218c7 --keep 8aa8b56d | grep -c 'Stated limits')"
check "keep both for a rule made from two loads it, though keep mine was saved for both" 1 \
  "$(MS --drop 18cd2c62 --drop 8fc96d58 --keep 607f18a2 | grep -c 'Main plans with the owner')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
