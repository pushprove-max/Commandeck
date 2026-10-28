#!/usr/bin/env bash
# plan-check-budget.test.sh -- Issues 426 and 427: plan-check refuses, before any judge reads it, a plan whose facts do
# not resolve (a missing file, a line past the end, a plan cited as evidence, an undated or future observation, no Facts
# at all) and a plan over its budget (no one-line Goal:, no one-line Steps, prose outside ## Why, a section over its
# cap), naming what failed. A plan inside both passes, and text in any fence form (fence.sh's rule) is never prose. Every
# SENTINELS line plan-check exempts from prose is proved here to be in seat.sh's spec, allowed alone and refused with
# words added.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.claude/plans"; printf 'a\nb\nc\n' > "$T/code.sh"; echo plan > "$T/.claude/plans/other.md"
# pc <expected text> <plan line>... -- "<rc> <1 when stderr holds the text, else 0>"
pc() { local want=$1; shift
  printf '%s\n' "$@" | PLAN_CHECK_ROOT=$T bash "$REAL/scripts/plan-check.sh" - '' >/dev/null 2>"$T/err"
  echo "$? $(grep -cF -- "$want" "$T/err")"; }
GOAL='Goal: refuse a plan whose facts do not resolve.'
BASE=('## What can go wrong' '- a case: test' '- Planned size: 1 files, 1 changed lines')
STEPS=('## Steps' '- modify code.sh ~2 -- the one change')
FACT='- code.sh holds three lines -- code.sh:1-3 (observed: 2026-10-01)'
ok=("$GOAL" "${BASE[@]}" "${STEPS[@]}" '## Facts' "$FACT")

check "a plan inside the budget whose facts resolve passes" "0 0" "$(pc REFUSED "${ok[@]}")"
# Owner's answer: a plan in the format before 0.55.0 passes with a warning to rewrite it; one marker of the new format
# (a Goal: line, a Steps or a Facts section) makes it a new plan, checked in full.
check "a plan in the format before 0.55.0 passes, warning that it was not checked" "0 1" \
  "$(pc 'WARNING: the plan is in the plan format before 0.55.0' 'plan' "${BASE[@]}" '## Cuts' 'Old prose, a ``` fence holding Goal: below.' '```' 'Goal: quoted' '```')"
check "a plan with only a Goal: line of the new format is checked in full" "2 1" "$(pc 'no ## Facts section' "$GOAL" "${BASE[@]}")"
check "a Facts citation of a missing file is refused, naming it" "2 1" \
  "$(pc 'nope.sh:1 -- no such file' "$GOAL" "${BASE[@]}" "${STEPS[@]}" '## Facts' '- x -- nope.sh:1 (observed: 2026-10-01)')"
check "a Facts line past the end of the file is refused, naming the count" "2 1" \
  "$(pc 'code.sh:2-9 -- lines 2-9 are not inside the file (3 lines)' "$GOAL" "${BASE[@]}" "${STEPS[@]}" '## Facts' '- x -- code.sh:2-9 (observed: 2026-10-01)')"
check "a Facts citation of a plan is refused" "2 1" \
  "$(pc 'cites a plan' "$GOAL" "${BASE[@]}" "${STEPS[@]}" '## Facts' '- x -- .claude/plans/other.md:1 (observed: 2026-10-01)')"
check "an observed date that is not a calendar date is refused" "2 1" \
  "$(pc 'observed: 2026-13-40 -- not a calendar date' "$GOAL" "${BASE[@]}" "${STEPS[@]}" '## Facts' '- x -- code.sh:1 (observed: 2026-13-40)')"
check "an observed date after today is refused" "2 1" \
  "$(pc 'after today' "$GOAL" "${BASE[@]}" "${STEPS[@]}" '## Facts' '- x -- code.sh:1 (observed: 2999-01-01)')"
check "a fact with no observed date is refused" "2 1" \
  "$(pc 'no `(observed: YYYY-MM-DD)`' "$GOAL" "${BASE[@]}" "${STEPS[@]}" '## Facts' '- x -- code.sh:1')"
check "a plan with no Facts section is refused" "2 1" "$(pc 'no ## Facts section' "$GOAL" "${BASE[@]}" "${STEPS[@]}")"
check "a plan with no Goal: line is refused" "2 1" "$(pc 'has no Goal: line' "${ok[@]:1}")"
check "a Goal: that runs onto a second line is refused" "2 1" \
  "$(pc 'the goal is one line' "$GOAL" 'and keeps going here' "${ok[@]:1}")"
check "a plan with no Steps section is refused" "2 1" "$(pc 'has no ## Steps section' "$GOAL" "${BASE[@]}" '## Facts' "$FACT")"
check "a step that is not one new|modify|delete line is refused" "2 1" \
  "$(pc '## Steps line 7 is not one step' "${ok[@]:0:6}" '  and a second line' '## Facts' "$FACT")"
