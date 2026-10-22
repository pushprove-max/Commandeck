#!/usr/bin/env bash
# covers: scripts/merge-queue.sh
# Issue 307's reuse rule against a check that finds its inputs by glob, not by name (split from
# merge-queue.test.sh): a run that tested another tree never stands for the merged tree; the check runs and refuses.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-queue-setup.sh"

# Inputs no file names: the check counts *.flag files by glob and is red on exactly one. The first
# unit alone (one flag) is red, the train (two) green: the train's run never stands for the first unit's tree.
jq --arg c "echo run >> $TMP/check-calls; [ \"\$(find . -name '*.flag' | wc -l)\" -ne 1 ]" '.testCommand = $c' <<<"$CFG" > "$REPO/.claude/commandeck.json"
mk ga; mk gb; add ga a.flag; add gb b.flag; go ga; go gb; : > "$TMP/check-calls"
OUT=$(cd "$REPO" && bash "$QUEUE" --train "ga@$(sha ga)" "gb@$(sha gb)" 2>&1); RC=$?
check "a glob-read train whose first unit is red alone merges neither: the train's run, then the first unit's own" "1 0 0 2" \
  "$RC $(git -C "$REPO" log --format=%s | grep -c '^feat(ga)') $(git -C "$REPO" log --format=%s | grep -c '^feat(gb)') $(runs)"
pattern_cases <<'EOF'
a * glob|set -- *.flag
a ? glob|set -- ?.flag
a [ab] glob|set -- [ab].flag
an extglob|shopt -s extglob\nset -- @(a|b).flag
EOF
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
