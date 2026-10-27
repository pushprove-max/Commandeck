#!/usr/bin/env bash
# plan-check-placeholder-fences.test.sh -- Issue 400, pass-1 finding: plan-check reads fences by the one fence rule
# (scripts/fence.sh), so a valid plan that quotes placeholder UI in a tilde or indented fence still launches, a fence
# holding a shorter delimiter stays open, and a size line quoted in any fence is never the plan's own. A placeholder line
# outside every fence is still refused, so the fence rule hides only quoted text.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
pc() { printf '%s\n' "$@" | bash "$REAL/scripts/plan-check.sh" - '' >/dev/null 2>&1; echo $?; }
HEAD=('- Planned size: 1 files, 1 changed lines' '## What can go wrong' '- a case: test')

check "a placeholder line in a tilde fence passes" 0 "$(pc "${HEAD[@]}" '~~~tsx' '<p>Coming soon</p>' '~~~')"
check "a placeholder line in an indented backtick fence passes" 0 "$(pc "${HEAD[@]}" '  ```' '<p>Coming soon</p>' '  ```')"
check "a four-backtick fence holding a three-backtick line stays open" 0 \
  "$(pc "${HEAD[@]}" '````markdown' '```' '<p>Coming soon</p>' '````')"
check "a placeholder line after a closed tilde fence is refused" 2 "$(pc "${HEAD[@]}" '~~~' 'x' '~~~' '<p>Coming soon</p>')"
check "a size line quoted in a tilde fence is not the plan's size line" 2 \
  "$(pc '~~~' '- Planned size: 1 files, 1 changed lines' '~~~' '## What can go wrong' '- a case: test')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
