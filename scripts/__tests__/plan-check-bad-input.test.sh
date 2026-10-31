#!/usr/bin/env bash
# plan-check-bad-input.test.sh -- issue 524: a plan whose `## Steps` or `## Cuts` say pars, refus, reject or validat lists
# its bad inputs under `## What can go wrong`: an absent or missing one, a junk or trailing one, an empty one and a quoted
# one. A plan missing a kind is refused naming each; `Bad input: none, <reason>` opts out, and a bare `Bad input: none,`
# does not.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PC=$REAL/scripts/plan-check.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/p"; printf 'a\nb\nc\n' > "$T/p/code.sh"
# plan <step text> <What can go wrong rows> <extra line or ''> -- a plan that passes every other check
plan() {
  printf 'Goal: check the bad-input rows.\n\n- Planned size: 1 files, 1 changed lines\nCloses: none\n%s\n\n## What can go wrong\n\n%s\n\n## Steps\n\n- modify src/x.ts -- %s\n\n## Facts\n\n- code.sh holds three lines -- code.sh:1-3 (observed: 2026-10-01)\n' \
    "$3" "$2" "$1" > "$T/p/bi.md"
}
printf 'Fix the issues.\n\nTier: Standard\n\n## Prior art\n\nInternal tooling; no outside library.\n\n## Data design\n\nNo stored data.\n\n## What can go wrong\n\n- Nothing new can break: fixture.\n' > "$T/batch.md"
bip() { plan "$@"; PLAN_CHECK_ROOT=$T bash "$PC" "$T/p/bi.md" "$T/batch.md" >/dev/null 2>"$T/err"; echo $?; } # prints the plan-check code
ALL=$'- Absent: no file\n- Junk: a trailing word\n- Empty: a blank line\n- Quoted: "x"'
# Catches: a parser planned with no bad-input row; a refusal that names no kind; a bare opt-out that opts out.
r=$(bip 'parse the input' '- a case: t-one' ''); out="none=$r:$(grep -c 'no absent or missing and junk or trailing and empty and quoted case' "$T/err")"
r=$(bip 'parse the input' $'- Absent: no file\n- Empty: a blank line' ''); out+=" some=$r:$(grep -c 'no junk or trailing and quoted case' "$T/err")"
r=$(bip 'parse the input' '- a case: t-one' 'Bad input: none,'); out+=" bare=$r"
check "a plan missing bad-input cases is refused" "none=2:1 some=2:1 bare=2" "$out"
# Catches: a check that refuses a plan that lists every kind, takes a plan with no parse word for a parser, or ignores the opt-out.
out="all=$(bip 'parse the input' "$ALL" '')"
out+=" noparse=$(bip 'rename the file' '- a case: t-one' '')"
out+=" optout=$(bip 'parse the input' '- a case: t-one' 'Bad input: none, a gate-only plan')"
out+=" stem=$(bip 'Validating the input' '- a case: t-one' '')"
check "a plan with bad-input cases passes" "all=0 noparse=0 optout=0 stem=2" "$out"
# Catches: the check reading only the fixture plans, so the last unit's plan (parsers, no junk row) goes through.
PLAN_CHECK_ROOT=$REAL bash "$PC" "$REAL/.claude/plans/plugin-open-2026-10-31.md" "$T/batch.md" >/dev/null 2>"$T/err"
check "the last unit's plan is asked for bad-input rows" "1" "$(grep -c 'list one row each, or write .Bad input: none, <reason>.' "$T/err")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
