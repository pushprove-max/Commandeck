#!/usr/bin/env bash
# The owner's checklist is read on screen: it stays short. What this pins, in main's session: a ninth open item is
# refused (the eighth passes, and a deleted or completed item is not open); a subject of 81 characters is refused
# (80 passes); a subject with an id in it (a message id, a commit hash, a hash sign before a number, an issue number
# spelled "issue 336", "issue-336" or "host issue 3147") is refused, while "Trim the 8 open items" passes; a
# TaskUpdate to completed is refused with the delete line and to deleted passes; and a worker session, an unreadable
# task folder and a TaskUpdate that names no subject are not checked. Run: bash hooks/__tests__/checklist-guard.test.sh
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/checklist-guard.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
git init -q -b main "$T/main"; git -C "$T/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$T/main" worktree add -q "$T/wt" -b wt
CFG=$T/cfg; mkdir -p "$CFG/tasks/s1"
items() { rm -f "$CFG/tasks/s1/"*.json; local i; for i in $(seq "$1"); do jq -nc --arg s "${2:-pending}" --argjson i "$i" '{id: ($i | tostring), subject: "item", status: $s}' > "$CFG/tasks/s1/$i.json"; done; }
# call <project dir> <tool> <tool_input json> -- the hook's exit code; its message is in $T/err
call() { jq -cn --arg t "$2" --argjson i "$3" '{tool_name: $t, tool_input: $i, session_id: "s1"}' \
  | env -u CLAUDE_CODE_TASK_LIST_ID CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>"$T/err"; echo $?; }
create() { call "${2:-$T/main}" TaskCreate "$(jq -cn --arg s "$1" '{subject: $s, description: "d"}')"; }

items 7; check "the eighth open item passes" 0 "$(create 'Review the plan')"
items 8; check "a ninth open item is refused, and the refusal says what to do" "2 1" "$(create 'Review the plan') $(grep -c 'TaskUpdate.* status .deleted.' "$T/err")"
items 8 completed; check "completed items are not open" 0 "$(create 'Review the plan')"
items 8 in_progress; check "in-progress items are open" 2 "$(create 'Review the plan')"
items 8 deleted; check "deleted items are not open" 0 "$(create 'Review the plan')"
items 0
S80=$(printf 'x%.0s' $(seq 80))
check "an 80-character subject passes, an 81-character subject is refused" "0 2" "$(create "$S80") $(create "${S80}x")"
check "the refusal for a long subject names the limit and the tool to call again" "1 1" "$(grep -c '80 characters at most; this one has 81' "$T/err") $(grep -c 'TaskCreate' "$T/err")"
for s in 'Reply to msg_abc123 from the relay' 'Merge 4f9a2c1 after the pass' 'Fix #12 first' 'Fix issue 336' 'Fix issue-336' 'Look at host issue 3147' 'Check PR 12' 'Wait on dcap_91ab' 'Ask term_f3 about ctx_77'; do
  check "a subject with an id is refused: $s" 2 "$(create "$s")"
done
check "the refusal names the id and says to use words" "1 1" "$(grep -c 'holds no ids' "$T/err") $(grep -c 'in words' "$T/err")"
for s in 'Trim the 8 open items' 'Decide the rollout order' 'Review the effaced banner' 'Count the 2026 releases' 'Check a 1234567 digit count'; do
  check "a subject with no id passes: $s" 0 "$(create "$s")"
done
check "a TaskUpdate to completed is refused with the delete line" "2 1" \
  "$(call "$T/main" TaskUpdate '{"taskId": "1", "status": "completed"}') $(grep -c 'status .deleted.' "$T/err")"
check "a TaskUpdate to deleted, to in_progress, or with no status passes" "0 0 0" \
  "$(call "$T/main" TaskUpdate '{"taskId": "1", "status": "deleted"}') $(call "$T/main" TaskUpdate '{"taskId": "1", "status": "in_progress"}') $(call "$T/main" TaskUpdate '{"taskId": "1", "activeForm": "Reading"}')"
check "a TaskUpdate that renames an item to a long or id-holding subject is refused" "2 2" \
  "$(call "$T/main" TaskUpdate "$(jq -cn --arg s "${S80}x" '{taskId: "1", subject: $s}')") $(call "$T/main" TaskUpdate '{"taskId": "1", "subject": "Fix issue 336"}')"
items 8
check "a TaskUpdate to rename an item passes even with 8 open (the cap guards creation)" 0 "$(call "$T/main" TaskUpdate '{"taskId": "1", "subject": "Review the plan"}')"
check "a worker session (a linked worktree) is not checked" "0 0" "$(create 'Fix issue 336 now' "$T/wt") $(create 'Review the plan' "$T/wt")"
rm -rf "$CFG/tasks/s1"
check "an unreadable (absent) task folder lets a create through" 0 "$(create 'Review the plan')"
mkdir -p "$CFG/tasks/s1"; echo 'not json' > "$CFG/tasks/s1/1.json"
check "a task file that does not parse lets a create through" 0 "$(create 'Review the plan')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