check "prose outside ## Why is refused, naming its section" "2 1" \
  "$(pc 'under ## What can go wrong is prose' "${ok[@]}" '## What can go wrong' 'This case is explained in prose.')"
check "the Owner's words: line the plan-author spec requires is not prose" "0 0" \
  "$(pc REFUSED "$GOAL" "Owner's words: build issue 1" "${ok[@]:1}")"
# The plan-author spec in seat.sh requires `## Stated limits` to open with a parenthetical line: read from seat.sh, so
# the spec and the checker cannot drift apart. Only that exact line is exempt; another parenthetical line is prose.
PRE=$(grep -o '(every reviewer is handed these[^`\\]*)' "$REAL/scripts/seat.sh")
check "the Stated limits opening line the plan-author spec requires is not prose" "1 0 0" \
  "$(printf '%s\n' "$PRE" | grep -c '^(every.*blocker)$') $(pc REFUSED "${ok[@]}" '## Stated limits' "$PRE" '- One file; command: git diff --stat; date: 2026-10-01')"
check "another parenthetical line under Stated limits is prose" "2 1" \
  "$(pc 'under ## Stated limits is prose' "${ok[@]}" '## Stated limits' '(these limits are loose, read them kindly)')"
# Every SENTINELS entry in plan-check.sh stands only if seat.sh's plan-author spec holds it word for word (grep), a plan
# with it as its own line passes, and the same line with words appended is prose. Read from plan-check.sh, so a new
# entry is tested the day it is added. One string over all entries, so a failure names the entry.
ENT=$(python3 -I -c 'import ast, re, sys
m = re.search(r"^SENTINELS = (\(.*?\x27\))$", open(sys.argv[1]).read(), re.S | re.M)
print("\n".join(ast.literal_eval(m.group(1))) if m else "")' "$REAL/scripts/plan-check.sh")
GOT="$([ -n "$ENT" ] && echo found || echo none):" WANT="found:"
while IFS= read -r s; do [ -n "$s" ] || continue
  GOT="$GOT [$s] $([ "$(grep -cF -- "$s" "$REAL/scripts/seat.sh")" -gt 0 ] && echo 1 || echo 0) $(pc REFUSED "${ok[@]}" '## What can go wrong' "$s") $(pc 'is prose' "${ok[@]}" '## What can go wrong' "$s and more words here")"
  WANT="$WANT [$s] 1 0 0 2 1"
done <<< "$ENT"
check "each SENTINELS entry is in seat.sh, passes as its own line, and is prose with words added" "$WANT" "$GOT"
# Each other shape the budget does not read as prose, paired with the same words outside that shape, which are: a
# comment (one line, then several), a table row, a quote, a list item's indented continuation, a Key: of five words.
yes() { pc REFUSED "${ok[@]}" '## Cuts' "$@"; }
no() { pc 'under ## Cuts is prose' "${ok[@]}" '## Cuts' "$@"; }
GOT="$(yes '<!-- a note in prose -->') $(no '<!-- x -->' 'a note in prose')"
GOT+=" $(yes '<!--' 'Prose inside.' '-->') $(no '<!--' '-->' 'Prose after it.')"
GOT+=" $(yes '| a | prose cell |') $(no 'a, prose cell')"
GOT+=" $(yes '> quoted prose here') $(no 'quoted prose here')"
GOT+=" $(yes '- an item' '  continued prose') $(no 'Timed checks: none' '  continued prose')"
GOT+=" $(yes 'Five words make a key: yes') $(no 'This line is a long sentence: yes')"
# The Facts check skips a quoted or commented fact as the budget does; the same fact bare is checked.
DEAD='- x -- nope.sh:1 (observed: 2026-10-01)'
check "a dead citation in a fence or a comment under ## Facts is not checked; the same line bare is refused" "0 0 0 0 2 1" \
  "$(pc nope.sh "${ok[@]}" '~~~' "$DEAD" '~~~') $(pc nope.sh "${ok[@]}" '<!--' "$DEAD" '-->') $(pc nope.sh "${ok[@]}" "$DEAD")"
check "a comment, table row, quote, list continuation and short Key: are not prose; the same words bare are" \
  "0 0 2 1 0 0 2 1 0 0 2 1 0 0 2 1 0 0 2 1 0 0 2 1" "$GOT"
check "prose under ## Why passes" "0 0" "$(pc REFUSED "${ok[@]}" '## Why' 'This plan exists because prose belongs here.')"
check "a section over its cap is refused, naming its size and cap" "2 1" \
  "$(pc 'section ## Verification is' "${ok[@]}" '## Verification' "$(for i in $(seq 80); do printf -- '- check %s: a long enough line of text\n' "$i"; done)")"
check "prose quoted in a tilde fence is not prose" "0 0" "$(pc REFUSED "${ok[@]}" '## Cuts' '~~~' 'Quoted prose.' '~~~')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
