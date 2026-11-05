#!/usr/bin/env bash
# covers: scripts/paths.sh
# plan-stale-fence.test.sh -- pass 3 (class markdown-fence-drift): pp_plan_stale reads the plan's ## Steps by the one
# fence rule (scripts/fence.sh). A step quoted in an indented or tilde fence is fixture text, never a step whose change
# on main stales the judges' verdict; a shorter delimiter inside a longer fence does not close it, so a real step after
# that fence is still read. A stale step missed here lets builder-launch.sh launch a plan main has moved under.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
g() { git -C "$T/m" -c user.name=t -c user.email=t@t "$@"; }
git init -q -b main "$T/m"
for f in a b c d e; do echo 1 > "$T/m/$f.txt"; done; g add .; g commit -qm one; A=$(g rev-parse HEAD)
for f in a b c d e; do echo 2 > "$T/m/$f.txt"; done; g commit -qam two; B=$(g rev-parse HEAD)
FN=$(sed -n '/^pp_plan_stale() {/,/^}/p' "$REAL/scripts/paths.sh")
stale() { printf '%s\n' "$@" > "$T/plan.md"
  (. "$REAL/scripts/fence.sh"; eval "$FN"; PP_MAIN=$T/m; pp_plan_stale "$A" "$B" "$T/plan.md" plan.md) | paste -sd' ' -; }

check "a fenced step is fixture text in every fence form; a real step after a nested fence is read" \
  "b.txt|b.txt|b.txt d.txt|b.txt e.txt" \
  "$(stale '## Steps' '  ```' '- modify a.txt' '  ```' '- modify b.txt')|$(stale '## Steps' '~~~' '- modify a.txt' '~~~' '- modify b.txt')|$(stale '## Steps' '- modify b.txt' '````' '```' '- modify c.txt' '````' '- modify d.txt')|$(stale '## Steps' '- modify b.txt' '  ```' '## Other' '  ```' '- modify e.txt')"
# Issue 640: a Steps heading written closed (`## Steps ##`) is the same section; missed, its steps never stale a verdict.
check "Steps heading closed is read" "$(stale '## Steps' '- modify a.txt')" "$(stale '## Steps ##' '- modify a.txt')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
