#!/usr/bin/env bash
# seat-plan-judges.test.sh -- what seat.sh types to a plan judge, on the hand-written commandeck.json of
# fixtures/seat-setup.sh. What this pins (#546 #547 #549, #538): the judge's three asks (restate each section, a smaller
# change, every named item exists or is marked new) ride its typed prompt and no author's; a driven judge reads each
# plan version in full and an undriven one keeps its one round; plan seats stay outside the Builder cap.
# Its own file, as seat-launch.test.sh is near the runner's time cap.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"
PWT=$HOME/orca/workspaces/proj/pu; git -C "$PROJ" worktree add -q "$PWT" && echo pu > "$(git -C "$PWT" rev-parse --absolute-git-dir)/commandeck-plan-of"
echo PLAN-DONE > "$T/screen"; mkdir -p "$PWT/.claude/plans"; echo 'the plan' > "$PWT/.claude/plans/pu.md"
printf 'Judge the plan.\nEnd on a line of its own.\n' > "$T/judge-spec.md"
# prompt <role> -- the text typed to that seat, as its record keeps it.
prompt() { cat "$HOME/.commandeck/scratch/"*/"seat-pu-$1.txt.prompt" 2>/dev/null; }
# fresh -- no pane or record of pu's seats left from an earlier case.
fresh() { rm -f "$T/pane-up" "$HOME/.commandeck/scratch/"*/seat-pu-plan-*.txt*; : > "$T/creates"; }

fresh; srun launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1
P=$(prompt plan-judge-sol)
check "a plan judge's typed prompt asks it to restate each plan section" 1 \
  "$(grep -c 'First restate each section of the plan in one or two plain sentences of your own, in your report' <<<"$P")"
check "a section that cannot be restated is named as a blocking finding in the prompt" 1 \
  "$(grep -c 'a section you cannot restate, or whose restatement contradicts the plan, is a blocking finding naming the section' <<<"$P")"
check "a plan judge's earlier asks are unchanged" "1:1:1" \
  "$(grep -c 'does not say how the previous version still works against it is a finding' <<<"$P"):$(grep -c 'an untraced requirement is a finding' <<<"$P"):$(grep -c 'makes your verdict NO-GO unless the owner approved that limit by name' <<<"$P")"
check "a plan judge's typed prompt asks whether a smaller change fully solves the problem" 1 \
  "$(grep -c 'Is there a smaller change that fully solves the problem? A yes is a finding naming the smaller change and why it fully solves it' <<<"$P")"
check "a plan judge's typed prompt carries the readiness check" 1 \
  "$(grep -c 'Confirm every file, function and test the plan names exists or is marked new' <<<"$P")"
check "the prompt makes a named item neither found nor marked new a blocking finding" 1 \
  "$(grep -c 'a named item neither found nor marked new is a blocking finding naming it' <<<"$P")"

# #554: the judge lists everything it can defend in one pass and owns what it missed on a re-judge.
check "a plan judge's typed prompt asks for every defensible finding in one pass, ranked by severity" 1 \
  "$(grep -c 'List every finding you can defend in one pass, ranked by severity, before the verdict' <<<"$P")"
check "a plan judge's typed prompt asks for the whole-plan re-read statement and a check of every earlier finding on a re-judge" 1 \
  "$(grep -c 'On a re-judge, re-read the whole plan, state `Re-read: whole plan`, and check every earlier finding' <<<"$P")"
check "a plan judge's typed prompt asks for later findings visible earlier to be marked missed earlier, with a count" 1 \
  "$(grep -c 'mark it "missed earlier" in its text and end your findings with `Missed earlier: <n>`' <<<"$P")"

# The launch is driven (srun exports COMMANDECK_DRIVER=1): each round reads one plan version in full.
check "a driven judge's prompt makes each round a full read of one version" 1 "$(grep -c 'Each round is a full read of one plan version\.' <<<"$P")"
check "a driven judge's prompt carries no recheck-only sentence" 0 "$(grep -c 'recheck only' <<<"$P")"
fresh; (unset COMMANDECK_DRIVER; COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch plan-judge-sol pu "$T/judge-spec.md") >"$T/out" 2>&1
check "an undriven judge's prompt keeps the one-round sentence" "1:0" \
  "$(prompt plan-judge-sol | grep -c 'a revised plan is not judged again\.'):$(prompt plan-judge-sol | grep -c 'Each round is a full read')"
check "an undriven judge's prompt no longer says to recheck only the change log" 0 "$(prompt plan-judge-sol | grep -c 'recheck only')"

fresh; srun launch plan-author pu "$T/judge-spec.md" >"$T/out" 2>&1
check "a plan-author seat's typed prompt carries none of the judge asks" 0 \
  "$(prompt plan-author | grep -c -e 'First restate each section' -e 'smaller change that fully solves' -e 'Confirm every file, function and test')"
check "a plan-author seat's typed prompt carries none of the list-everything asks" 0 \
  "$(prompt plan-author | grep -c -e 'List every finding you can defend' -e 'Re-read: whole plan' -e 'Missed earlier')"

# Plan seats stay outside the maxBuilders cap: with the cap full a judge opens, and a Builder is still refused beside it.
SCR=$(dirname "$(ls "$HOME/.commandeck/scratch/"*/seat-pu-plan-author.txt)")
cap() { jq -n --argjson o "$1" '{pluginConfigs: {"commandeck@commandeck": {options: ({planJudgeSolAgent: "claude", codexReviewerAgent: "claude"} + $o)}}}' > "$HOME/.claude/settings.json"; }
git -C "$PROJ" worktree add -q "$HOME/orca/workspaces/proj/seat-b2"
printf 'path:/elsewhere/other\tBuilder — other\th9\t1\n' >> "$SCR/pane-titles.tsv"; echo '{"handle":"h9","agentIdentity":"claude"}' > "$T/extra"
cap '{"maxBuilders": 1}'
fresh; srun launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1; RC=$?
check "a plan judge seat opens while the Builder cap is full" "0:1" "$RC:$(grep -c . "$T/creates")"
: > "$T/creates"; COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch builder seat-b2 "$T/spec.md" >"$T/out" 2>&1; RC=$?
check "a Builder past the cap is still refused while plan seats run" "2:1:0" \
  "$RC:$(grep -cx 'REFUSED: 1 Builders are running (h9), the maxBuilders cap in /config; close one or raise the cap' "$T/out"):$(grep -c . "$T/creates")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
