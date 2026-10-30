#!/usr/bin/env bash
# Issue 344 (host issue 3171): before a closing (final) pass the unit is rebased onto current local main, and when main
# moved the shell tests that cover what the unit or main changed run, so a clash with main fails before Codex is asked
# and not at the merge. Pinned: an unrelated main change is rebased onto and the pass runs on that tip; a main change that
# breaks the unit's test stops the pass before Codex with no round file, and a retry without a fix is stopped again;
# a red `# own-lane:` test stops it too; a conflict stops it, names the file, aborts the rebase and leaves the branch as
# it was. The fixture is the one builder-codex-pass.test.sh uses.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

G() { git -C "$REPO" -c user.name=t -c user.email=t@t "$@"; }
# main already holds scripts/lib.sh and scripts/lane-lib.sh; the unit adds the tests that cover them, then a first pass.
mkdir -p "$REPO/scripts/__tests__"; echo 'echo ok' > "$REPO/scripts/lib.sh"; echo 'echo ok' > "$REPO/scripts/lane-lib.sh"
G add -A; G commit -qm libs; git -C "$W" merge -q --ff-only main
mkdir -p "$W/scripts/__tests__"
printf '#!/usr/bin/env bash\n# covers lib.sh\necho "1 passed, 0 failed"\n[ "$(bash "$(dirname "$0")/../lib.sh")" = ok ]\n' > "$W/scripts/__tests__/dep.test.sh"
printf '#!/usr/bin/env bash\n# own-lane: slow\n# covers lane-lib.sh\necho "1 passed, 0 failed"\n[ "$(bash "$(dirname "$0")/../lane-lib.sh")" = ok ]\n' > "$W/scripts/__tests__/lane.test.sh"
printf 'echo built\n' > "$W/a.sh"
pass 1 adversarial
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 20 >/dev/null)
fin() { # <N> [reply] -- a final pass from the Builder's worktree; prints its exit code
  sites "$1"
  (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-$1 STUB_REPLY="${2:-VERDICT: GO}" bash "$PASS_SH" "$U" "$1" final >"$TMP/out" 2>"$TMP/err"); echo $?; }
round() { [ -e "$B/$U-r$1-reports.md" ] && echo yes || echo no; }
ontop() { git -C "$W" merge-base --is-ancestor main HEAD; echo $?; }
NOGO2=$'- [P2] (class: probe) REBASE-PROBE -- a.sh:1 -- wrong -- bash a.sh\nVERDICT: NO-GO'

# main moves on a file no test of the unit covers: the pass goes on, reading the rebased tip.
echo other > "$REPO/other.txt"; G add -A; G commit -qm other
check "an unrelated main change is rebased onto, and the final pass runs on that tip" "0 0 yes" "$(fin 2 "$NOGO2") $(ontop) $(round 2)"
check "the pass says it rebased" 1 "$(grep -c "^rebased $U onto local main" "$TMP/out")"

# main changes the file the unit's test depends on: red before Codex, on the rebased tip.
echo 'echo broken' > "$REPO/scripts/lib.sh"; G commit -qam 'lib broken'
check "a main change that breaks the unit's test stops the final pass before Codex, with no round file" "2 1 no" \
  "$(fin 3 "$NOGO2") $(grep -c "tests that cover what $U or main changed are red" "$TMP/err") $(round 3)"
check "the unit is on top of main by then" 0 "$(ontop)"
check "a retry without a fix is stopped again, with no round file" "2 1 no" \
  "$(fin 3 "$NOGO2") $(grep -c "tests that cover what $U or main changed are red" "$TMP/err") $(round 3)"
echo 'echo ok' > "$W/scripts/lib.sh"
check "once the test is green the retry goes on to Codex" "0 yes" "$(fin 3 "$NOGO2") $(round 3)"

# A red `# own-lane:` test is skipped by the ordinary run, so the gate runs those on their own, as the merge does.
echo 'echo broken' > "$REPO/scripts/lane-lib.sh"; G commit -qam 'lane-lib broken'
check "a red own-lane test stops the final pass before Codex" "2 no" "$(fin 4 "$NOGO2") $(round 4)"
echo 'echo ok' > "$W/scripts/lane-lib.sh"
check "and once it is green the retry goes on to Codex" "0 yes" "$(fin 4 "$NOGO2") $(round 4)"

