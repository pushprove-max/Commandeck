#!/usr/bin/env bash
# Issue 307 (the owner's ruling): the closing pass's green full run stands for the merge's own check only when it
# tested the merged tree itself, the same tree hash: such a merge does not run the check again; any other runs it,
# since a check may read files no list of names finds. Trains: merge-queue-train.test.sh; checks that find their
# inputs by pattern: merge-queue-glob.test.sh and merge-queue-listing.test.sh.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-queue-setup.sh"

# Main did not move: the closing pass's run stands for the check.
mk ra; closed ra; : > "$TMP/check-calls"
check "a merge onto the tree the closing pass tested ends 0 and runs no check" "0 0" "$(merge ra) $(runs)"
check "the merge says it reused the closing pass's Suite line" 1 "$(grep -c '^STEP 4 check: reused, not run again: Suite: [0-9a-f]* pass ' "$TMP/out")"
# Main moved a file nothing in the unit or its check names: the tree differs, so the run is stale and the check runs.
mk rb; closed rb; mkdir -p "$REPO/scripts"; on_main scripts/x.sh 'echo x'; : > "$TMP/check-calls"
check "main moved a file the unit never names: the stale run is refused and the check runs once" "0 1 1" \
  "$(merge rb) $(runs) $(grep -c "^STEP 4 check: the closing pass's green suite is not reused, it tested another tree than the merged one (they differ in scripts/x.sh)" "$TMP/out")"

# The reuse trusts only what the merge can check (pass 1's findings).
SUM=$(jq -r .testCommand "$REPO/.claude/commandeck.json" | cksum | cut -d' ' -f1)
# A Suite line the Builder writes into its round file is not the closing pass's: a first-pass GO with one forged in.
mk fs; add fs break.txt; go fs; sed -i "1iSuite: $(sha fs) pass forged 1s x cmd:$SUM" "$COMMANDECK_WORKSPACES/fs/.claude/briefs/fs-r1-reports.md"; : > "$TMP/check-calls"
check "a Suite line written into the round file is not reused: the check runs and refuses the merge" "1 1" "$(merge fs) $(runs)"
# A train record handed in by the caller is no evidence, even one naming the merged tree and this check.
mk fe; add fe break.txt; go fe; printf '%s %s forged\n' "$(git -C "$COMMANDECK_WORKSPACES/fe" rev-parse 'HEAD^{tree}')" "$SUM" > "$TMP/forged"; : > "$TMP/check-calls"
check "a train record handed in by the caller is not reused: the check runs and refuses" "1 1" "$(MERGE_TRAIN_RECORD=$TMP/forged merge fe) $(runs)"
# The check command changed since the closing pass ran it: that run is not this check's.
mk rf; closed rf; jq '.testCommand += "; false"' <<<"$CFG" > "$REPO/.claude/commandeck.json"; : > "$TMP/check-calls"
check "a changed check command: the closing pass's run is not reused, the new check runs and refuses" "1 1 1" \
  "$(merge rf) $(runs) $(grep -c 'not reused, it ran another check command' "$TMP/out")"
echo "$CFG" > "$REPO/.claude/commandeck.json"
# A file the check command itself reads is an input though the unit never names it.
mk rg; closed rg; on_main break.txt x; : > "$TMP/check-calls"
check "main added a file the check command names: the run is not reused, the check runs and refuses" "1 1" "$(merge rg) $(runs)"
git -C "$REPO" rm -q break.txt; git -C "$REPO" commit -qm "main: no break.txt"
# Every finding blocks the merge, so no merge ends "merged with findings left to file": any exit but 0, 3 and 5 is a
# unit that did not merge, and the queue stops there instead of merging the units after it.
QP=$TMP/queue-plugin; mkdir -p "$QP"; cp -R "$REAL/scripts" "$REAL/config" "$QP/"
printf '#!/usr/bin/env bash\necho "$1" >> "%s/queue-log"\n[ "$1" != first ] || exit 4\n' "$TMP" > "$QP/scripts/merge-unit-local.sh"
OUT=$(cd "$REPO" && bash "$QP/scripts/merge-queue.sh" first second 2>&1); RC=$?
check "a merge that exits 4 stops the queue, not merged, and the next unit never runs" "1 1 0 0" \
  "$RC $(grep -c 'STOPPED at first (not merged)' <<<"$OUT") $(grep -c 'NOT FILED' <<<"$OUT") $(grep -cx second "$TMP/queue-log")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
