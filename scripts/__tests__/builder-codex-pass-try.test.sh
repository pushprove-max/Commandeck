#!/usr/bin/env bash
# builder-codex-pass-try.test.sh -- issue 471: a refusal of the pass ends with a `Try:` line holding the command that
# runs now, built from what was refused. The new-test-cap refusal's Try is the count of the new tests, run in the
# unit's worktree; run as printed, it must work.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

git -C "$REPO" worktree add -q "$TMP/ws/ca" -b builder/ca main && mkdir -p "$TMP/ws/ca/.claude/briefs" "$TMP/ws/ca/t"
echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$TMP/ws/ca/.claude/settings.local.json"
printf 'Fix #1.\nbash x/builder-codex-pass.sh ca 1 adversarial\n' > "$REPO/.claude/briefs/ca-builder-brief.md"
cp "$REPO/.claude/briefs/ca-builder-brief.md" "$TMP/ws/ca/.claude/briefs/ca.md"
for i in $(seq 45); do printf 'check "case %s" 0 0\n' "$i"; done > "$TMP/ws/ca/t/x.test.sh"
(cd "$TMP/ws/ca" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-ca-1 STUB_REPLY='VERDICT: GO' \
  bash "$PASS_SH" ca 1 adversarial >"$TMP/out" 2>"$TMP/err")
TRY=$(tail -n 1 "$TMP/err")
check "the new-test cap refusal ends with a Try line that counts the new tests (issue 471)" "1 Try: cd $TMP/ws/ca && bash $REAL/scripts/new-test-count.sh main" \
  "$(grep -c 'over the new-test cap' "$TMP/err") $TRY"
check "the Try line runs as printed and counts the 45 new tests (issue 471)" "45" "$(eval "${TRY#Try: }" | head -1)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