# Issue 356: the round file says how long each pre-review step took, so a slow closing pass can be told from a slow
# reviewer. r2 rebased and ran tests with no suite on; r5 is on top of main and runs only the suite.
cfg '.fullSuiteBeforeFinal = true | .testCommand = "echo \"1 passed, 0 failed\""'; echo five > "$W/a.sh"
check "the final pass with the suite on runs" "0 yes" "$(fin 5 "$NOGO2") $(round 5)"
cfg 'del(.fullSuiteBeforeFinal)'
check "a closing pass's report carries one timing line per pre-review step" "1 1 1 1" \
  "$(grep -c '^Pre-review: ' "$B/$U-r2-reports.md") $(grep -cE '^Pre-review: rebase [0-9]+ s, tests [0-9]+ s, suite not run$' "$B/$U-r2-reports.md") \
$(grep -c '^Pre-review: ' "$B/$U-r5-reports.md") $(grep -cE '^Pre-review: rebase not run, tests not run, suite [0-9]+ s$' "$B/$U-r5-reports.md")"

# Issue 385: a closing pass needs a green typecheck when the project sets one up (typecheckCommand), checked before any
# reviewer; a project with none is told so and goes on. These passes are past the default cap of five.
cfg '.reviewLoop.passCap = "20"'
cfg '.typecheckCommand = "echo \"src/x.ts(1,1): error TS2322: TYPE-PROBE\"; exit 1"'; echo six > "$W/a.sh"
check "a closing pass on a red typecheck is refused before any reviewer" "2 1 1 no" \
  "$(fin 6 "$NOGO2") $(grep -c 'a closing pass needs a green typecheck, and `echo .*` is red in' "$TMP/err") $(grep -cx 'src/x.ts(1,1): error TS2322: TYPE-PROBE' "$TMP/err") $(round 6)"
cfg 'del(.typecheckCommand)'
check "a closing pass with no typecheckCommand runs no typecheck and says so" "0 1 yes" \
  "$(fin 6 "$NOGO2") $(grep -cx 'no typecheckCommand set: no typecheck before the closing pass' "$TMP/out") $(round 6)"
cfg '.typecheckCommand = "true"'; echo seven > "$W/a.sh"
check "a green typecheck lets the closing pass run" "0 1 yes 0" \
  "$(fin 7 "$NOGO2") $(grep -cx 'typecheck before the closing pass: green (true)' "$TMP/out") $(round 7) $(grep -c '^typecheck cache: seeded' "$TMP/out")"

# Issue 386: a fresh worktree's typecheck cache is copied from a sibling worktree (same depth, so its paths resolve),
# only where absent and ignored, by temp file and rename; a failed copy is a cold compile, never a failed pass.
SIB=$(dirname "$W")/sib; mkdir -p "$SIB/.cache"; echo SEED > "$SIB/.cache/tc.tsbuildinfo"
echo '.cache/' >> "$(git -C "$W" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
rm -rf "$W/.cache"
cfg '.typecheckCommand = "grep -qx SEED .cache/tc.tsbuildinfo"'; echo eight > "$W/a.sh"
check "a closing pass seeds the typecheck cache from a sibling worktree" "0 1 yes" \
  "$(fin 8 "$NOGO2") $(grep -c "^typecheck cache: seeded 1 file(s) from the worktrees beside $W" "$TMP/out") $(round 8)"
echo OWN > "$W/.cache/tc.tsbuildinfo"
cfg '.typecheckCommand = "grep -qx OWN .cache/tc.tsbuildinfo"'; echo nine > "$W/a.sh"
check "a present typecheck cache is never overwritten" "0 0 OWN" \
  "$(fin 9 "$NOGO2") $(grep -c '^typecheck cache: seeded' "$TMP/out") $(cat "$W/.cache/tc.tsbuildinfo")"
rm -rf "$W/.cache"; chmod 000 "$SIB/.cache/tc.tsbuildinfo"
cfg '.typecheckCommand = "test ! -e .cache/tc.tsbuildinfo"'; echo ten > "$W/a.sh"
check "a seed that cannot be copied leaves a cold typecheck and the pass runs" "0 0 0" \
  "$(fin 10 "$NOGO2") $(grep -c '^typecheck cache: seeded' "$TMP/out") $(ls "$W/.cache/" 2>/dev/null | grep -c '^tc\.tsbuildinfo\.')"
