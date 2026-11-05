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
# #653: the template no longer spells out the Test edit line, so the refusal must print it for the test that lost a line.
check "test edit refusal shows the ruling line form" 1 "$(grep -cE 'Lines main must add: Test edit: t/x\.test\.sh test:[^ ]+ ruling:' "$TMP/err")"

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

approve "Test edit: t/x.test.sh test:two ruling:$OKID"
check "approved_edit_passes: main's line with a logged id lets the pass run" "0" "$(epass)"

# Catches the merge trusting the launch: a tip is verified again from main's script, and a later edit is unapproved there.
V_OK=$(everify)
printf '1. ruled\n   - Source: %s\n' "$OKID" > "$MAINR"
check "verify_refuses_unapproved_edit (--verify refuses the committed edit once main holds no line, and passes while it does)" "0 2 1" \
  "$V_OK $(everify) $(grep -c 't/x.test.sh is an existing test' "$TMP/verr")"

# Issue 504: main approves one test, not the file. --verify reads the committed tip, which lost the line of `check "two"`.
# Catches a line that names another test, or only the path, approving this edit: one yes would cover every test in the file.
printf '1. ruled\n   - Source: %s\nTest edit: t/x.test.sh test:one ruling:%s\n' "$OKID" "$OKID" > "$MAINR"; everify >/dev/null
OTHER_TEST=$(grep -c 't/x.test.sh is an existing test' "$TMP/verr") TELLS=$(grep -c 'Test edit: t/x.test.sh test:two ruling:<id>' "$TMP/verr")
printf '1. ruled\n   - Source: %s\nTest edit: t/x.test.sh ruling:%s\n' "$OKID" "$OKID" > "$MAINR"; everify >/dev/null
PATH_ONLY=$(grep -c 't/x.test.sh is an existing test' "$TMP/verr")
check "a test the line does not name is refused (another test's line and a path-only line approve nothing; the refusal prints the line to add)" "1 1 1" "$OTHER_TEST $TELLS $PATH_ONLY"

# Catches a named test's line failing to approve its own edit.
printf '1. ruled\n   - Source: %s\nTest edit: t/x.test.sh test:two ruling:%s\n' "$OKID" "$OKID" > "$MAINR"; everify >/dev/null
check "a named test passes (the line for the test that lost its check approves the edit)" "0" "$(grep -c 't/x.test.sh is an existing test' "$TMP/verr")"

# A line outside every check is refused by line. Catches a helper edit approved by a test's name or by (file): one (file)
# approval would cover every helper of the file, and a helper may register a test.
printf 'helper() { :; }\ncheck "one" 0 0\n' > "$REPO/t/h.test.sh"; git -C "$REPO" add t; git -C "$REPO" commit -qm "a helper"
git -C "$W" merge -q -m merge main; printf 'check "one" 0 0\n' > "$W/t/h.test.sh"; git -C "$W" add t; git -C "$W" commit -qm "drop the helper"
rulings() { { printf '1. ruled\n   - Source: %s\n' "$OKID"; printf '%s\n' "$@"; } > "$MAINR"; } # <Test edit lines>
X="Test edit: t/x.test.sh test:two ruling:$OKID"
HL="Test edit: t/h.test.sh line:helper() { :; } ruling:$OKID"
stops() { grep -c "$1 is an existing test" "$TMP/verr"; } # <path>: 1 when --verify refused that file
rulings "$X" "Test edit: t/h.test.sh test:one ruling:$OKID"; everify >/dev/null; BY_TEST=$(stops t/h.test.sh)
rulings "$X" "Test edit: t/h.test.sh test:(file) ruling:$OKID"; everify >/dev/null; BY_FILE=$(stops t/h.test.sh)
rulings "$X" "$HL"; everify >/dev/null
check "a helper edit needs its line (a test's name and (file) cover no code line; its own line approval does)" "1 1 0" "$BY_TEST $BY_FILE $(stops t/h.test.sh)"

# Catches: a path-only line from before test names leaving main to find the ruling again: it approves nothing, and the refusal
# prints each line to add with that line's id, so the owner's yes moves over by one copy and no test goes unnamed.
rulings "Test edit: t/x.test.sh ruling:$OKID" "Test edit: t/h.test.sh ruling:$OKID"; RC=$(everify)
READY=$(grep -c "Test edit: t/x.test.sh test:two ruling:$OKID" "$TMP/verr") HELP=$(grep -cF "$HL" "$TMP/verr")
rulings "$X" "$HL"; everify >/dev/null
check "a path-only line gets ready lines" "2 1 1 0" "$RC $READY $HELP $(grep -c 'is an existing test' "$TMP/verr")"

# One approval names one exact line and is spent on it. Catches an approval reaching a second identical line, another file, a
# changed text, a labelled line or an unlogged id; (file) or (line) standing in for it; a data file losing its (file); and a
# retry that hangs on anything but git and main's rulings.
printf 'run "same"\nrun "same"\ncheck "one" 0 0\n' > "$REPO/t/l.test.sh"; printf '{\n"a": 1\n}\n' > "$REPO/t/d.test.json"
git -C "$REPO" add t; git -C "$REPO" commit -qm "two same lines"; git -C "$W" merge -q -m merge main
printf 'check "one" 0 0\n' > "$W/t/l.test.sh"; printf '{\n}\n' > "$W/t/d.test.json"; git -C "$W" add t; git -C "$W" commit -qm "drop them"
L="Test edit: t/l.test.sh line:run \"same\" ruling:$OKID"
D="Test edit: t/d.test.json test:(file) ruling:$OKID"
rulings "$X" "$HL" "$D" "$L"; everify >/dev/null; ONE=$(stops t/l.test.sh) LEFT=$(grep -oF 'Test edit: t/l.test.sh line:run "same" ruling:<id>' "$TMP/verr" | wc -l | tr -d ' ')
rulings "$X" "$HL" "$D" "$L" "$L"; everify >/dev/null; TWO=$(stops t/l.test.sh) DATA=$(stops t/d.test.json)
WRONG=0
for w in "Test edit: t/h.test.sh line:run \"same\" ruling:$OKID" "Test edit: t/l.test.sh line:run \"sam\" ruling:$OKID" "Test edit: t/l.test.sh line:run \"same\" ruling:$OTHERID" \
  "Test edit: t/l.test.sh test:(file) ruling:$OKID" "Test edit: t/l.test.sh test:(line) ruling:$OKID"; do
  rulings "$X" "$HL" "$D" "$w" "$w"; everify >/dev/null; WRONG=$((WRONG + $(stops t/l.test.sh)))
done
rulings "Test edit: t/x.test.sh line:check \"two\" 0 0 ruling:$OKID" "$HL" "$D" "$L" "$L"; everify >/dev/null; LABELLED=$(stops t/x.test.sh)
# The retry: the approval and the index go between two runs, and the third run needs only main's rulings again.
rulings "$X" "$HL" "$D"; everify >/dev/null; R1=$(stops t/l.test.sh)
mv "$(git -C "$W" rev-parse --absolute-git-dir)/index" "$TMP/index.gone"; git -C "$W" reset -q
: > "$MAINR"; everify >/dev/null; R2=$(stops t/l.test.sh)
rulings "$X" "$HL" "$D" "$L" "$L"; everify >/dev/null
check "a line approval unlocks one line" "1 1 0 0 5 1 1 1 0" "$ONE $LEFT $TWO $DATA $WRONG $LABELLED $R1 $R2 $(stops t/l.test.sh)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
