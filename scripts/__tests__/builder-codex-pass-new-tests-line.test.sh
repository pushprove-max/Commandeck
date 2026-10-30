#!/usr/bin/env bash
# builder-codex-pass-new-tests-line.test.sh -- issue 462: the pass's new-test cap is the unit plan's `New tests: <unit> <n>`
# line, up or down. A plan that reviewed 30 new tests stopped at 31 under a cap of 40, and a plan that reviewed 45 was
# stopped at 41 by the setting. `off` still wins, and a plan with no line keeps the setting's refusal.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

newunit() { # <unit> <new test count> [<plan New tests line>]: a unit adding that many tests, its plan on its worktree
  git -C "$REPO" worktree add -q "$TMP/ws/$1" -b "builder/$1" main && mkdir -p "$TMP/ws/$1/.claude/briefs" "$TMP/ws/$1/.claude/plans" "$TMP/ws/$1/t"
  echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$TMP/ws/$1/.claude/settings.local.json"
  printf 'Fix #1.\nbash x/builder-codex-pass.sh %s 1 adversarial\n' "$1" > "$REPO/.claude/briefs/$1-builder-brief.md"
  cp "$REPO/.claude/briefs/$1-builder-brief.md" "$TMP/ws/$1/.claude/briefs/$1.md"
  local i; for i in $(seq "$2"); do printf 'check "case %s" 0 0\n' "$i"; done > "$TMP/ws/$1/t/x.test.sh"
  [ -z "${3:-}" ] || printf 'Goal: x.\n%s\n' "$3" > "$TMP/ws/$1/.claude/plans/$1.md"
}
upass() { # <unit>: pass 1 of <unit>; its output in $TMP/err; prints its exit code
  (cd "$TMP/ws/$1" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-$1-1 STUB_REPLY='VERDICT: GO' \
    bash "$PASS_SH" "$1" 1 adversarial >"$TMP/out" 2>"$TMP/err"); echo $?
}

newunit lo 31 'New tests: lo 30'
out="down=$(upass lo):$(grep -c 'the change adds 31 new tests, over the new-test cap of 30 (the New tests: line in .claude/plans/lo.md)' "$TMP/err")"
newunit hi 45 'New tests: hi 45'
out+=" up=$(upass hi):$(grep -c 'over the new-test cap' "$TMP/err")"
newunit no 45
out+=" noline=$(upass no):$(grep -c 'the change adds 45 new tests, over the new-test cap of 40 (reviewLoop.newTestCap)' "$TMP/err")"
check "New tests 30 stops 31 (issue 462)" "down=2:1 up=0:0 noline=2:1" "$out"

jq '.reviewLoop.newTestCap = "off"' "$REPO/.claude/commandeck.json" > "$TMP/cfg" && mv "$TMP/cfg" "$REPO/.claude/commandeck.json"
newunit of 31 'New tests: of 30'
check "off wins over a New tests line (issue 462)" "0:0" "$(upass of):$(grep -c 'over the new-test cap' "$TMP/err")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
