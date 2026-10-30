#!/usr/bin/env bash
# dashboard-built-issue.test.sh -- issue 486: a Builder's row says which review workflow main chose and its newest per-issue
# round, and a per-issue pass is no round of the whole branch. The fixture is fixtures/dashboard-built-setup.sh.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"

# u-issues: main's brief chooses per-issue for issues 7 and 12; its worktree holds two issues' round files, issue 7 the newer.
mkdir -p "$WS/u-issues/.claude/briefs" "$MAIN/.claude/briefs" && touch "$WS/u-issues/.git"
echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$WS/u-issues/.claude/settings.local.json"
printf 'Fix #7 and #12.\nReview workflow: per-issue #7 #12\n' > "$MAIN/.claude/briefs/u-issues-builder-brief.md"
printf 'x\n' > "$WS/u-issues/.claude/briefs/u-issues-issue-12-round-1.md"; touch -t 202001010000 "$WS/u-issues/.claude/briefs/u-issues-issue-12-round-1.md"
printf 'x\n' > "$WS/u-issues/.claude/briefs/u-issues-issue-7-round-2.md"
dash
wf() { jq -c --arg u "$1" 'first(.[]) | [.units.inFlight[]? | select(.unit == $u) | .builder | [.workflow, .issueRound]]' "$T/out/run/project.json" 2>&1; }

# Catches a per-issue Builder whose row says nothing of it, or a default one that reads as per-issue.
check "row_carries_workflow: a per-issue Builder's row carries its workflow and newest issue round; a default one carries default and none" \
  '[["per-issue #7 #12",{"issue":7,"round":2}]] [["default",null]]' "$(wf u-issues) $(wf u-verdicts)"

# Catches a running review blanking the row: its prompt file is newer than every round file and is no round.
BR=$WS/u-issues/.claude/briefs
printf 'x\n' > "$BR/u-issues-issue-7-round-3-prompt-1.md"
dash
check "prompt_file_keeps_last_round: a running round's prompt file leaves the last finished round on the row" \
  '[["per-issue #7 #12",{"issue":7,"round":2}]]' "$(wf u-issues)"

# Catches a removed round file leaving a blank or stale row: each collect reads what is there.
rm -f "$BR/u-issues-issue-7-round-2.md"
dash
check "removed_round_falls_back: the row falls back to the next newest round" \
  '[["per-issue #7 #12",{"issue":12,"round":1}]]' "$(wf u-issues)"
rm -f "$BR/u-issues-issue-12-round-1.md"
dash
check "removed_round_falls_back: with no round file left the row has no round" \
  '[["per-issue #7 #12",null]]' "$(wf u-issues)"

# Catches a per-issue pass shown as a round of the branch: the round, the roster, the steps and the stage list would all
# name a round no round file holds. The stage and the open wait still show it.
printf '%s\n' '{"event":"tool-start","ts":"2026-10-10T12:00:00Z","tool":"Read","use":"t1"}' '{"event":"tool-end","ts":"2026-10-10T12:00:01Z","use":"t1"}' \
  '{"event":"codex-start","ts":"2026-10-10T12:30:00Z","pass":"adversarial","round":1}' '{"event":"codex-end","ts":"2026-10-10T12:40:00Z","pass":"adversarial","round":1,"rc":0}' \
  '{"event":"codex-start","ts":"2026-10-10T12:50:00Z","pass":"issue","round":2}' > "$T/issue.jsonl"
J=$(jq -s --argjson now 0 -f "$SOURCE/scripts/dashboard_builders.jq" "$T/issue.jsonl")
check "issue_pass_is_no_round: the open per-issue pass is no round, roster entry, step or review stage; the stage and the wait show it" \
  '[1,["adversarial"],1,[["building",null],["review",1],["fixing",null]],"review","issue"]' \
  "$(jq -c '[.round, [.passes[].pass], (.steps | length), [.stageHistory[] | [.stage, .round]], .stage, .waiting[0].what]' <<<"$J")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
