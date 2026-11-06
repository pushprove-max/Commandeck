#!/usr/bin/env bash
# merge-unit-local.sh's loosened-check report (issue 676): a Builder edits existing tests without asking, so the merge
# report is where the owner reads every check it loosened. Run on loosened_report, cut from the script, on a scratch repo.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (want \"$2\", got \"$3\")"; fi }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
awk '/^loosened_report\(\)/ { on=1 } on { print } on && /^}$/ { exit }' "$ROOT/scripts/merge-unit-local.sh" > "$T/fn.sh"
HERE=$ROOT/scripts
# shellcheck disable=SC1090,SC1091
. "$ROOT/scripts/fence.sh"; . "$T/fn.sh"
R=$T/repo EV=$T/u-evidence.md
g() { git -C "$R" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null "$@"; }
git init -q -b main "$R"; mkdir -p "$R/t"
printf 'check "one" 0 0\ncheck "two" 0 0\n' > "$R/t/x.test.sh"; g add -A; g commit -qm base
g checkout -q -b unit/u
evidence() { printf '# u\n\n'; [ $# = 0 ] || { printf '## Loosened checks\n\n'; printf '%s\n' "$@"; printf '\n## Proof\n\nRan: x\n'; }; } # [<list lines>]
report() { (cd "$R" && loosened_report "$(g merge-base main unit/u)" unit/u "$EV"); }

# Catches: a report about loosened checks on a unit that touched no existing test, noise on every merge.
printf 'echo a\n' > "$R/a.sh"; g add -A; g commit -qm code; evidence > "$EV"
check "no edited tests: no loosened-check section" "" "$(report)"

printf 'check "one" 0 0\ncheck "two" 0 1\n' > "$R/t/x.test.sh"; g commit -qam "loosen two"
# Catches: an edited test whose loosened check never reaches the owner's eyes.
evidence '- t/x.test.sh: two: expects 0 or 1; still catches: a crash exit' > "$EV"
check "the merge report lists a loosened check named in the evidence file" \
  "step 4 edited tests: t/x.test.sh|step 4 loosened check: - t/x.test.sh: two: expects 0 or 1; still catches: a crash exit" \
  "$(report | paste -sd'|' -)"
# Catches: a cut-off list hiding the loosened checks past the first few.
evidence $(for i in $(seq 1 40); do printf -- '-_t/x.test.sh:_case%s ' "$i"; done) > "$EV"
check "a long loosened-check list is shown whole" "40 -_t/x.test.sh:_case40" \
  "$(report | grep -c '^step 4 loosened check: ') $(report | tail -1 | sed 's/^step 4 loosened check: //')"
# Catches: an evidence file with no list read as "nothing got looser".
evidence > "$EV"; A=$(report | grep -c "loosened checks: MISSING: u-evidence.md has no '## Loosened checks' list")
rm -f "$EV"; B=$(report | grep -c 'loosened checks: MISSING')
check "a missing loosened-check list is reported as missing" "1 1" "$A $B"
# Catches: a check loosened by adding lines only (an accepted result added, a known-failure marker put above a test)
# left out of the report, because no line of the existing test was lost.
printf 'import unittest\nclass T(unittest.TestCase):\n    def test_a(self):\n        self.assertIn(1, {0})\n' > "$R/t/test_a.py"
g add -A; g commit -qm "base py"; g branch -f main HEAD
sed -i.bak '/def test_a/i\
    @unittest.expectedFailure
' "$R/t/test_a.py"; rm -f "$R/t/test_a.py.bak"; g commit -qam "mark known failure"
evidence '- t/test_a.py: test_a: expected failure; still catches: an unexpected pass' > "$EV"
check "an addition-only loosening is reported" \
  "step 4 edited tests: t/test_a.py|step 4 loosened check: - t/test_a.py: test_a: expected failure; still catches: an unexpected pass" \
  "$(report | paste -sd'|' -)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
