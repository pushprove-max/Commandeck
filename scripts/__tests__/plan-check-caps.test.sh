#!/usr/bin/env bash
# plan-check-caps.test.sh -- issues 476 and 480: plan-check.sh refuses a plan that asks the owner outside its one
# `## Question for the owner` section, and a plan over the review-limits caps (changed lines, Closes issues) with no
# `Split override: <reason>` line. A fenced line counts for neither; a bare `Split override:` is no override.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PC=$REAL/scripts/plan-check.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/p"; printf 'a\nb\nc\n' > "$T/p/code.sh"
# plan <changed lines> <Closes line> <extra lines at the end> -- a plan that passes every other check
plan() {
  printf 'Goal: check the caps.\n\n- Planned size: 1 files, %s changed lines\n%s\n\n## What can go wrong\n\n- a case: t-one\n\n## Steps\n\n- modify src/x.ts -- the one change\n\n## Facts\n\n- code.sh holds three lines -- code.sh:1-3 (observed: 2026-10-01)\n\n## Acceptance test\n\n- t-one\n%s\n' \
    "$1" "$2" "${3:-}" > "$T/p/c.md"
}
printf 'Fix the issues.\n\nTier: Standard\n\n## Prior art\n\nInternal tooling; no outside library.\n\n## Data design\n\nNo stored data.\n\n## What can go wrong\n\n- Nothing new can break: fixture.\n' > "$T/batch.md"
pc() { PLAN_CHECK_ROOT=$T bash "$PC" "$T/p/c.md" "$T/batch.md" >/dev/null 2>"$T/err"; echo $?; } # prints the plan-check code
refused() { grep -c "$1" "$T/err"; }

Q=$'\n## Question for the owner\n\n- Which one?\n'
plan 10 'Closes: none' "$Q"; out="one=$(pc)"
plan 10 'Closes: none' "$Q$Q"; r=$(pc); out+=" second=$r:$(refused 'asks the owner outside its one ## Question for the owner section (line ')"
plan 10 'Closes: none' $'\n> Owner: which one?'; r=$(pc); out+=" stray=$r:$(refused 'asks the owner outside its one ## Question for the owner section (line ')"
plan 10 'Closes: none' "$Q"$'> Owner: which one?\n'; out+=" inside=$(pc)"
plan 10 'Closes: none' $'\n```\n> Owner: which one?\n## Question for the owner\n## Question for the owner\n```'; out+=" fenced=$(pc)"
check "a stray owner section is refused (issue 476)" "one=0 second=2:1 stray=2:1 inside=0 fenced=0" "$out"

SPLIT='is over a cap'
plan 1000 'Closes: none'; out="atcap=$(pc):$(refused "$SPLIT")"
plan 1001 'Closes: none'; r=$(pc); out+=" lines=$r:$(refused "$SPLIT (1001 changed lines, cap 1000; 0 Closes issues, cap 5)")"
plan 10 'Closes: #1 #2 #3 #4 #5'; pc >/dev/null; out+=" fiveissues=$(refused "$SPLIT")"
plan 10 $'Closes: #1 #2 #3\nCloses: #4 #5 #6'; r=$(pc); out+=" issues=$r:$(refused "$SPLIT (10 changed lines, cap 1000; 6 Closes issues, cap 5)")"
plan 1001 'Closes: none' 'Split override: the owner ordered one unit'; out+=" override=$(pc):$(refused "$SPLIT")"
printf '{"review-limits":{"calls":60,"diffLines":"many"}}\n' > "$T/routing.json"
plan 10 'Closes: none'; r=$(COMMANDECK_ROUTING=$T/routing.json pc); out+=" unreadable=$r:$(refused "cannot read review-limits.diffLines from $T/routing.json")"
printf '{"review-limits":{"calls":60,"maxIssues":-1}}\n' > "$T/routing.json"
plan 10 'Closes: none'; r=$(COMMANDECK_ROUTING=$T/routing.json pc); out+=" negative=$r:$(refused "cannot read review-limits.maxIssues from $T/routing.json")"
check "over either cap is refused (issue 480)" "atcap=0:0 lines=2:1 fiveissues=0 issues=2:1 override=0:0 unreadable=2:1 negative=2:1" "$out"

# A routing file deployed before the caps were read: setup adds only roles, so a key it lacks takes the shipped cap and
# the plan is judged as on a fresh install; a value the owner kept is the owner's cap.
jq '."review-limits" |= del(.maxIssues, .oneJudgeLines)' "$REAL/config/routing.json" | jq '."review-limits".diffLines = 3000' > "$T/routing.json"
old() { COMMANDECK_ROUTING=$T/routing.json pc; }
plan 2000 'Closes: none'; out="kept=$(old)"
plan 10 'Closes: #1 #2 #3 #4 #5'; old >/dev/null; out+=" atcap=$(refused "$SPLIT")"
plan 10 'Closes: #1 #2 #3 #4 #5 #6'; r=$(old); out+=" over=$r:$(refused "6 Closes issues, cap 5")"
printf '{"review-limits":{"calls":60}}\n' > "$T/routing.json"
plan 1000 'Closes: none'; out+=" bare=$(old)"
plan 1001 'Closes: none'; r=$(old); out+=" bareover=$r:$(refused "1001 changed lines, cap 1000")"
check "an old routing file takes the shipped caps (issue 480)" "kept=0 atcap=0 over=2:1 bare=0 bareover=2:1" "$out"

plan 1001 'Closes: none' 'Split override:'; r=$(pc); out="bare=$r:$(refused "$SPLIT")"
plan 1001 'Closes: none' $'```\nSplit override: fenced\n```'; r=$(pc); out+=" fenced=$r:$(refused "$SPLIT")"
check "a bare Split override fails (issue 480)" "bare=2:1 fenced=2:1" "$out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
