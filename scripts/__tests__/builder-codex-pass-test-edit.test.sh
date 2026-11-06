#!/usr/bin/env bash
# builder-codex-pass-test-edit.test.sh -- issue 676: an edit to an existing test is the Builder's call. A pass and the
# merge's --verify run on a tree whose existing test lost a check with no `Test edit:` row; rows of the old rule are
# ignored, never refused; and every reviewer is told to check each edited test still catches its bug.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

OKID=r-19990101-000001-1-abcdef MAINR=$REPO/.claude/briefs/$U-main-rulings.md
# The test file is on main before the unit forks, so the unit's change to it is an edit, not an addition.
mkdir -p "$REPO/t"; printf 'check "one" 0 0\ncheck "two" 0 0\ncheck "three" 0 0\n' > "$REPO/t/x.test.sh"
git -C "$REPO" add t; git -C "$REPO" commit -qm "a test"; git -C "$W" merge -q --ff-only main
printf 'check "one" 0 0\ncheck "three" 0 0\n' > "$W/t/x.test.sh"
epass() { # prints the exit code of pass 1; stderr in $TMP/err
  (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-1 STUB_REPLY='VERDICT: GO' \
    bash "$PASS_SH" "$U" 1 adversarial >"$TMP/out" 2>"$TMP/err"); echo $?
}
ack() { (cd "$W" && COMMANDECK_MAIN=$REPO bash "$PASS_SH" --ack-rulings "$U" >/dev/null 2>&1); }
everify() { (cd "$REPO" && PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO bash "$PASS_SH" --verify "$W" "$U" "$(git -C "$W" rev-parse HEAD)" >"$TMP/vout" 2>"$TMP/verr"); echo $?; }

# Catches: a Builder held for hours on a named yes for a test edit that plainly follows the change (the issue-496 gate).
RC=$(epass)
check "a pass runs on a tree with an edited existing test and no Test edit row" "0 1 0" \
  "$RC $(ls "$B/$U-r1-reports.md" 2>/dev/null | wc -l | tr -d ' ') $(grep -c 'is an existing test' "$TMP/err")"
# Catches: a loosened test nobody checks once no person approves it; every reviewer must be asked.
P1='still catches the bug it was written for; rate P1 (class: loosened-test) a loosened check that lost its purpose'
check "the pass prompt carries the still-catches-its-bug P1 instruction" "yes" \
  "$(n=0 k=0; for p in "$B/$U"-r1-prompt-*.md; do n=$((n + 1)); grep -qF "$P1" "$p" && k=$((k + 1)); done; [ "$n" -gt 0 ] && [ "$n" = "$k" ] && echo yes || echo "$k of $n")"

# Catches: a unit opened under the old rule, whose main rulings hold Test edit rows (a path-only one too, which the old
# gate refused), stopped at the merge: the rows are left in place and read by nothing.
printf '1. ruled\n   - Source: %s\nTest edit: t/x.test.sh ruling:%s\nTest edit: t/x.test.sh test:one ruling:%s\n' "$OKID" "$OKID" "$OKID" > "$MAINR"; ack
check "old Test edit rows are ignored" "0 0" "$(everify) $(grep -c 'is an existing test' "$TMP/verr")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
