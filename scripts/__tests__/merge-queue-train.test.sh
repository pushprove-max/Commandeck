#!/usr/bin/env bash
# covers: scripts/merge-queue.sh
# Issue 307 for a train (split from merge-queue.test.sh; its later steps are in merge-queue-train-detach.test.sh):
# it runs the check on the combined tip and on green merges every unit as it would merge alone; on red it finds the
# first unit that turns it red, merges the ones before it, names it, and the ones after it wait.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-queue-setup.sh"

# A green train of three closed units: the train's run, then the first unit reuses its own closing pass (main has
# not moved under it) and the two after it run their own check (main moved under them).
for u in ta tb tc; do mk "$u"; closed "$u"; done; : > "$TMP/check-calls"
OUT=$(cd "$REPO" && bash "$QUEUE" --train "ta@$(sha ta)" "tb@$(sha tb)" "tc@$(sha tc)" 2>&1); RC=$?
check "a green train of three ends 0, runs the check three times, and merges all three" "0 3 3" \
  "$RC $(runs) $(git -C "$REPO" log --format=%s | grep -cE '^feat\(t[abc]\)')"
check "only the first unit's merge reused its closing pass's run" "1 0 0" \
  "$(for u in ta tb tc; do grep -c '^STEP 4 check: reused, not run again: Suite: ' "$COMMANDECK_SCRATCH/merge-$u.log"; done | paste -sd' ' -)"
# A red train where the second unit breaks the combined tip: the first merges, the second is named, the third waits.
mk ba; mk bb; mk bc; echo x > "$COMMANDECK_WORKSPACES/bb/break.txt"
git -C "$COMMANDECK_WORKSPACES/bb" add break.txt; git -C "$COMMANDECK_WORKSPACES/bb" commit -qm "feat(bb): breaks the check"
closed ba; go bb; go bc; : > "$TMP/check-calls"
OUT=$(cd "$REPO" && bash "$QUEUE" --train "ba@$(sha ba)" "bb@$(sha bb)" "bc@$(sha bc)" 2>&1); RC=$?
check "a red train ends 1, merges the first unit only, and the other two are not merged" "1 1 0 0" \
  "$RC $(git -C "$REPO" log --format=%s | grep -c '^feat(ba)') $(git -C "$REPO" log --format=%s | grep -c '^feat(bb)') $(git -C "$REPO" log --format=%s | grep -c '^feat(bc)')"
check "it names the second unit and says the third waits" 1 "$(grep -c '^merge-queue: train red at bb: .*waiting: bc$' <<<"$OUT")"
check "the check ran on the whole train, then on the first unit, then on the first two: three runs" 3 "$(runs)"

# A train never leaves an untested part of itself on main. The check is red on break.txt unless fix.txt is there too.
jq --arg c "echo run >> $TMP/check-calls; [ ! -e break.txt ] || [ -e fix.txt ]" '.testCommand = $c' <<<"$CFG" > "$REPO/.claude/commandeck.json"
# A unit that would refuse (no review proof) leaves the train before its check: the train is the first unit alone.
mk na; mk nb; add na break.txt; add nb fix.txt; go na; : > "$TMP/check-calls"
OUT=$(cd "$REPO" && bash "$QUEUE" --train "na@$(sha na)" "nb@$(sha nb)" 2>&1); RC=$?
check "a unit whose dry run refuses leaves the train, named; the red unit before it is not merged" "1 0 0 1 1" \
  "$RC $(git -C "$REPO" log --format=%s | grep -c '^feat(na)') $(git -C "$REPO" log --format=%s | grep -c '^feat(nb)') \
$(grep -c '^merge-queue: STOPPED at nb (not merged: its dry run refused it' <<<"$OUT") $(grep -c '^merge-queue: train red at na' <<<"$OUT")"
# A green train whose first unit alone is red: the train's run on the combined tip does not stand for the first
# unit's own tree, which the second unit changes in a file the check reads. The first unit's check runs and refuses
# it, so a stop after it (a hold put on the second) never leaves main red.
mk ha; mk hb; add ha break.txt; add hb fix.txt; go ha; go hb; : > "$TMP/check-calls"
OUT=$(cd "$REPO" && bash "$QUEUE" --train "ha@$(sha ha)" "hb@$(sha hb)" 2>&1); RC=$?
check "a train whose first unit is red alone merges neither: the train's run, then the first unit's own" "1 0 0 2" \
  "$RC $(git -C "$REPO" log --format=%s | grep -c '^feat(ha)') $(git -C "$REPO" log --format=%s | grep -c '^feat(hb)') $(runs)"
check "main stays green after it" 0 "$(cd "$REPO" && [ ! -e break.txt ]; echo $?)"
# A train names each unit's sha: a bare unit is refused before anything runs.
check "--train with a unit that has no sha is a usage error" 2 "$(cd "$REPO" && bash "$QUEUE" --train ba >/dev/null 2>&1; echo $?)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
