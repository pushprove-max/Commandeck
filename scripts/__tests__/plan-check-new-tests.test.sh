#!/usr/bin/env bash
# plan-check-new-tests.test.sh -- issue 462: a plan that names test cases carries the `New tests: <unit> <n>` line the
# pass's cap reads. A plan with no line, or a line that does not match the cases it names, is refused naming the line;
# a ` -- <reason>` lets the count differ. Cases are the `; `-separated parts of the `- test file path:` rows, else of
# the `Red-first:` lines; a fenced line and a `Break:` line count nothing.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PC=$REAL/scripts/plan-check.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/p"; printf 'a\nb\nc\n' > "$T/p/code.sh"
# plan <New tests line or ''> <extra acceptance lines> -- a plan naming three cases that passes every other check
plan() {
  printf 'Goal: check the New tests line.\n\n- Planned size: 1 files, 1 changed lines\nCloses: none\n%s\n\n## What can go wrong\n\n- a case: t-one\n\n## Steps\n\n- modify src/x.ts -- the one change\n\n## Facts\n\n- code.sh holds three lines -- code.sh:1-3 (observed: 2026-10-01)\n\n## Acceptance test\n\n- test file path: `a.test.sh` (t-one; t-two; t-three)\n%s\n' \
    "$1" "${2:-}" > "$T/p/nt.md"
}
printf 'Fix the issues.\n\nTier: Standard\n\n## Prior art\n\nInternal tooling; no outside library.\n\n## Data design\n\nNo stored data.\n\n## What can go wrong\n\n- Nothing new can break: fixture.\n' > "$T/batch.md"
ntp() { plan "$@"; PLAN_CHECK_ROOT=$T bash "$PC" "$T/p/nt.md" "$T/batch.md" >/dev/null 2>"$T/err"; echo $?; } # prints the plan-check code
r=$(ntp ''); out="missing=$r:$(grep -c 'names 3 new test cases but has no `New tests: nt 3` line' "$T/err")"
out+=" match=$(ntp 'New tests: nt 3')"
bare=$(ntp 'New tests: 3'); out+=" bare=$bare"
r=$(ntp 'New tests: nt 4'); out+=" differs=$r:$(grep -c 'says New tests: 4 but names 3 cases' "$T/err")"
out+=" reason=$(ntp 'New tests: nt 2 -- two cases fold into one check')"
out+=" fenced=$(ntp 'New tests: nt 3' $'```\n- test file path: `b.test.sh` (x; y)\n```')"
out+=" redfirst=$(ntp 'New tests: nt 3' 'Break: a.test.sh -- t-one -- src/x.ts')"
out+=" zero=$(ntp 'New tests: nt 03')"
check "a wrong New tests line is refused (issue 462)" "missing=2:1 match=0 bare=0 differs=2:1 reason=0 fenced=0 redfirst=0 zero=0" "$out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
