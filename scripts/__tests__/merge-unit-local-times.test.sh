#!/usr/bin/env bash
# covers: scripts/merge-unit-local.sh
# merge-unit-local.sh's MERGE-TIME lines (#490, #491): one line per step and a total, so a slow merge's time has a name.
# Its own file: merge-unit-local.test.sh runs near its cap.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-unit-local-setup.sh"

# check_cmd <command>: the project's testCommand, which the merge runs at step 4 on the merged tree.
check_cmd() { jq --arg c "$1" '.testCommand = $c' <<<'{}' > "$REPO/.claude/commandeck.json"; }
# secs <step>: the seconds of the MERGE-TIME line of that step; sum: all step lines added; total: the total line.
secs() { sed -n "s/^MERGE-TIME step=$1 .* seconds=//p" "$TMP/out" | head -1; }
sum() { awk -F'seconds=' '/^MERGE-TIME step=/ { s += $2 } END { print s + 0 }' "$TMP/out"; }
total() { sed -n 's/^MERGE-TIME total seconds=//p' "$TMP/out"; }

# #490: steps that met end to end add up to the total; a merge whose time sat in a step the log never named had no
# line to read. The 2 s check puts a known time in one step.
mkdir -p "$REPO/.claude"; check_cmd 'sleep 2'
mk tg1; go tg1
rc=$(merge tg1)
check "step_seconds_add_to_total: a green merge ends 0 and DONE is the last line" "0 DONE" "$rc $(tail -1 "$TMP/out" | cut -c1-4)"
check "step_seconds_add_to_total: the step lines add up to the total line" "$(total)" "$(sum)"
check "step_seconds_add_to_total: the 2 s check shows in the check step, and the sync and rebase steps have a line" "yes yes yes" \
  "$([ "$(secs check)" -ge 2 ] 2>/dev/null && echo yes) $(grep -q '^MERGE-TIME step=sync ' "$TMP/out" && echo yes) $(grep -q '^MERGE-TIME step=rebase ' "$TMP/out" && echo yes)"

# #490: the step a merge died in is closed above its FAILED line, and no MERGE-TIME line comes after FAILED (the
# merge log's end is read by its DONE or FAILED line). A red check is the refusal: no fixture has a rebase conflict.
# The undo line the squash's exit prints after FAILED is older than this and is not what is pinned.
check_cmd 'false'
mk tg2; go tg2
rc=$(merge tg2)
check "failed_merge_still_closes_times: the red check ends 1 and FAILED is the last line, under the squash's undo" "1 FAILED" \
  "$rc $(tail -1 "$TMP/out" | cut -c1-6)"
check "failed_merge_still_closes_times: the check step has its line and there is no total" "1 0" \
  "$(grep -c '^MERGE-TIME step=check ' "$TMP/out") $(grep -c '^MERGE-TIME total' "$TMP/out")"
rm -f "$REPO/.claude/commandeck.json"

# #491: the 12-minute merge was a hung fetch. The fetch times out, the merge refuses, and the time is in the sync step.
printf '#!/bin/sh\nexec sleep 300\n' > "$TMP/hang-ssh"; chmod +x "$TMP/hang-ssh"
git -C "$REPO" remote set-url origin ssh://hang.invalid/x.git
mk tg3
(cd "$REPO" && GIT_SSH_COMMAND="$TMP/hang-ssh" COMMANDECK_SYNC_FETCH_S=2 timeout 60 bash "$MERGE" tg3) > "$TMP/out" 2>&1; rc=$?
check "hung_fetch_shows_as_sync_seconds: the merge refuses (1), FAILED is last, and the sync step took the fetch's time" "1 FAILED yes" \
  "$rc $(tail -1 "$TMP/out" | cut -c1-6) $([ "$(secs sync)" -ge 2 ] 2>/dev/null && [ "$(secs sync)" -le 15 ] && echo yes)"
git -C "$REPO" remote set-url origin "$REPO"

# A total says the whole merge finished, so a merge that leaves an issue to close by hand must not print one. Its step
# lines stay, and the recovery line still names the issue.
mk tg4 'feat(tg4): the unit (#7)'
printf '# tg4\n\n## The issues\n\n1. #7: one\n' > "$COMMANDECK_WORKSPACES/tg4/.claude/briefs/tg4.md"
mkdir -p "$REPO/.claude/briefs"; printf '[7]\n' > "$REPO/.claude/briefs/tg4-issues.json"
go tg4
: > "$TMP/gh-fails"
rc=$(merge tg4)
rm -f "$TMP/gh-fails"
check "exit3_prints_no_total: a refused close ends 3 with its recovery line" "3 1" "$rc $(grep -c '^NOT CLOSED: gh issue close 7 --comment' "$TMP/out")"
check "exit3_prints_no_total: the steps have their lines and there is no total" "yes 0" \
  "$(grep -q '^MERGE-TIME step=' "$TMP/out" && echo yes) $(grep -c '^MERGE-TIME total' "$TMP/out")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
