#!/usr/bin/env bash
# builder-codex-pass-test-edit.test.sh -- issue 496: an existing test file that loses a line reaches no review and no merge
# unless main's rulings for the unit hold `Test edit: <path> ruling:<id>` with an id the ruling log stands behind. Only
# main's copy counts, and --verify asks again from main's script. The ids use the r-1999... shape: the leak test bans r-20....
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

LOG=$TMP/rulings.jsonl OKID=r-19990101-000001-1-abcdef OTHERID=r-19990101-000002-1-abcdef
printf '%s\n' '{"id":"'$OKID'","answer":"yes"}' > "$LOG"
MAINR=$REPO/.claude/briefs/$U-main-rulings.md WTR=$B/$U-main-rulings.md
# The test file is on main before the unit forks, so the unit's change to it is an edit, not an addition.
mkdir -p "$REPO/t"; printf 'check "one" 0 0\ncheck "two" 0 0\ncheck "three" 0 0\n' > "$REPO/t/x.test.sh"
git -C "$REPO" add t; git -C "$REPO" commit -qm "a test"; git -C "$W" merge -q --ff-only main
printf 'check "one" 0 0\ncheck "three" 0 0\n' > "$W/t/x.test.sh"
epass() { # prints the exit code of pass 1; stderr in $TMP/err
  (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_RULING_LOG=$LOG STUB_THREAD=thr-1 STUB_REPLY='VERDICT: GO' \
    bash "$PASS_SH" "$U" 1 adversarial >"$TMP/out" 2>"$TMP/err"); echo $?
}
ack() { (cd "$W" && COMMANDECK_MAIN=$REPO bash "$PASS_SH" --ack-rulings "$U" >/dev/null 2>&1); }
everify() { (cd "$REPO" && PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_RULING_LOG=$LOG bash "$PASS_SH" --verify "$W" "$U" "$(git -C "$W" rev-parse HEAD)" >"$TMP/vout" 2>"$TMP/verr"); echo $?; }
approve() { printf '1. ruled\n   - Source: %s\n%s\n' "$OKID" "$1" > "$MAINR"; ack; } # <the Test edit line>

# Catches a thinned existing test reaching review: the cap counts added checks only, so a lost line passed.
RC=$(epass); NAMED=$(grep -c 't/x.test.sh is an existing test and loses 1 line(s), 1 of them check lines' "$TMP/err")
TRY=$(grep -c 'ask-main.sh "Test edit: t/x.test.sh"' "$TMP/err") ACKS=$(grep -c -- '--ack-rulings' "$TMP/err")
check "pass_refuses_unapproved_edit (an existing test that lost a check stops the pass, names the file and how to ask main)" "2 1 1 1 0" \
  "$RC $NAMED $TRY $ACKS $(ls "$B"/$U-r1-reports.md 2>/dev/null | wc -l | tr -d ' ')"

# Catches the Builder approving its own edit: its worktree copy of the rulings file is not main's.
# Main's file holds the id with no Test edit line, so only reading the worktree's copy could approve the edit.
approve "no test edit here"
printf '1. ruled\n   - Source: %s\nTest edit: t/x.test.sh ruling:%s\n' "$OKID" "$OKID" > "$WTR"; ack
RC=$(epass)
check "worktree_approval_ignored (a Test edit line in the worktree's rulings approves nothing)" "2 1" \
  "$RC $(grep -c 't/x.test.sh is an existing test' "$TMP/err")"
rm -f "$WTR" "$MAINR"; ack

# Catches an id or a path that merely looks like approval: an id the log lacks, and an approval of another file.
approve "Test edit: t/x.test.sh ruling:$OTHERID"; WRONG_ID=$(epass)
approve "Test edit: t/y.test.sh ruling:$OKID"; WRONG_PATH=$(epass)
approve "Test edit: t/x.test.sh ruling:$OKID extra"; WRONG_SHAPE=$(epass)
check "wrong_id_refused: an unlogged id, another file's line and a malformed line each approve nothing" "2 2 2" "$WRONG_ID $WRONG_PATH $WRONG_SHAPE"

approve "Test edit: t/x.test.sh ruling:$OKID"
check "approved_edit_passes: main's line with a logged id lets the pass run" "0" "$(epass)"

# Catches the merge trusting the launch: a tip is verified again from main's script, and a later edit is unapproved there.
V_OK=$(everify)
printf '1. ruled\n   - Source: %s\n' "$OKID" > "$MAINR"
check "verify_refuses_unapproved_edit (--verify refuses the committed edit once main holds no line, and passes while it does)" "0 2 1" \
  "$V_OK $(everify) $(grep -c 't/x.test.sh is an existing test' "$TMP/verr")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
