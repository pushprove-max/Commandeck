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

# main changes what the unit changed: a conflict stops the pass, names the file, and leaves the branch as it was.
echo main-side > "$REPO/a.sh"; G commit -qam 'a.sh on main'
printf 'echo unit-side\n' > "$W/a.sh"; git -C "$W" add -A; git -C "$W" -c user.name=t -c user.email=t@t commit -qm 'a.sh on the unit'
head=$(git -C "$W" rev-parse HEAD)
check "a conflict stops the pass, names the file, aborts the rebase and leaves the branch as it was" "2 1 1 0 $head" \
  "$(fin 5 "$NOGO2") $(grep -c 'REBASE CONFLICT' "$TMP/err") $(grep -c 'a.sh' "$TMP/err") $(ls -d "$(git -C "$W" rev-parse --git-path rebase-merge)" 2>/dev/null | wc -l | tr -d ' ') $(git -C "$W" rev-parse HEAD)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