chmod 644 "$SIB/.cache/tc.tsbuildinfo"; rm -rf "$SIB/.cache"; mkdir -p "$SIB/build"; echo SEED > "$SIB/build/x.tsbuildinfo"
cfg '.typecheckCommand = "true"'; echo eleven > "$W/a.sh"
check "only an ignored typecheck cache is seeded" "0 0 absent" \
  "$(fin 11 "$NOGO2") $(grep -c '^typecheck cache: seeded' "$TMP/out") $([ -e "$W/build/x.tsbuildinfo" ] && echo present || echo absent)"
rm -rf "$SIB"
# A typecheck that never ends (a watch-mode command, a held lock) stops the pass naming the check, within its limit.
cfg '.typecheckCommand = "sleep 30"'; echo twelve > "$W/a.sh"; S0=$SECONDS
R=$(COMMANDECK_TYPECHECK_TIMEOUT_S=1 fin 12 "$NOGO2"); D=$((SECONDS - S0))
check "a typecheck past its time limit names the check that gave no result" "2 1 no 1" \
  "$R $(grep -c '^REFUSED: no result from: typecheck\. `sleep 30` ran past 1s' "$TMP/err") $(round 12) $([ "$D" -le 20 ] && echo 1 || echo "slow $D")"
cfg 'del(.typecheckCommand)'

# main changes what the unit changed: a conflict stops the pass, names the file, and leaves the branch as it was.
echo main-side > "$REPO/a.sh"; G commit -qam 'a.sh on main'
printf 'echo unit-side\n' > "$W/a.sh"; git -C "$W" add a.sh; git -C "$W" -c user.name=t -c user.email=t@t commit -qm 'a.sh on the unit'
head=$(git -C "$W" rev-parse HEAD)
check "a conflict stops the pass, names the file, aborts the rebase and leaves the branch as it was" "2 1 1 0 $head" \
  "$(fin 12 "$NOGO2") $(grep -c 'REBASE CONFLICT' "$TMP/err") $(grep -c 'a.sh' "$TMP/err") $(ls -d "$(git -C "$W" rev-parse --git-path rebase-merge)" 2>/dev/null | wc -l | tr -d ' ') $(git -C "$W" rev-parse HEAD)"

# A final on a stopped rebase, with a tracked brief changed, failed only after the commit; both are refused at once, before
# any commit or rebase. The unit's rebase is stopped at a `break` line, then its tracked brief is edited.
echo v1 > "$W/.claude/briefs/tracked-note.md"; git -C "$W" add -f .claude/briefs/tracked-note.md
git -C "$W" -c user.name=t -c user.email=t@t commit -qm 'a tracked brief'
GIT_SEQUENCE_EDITOR='echo break >>' git -C "$W" -c user.name=t -c user.email=t@t rebase -q -i HEAD~1 >/dev/null 2>&1
echo v2 > "$W/.claude/briefs/tracked-note.md"; head=$(git -C "$W" rev-parse HEAD)
check "a final with a rebase in progress and a changed tracked file is refused once, before it commits (issue 451)" "2 1 1 1 1 no 0 $head" \
  "$(fin 12 "$NOGO2") $(grep -c '^REFUSED:' "$TMP/err") $(grep -cx 'REFUSED: 2 checks failed:' "$TMP/err") $(grep -c '^- a rebase is in progress' "$TMP/err") \
$(grep -c '^- tracked files .*tracked-note.md' "$TMP/err") $(round 12) $(grep -c 'rebased\|REBASE CONFLICT' "$TMP/out" "$TMP/err" | awk -F: '{ s += $2 } END { print s }') $(git -C "$W" rev-parse HEAD)"

# Issue 474: a slow pass named no slow step. Each step of a closing pass prints a clock line of its own, start and end, in
# the order the pass runs them. The unit is put back on a base main can take (the conflict and the stopped rebase above
# are undone), then main moves, and the tests that cover the unit's own files run, one of them an own-lane test.
git -C "$W" rebase --abort; git -C "$W" checkout -q -- .; git -C "$W" reset -q --hard HEAD~2; G reset -q --hard HEAD~1
echo again >> "$REPO/other.txt"; G commit -qam 'other moved'
cfg '.reviewLoop.passCap = "40"'
cfg '.typecheckCommand = "true"'; echo thirteen > "$W/n13.txt"
R13=$(fin 13)
check "a pass clocks each step (issue 474)" "0 precheck start,precheck end,rebase start,rebase end,test selection start,test selection end,tests start,tests end,own-lane tests start,own-lane tests end,typecheck start,typecheck end" \
  "$R13 $(sed -n "s/^[0-9][0-9]:[0-9][0-9]:[0-9][0-9] $U pass 13: //p" "$TMP/out" | paste -sd, -)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
