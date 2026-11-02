#!/usr/bin/env bash
# seat-judge-rounds.test.sh -- seat.sh launch plan-judge-opus, on the hand-written commandeck.json of fixtures/seat-setup.sh.
# What this pins (#535): an Opus judge round is refused until the Sol seat's rounds reach Opus's own, so Opus never
# judges a plan Sol has not seen; the gate stands aside when plan-judge-sol is off in /plugin config; no round cap.
# Its own file, as seat-launch.test.sh is near the runner's time cap.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"
PWT=$HOME/orca/workspaces/proj/pu; git -C "$PROJ" worktree add -q "$PWT" && echo pu > "$(git -C "$PWT" rev-parse --absolute-git-dir)/commandeck-plan-of"
echo PLAN-DONE > "$T/screen"; mkdir -p "$PWT/.claude/plans"; echo 'the plan' > "$PWT/.claude/plans/pu.md"
printf 'Judge the plan.\nEnd on a line of its own.\n' > "$T/judge-spec.md"
# A judge Sol opens first, to find the scratch folder; then its record is dropped so each case sets its own.
srun launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1
SCR=$(dirname "$(ls "$HOME/.commandeck/scratch/"*/seat-pu-plan-judge-sol.txt)")
SOL=$SCR/seat-pu-plan-judge-sol.txt OPUS=$SCR/seat-pu-plan-judge-opus.txt
# fresh -- no record, no round and no pane left from an earlier case.
fresh() { rm -f "$SOL" "$SOL.rounds" "$OPUS" "$OPUS.rounds" "$T/pane-up"; : > "$T/creates"; }
# opus -- launch Opus; RC and $T/out hold its exit and words.
opus() { srun launch plan-judge-opus pu "$T/judge-spec.md" >"$T/out" 2>&1; RC=$?; }
GATE='REFUSED: a plan-judge-opus round on pu needs a plan-judge-sol seat with at least as many rounds'

fresh; opus
check "an Opus judge with no Sol record is refused" "2:1:0" "$RC:$(grep -c "$GATE" "$T/out"):$(grep -c . "$T/creates")"

fresh; : > "$SOL"; echo 'seat-plan-judge-opus-1 VERDICT: NO-GO' > "$OPUS.rounds"; opus
check "an Opus round ahead of Sol's is refused" "2:1:0" "$RC:$(grep -c "$GATE" "$T/out"):$(grep -c . "$T/creates")"

# One Sol launch collected twice is one round, as the Opus launch collected twice is one: the tag counts, not the line.
fresh; : > "$SOL"; echo 'seat-plan-judge-sol-1 VERDICT: NO-GO' > "$SOL.rounds"
printf 'seat-plan-judge-opus-1 VERDICT: NO-GO\nseat-plan-judge-opus-1 VERDICT: NO-GO\n' > "$OPUS.rounds"; opus
check "an Opus round level with Sol's launches" "0:0:1" "$RC:$(grep -c "$GATE" "$T/out"):$(grep -c . "$T/creates")"

# No cap: a third round of a judge opens, past the two rounds the host's planJudgeRounds once allowed.
fresh; printf 'seat-plan-judge-sol-1 VERDICT: NO-GO\nseat-plan-judge-sol-2 VERDICT: NO-GO\n' > "$SOL.rounds"
srun launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1; RC=$?
check "a third judge round is not capped" "0:0:1" "$RC:$(grep -c 'REFUSED' "$T/out"):$(grep -c . "$T/creates")"

# plan-judge-sol off in /plugin config is no Sol seat: Opus judges alone, as plan-tier.sh runs it.
fresh; jq -n '{pluginConfigs: {"commandeck@commandeck": {options: {planJudgeSolAgent: "claude", codexReviewerAgent: "claude", planJudgeSolEnabled: false}}}}' > "$HOME/.claude/settings.json"; opus
check "an Opus round launches when Sol is off in /plugin config" "0:0:1" "$RC:$(grep -c "$GATE" "$T/out"):$(grep -c . "$T/creates")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
