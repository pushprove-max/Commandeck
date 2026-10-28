#!/usr/bin/env bash
# new-test-count.sh (issue 433): a change that added more tests than the cap reached review with no count named. The
# counter feeds the pass script's cap, so a test it misses lets a change past the cap, and a moved or already-merged
# test it counts refuses a change that adds none.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# repo <name> -- a project whose main holds one shell test with one check, and a unit branch cut from it.
repo() {
  R=$T/$1; mkdir -p "$R/scripts/__tests__" "$R/src"
  git -C "$R" init -q -b main && git -C "$R" config user.name t && git -C "$R" config user.email t@t
  printf 'check "the old case" 0 0\n' > "$R/scripts/__tests__/a.test.sh"
  git -C "$R" add -A && git -C "$R" commit -qm base && git -C "$R" checkout -q -b unit
}
count() { (cd "$R" && bash "$REAL/scripts/new-test-count.sh" main | head -1); }

repo added; printf 'check "the new case one" 0 0\ncheck "the new case two" 0 0\n' >> "$R/scripts/__tests__/a.test.sh"
check "a shell test file's added check lines count as new tests (issue 433)" "2 1" \
  "$(count) $(cd "$R" && bash "$REAL/scripts/new-test-count.sh" main | grep -cx 'the new case one')"

repo moved; printf '# a header\n' > "$R/scripts/__tests__/b.test.sh"; : > "$R/scripts/__tests__/a.test.sh"
printf 'check "the old case" 0 0\n' >> "$R/scripts/__tests__/b.test.sh"
check "a check moved with the same label is not new (issue 433)" 0 "$(count)"

repo ts; printf "it('adds a row', () => {});\ntest(\"keeps a row\", () => {});\nconst x = fit;\n" > "$R/src/a.test.ts"
check "an it( or test( case added to a .test.ts file counts (issue 433)" 2 "$(count)"

# Work merged on main after the unit's own fork is not the unit's change, whatever review base main set.
repo merged; git -C "$R" checkout -q main; printf 'check "merged work" 0 0\n' >> "$R/scripts/__tests__/a.test.sh"
git -C "$R" commit -qam merged; git -C "$R" checkout -q unit; git -C "$R" rebase -q main
printf 'check "the unit case" 0 0\n' >> "$R/scripts/__tests__/a.test.sh"
check "tests already on main before a review base are not counted (issue 433)" 1 "$(count)"

repo spec; for i in $(seq 31); do printf "test('case %s', () => {});\n" "$i"; done > "$R/src/a.spec.ts"
check "31 test( cases added to src/a.spec.ts count 31 (issue 433)" 31 "$(count)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
