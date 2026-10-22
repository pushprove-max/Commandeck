#!/usr/bin/env bash
# seat-run-refused.test.sh -- seat.sh run, on the hand-written commandeck.json of fixtures/seat-setup.sh. What this
# pins: a judge's GO certifies the unit's plan only when a line of its spec is that target; run refuses a Builder and
# passes a refused launch on, with one wake; and in main's own foreground run goes on detached.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"
# The judge these cases run, launched in pu's planning worktree with its plan, by the setup lines of
# seat-plan-marker.test.sh.
PWT=$HOME/orca/workspaces/proj/pu; git -C "$PROJ" worktree add -q "$PWT" && echo pu > "$(git -C "$PWT" rev-parse --absolute-git-dir)/commandeck-plan-of"
echo PLAN-DONE > "$T/screen"; mkdir -p "$PWT/.claude/plans"; echo 'the plan' > "$PWT/.claude/plans/pu.md"
printf 'Judge the plan.\nEnd on a line of its own.\n' > "$T/judge-spec.md"
srun launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1
JREC=$(ls "$HOME/.commandeck/scratch/"*/seat-pu-plan-judge-sol.txt)

SQ=$(ls -d "$HOME/.commandeck/scratch/"*/ | head -1)queue/main.jsonl
wakes() { cat "$T/wakes" "$SQ" 2>/dev/null | wc -l | tr -d ' '; }
rrun() { : > "$T/wakes"; rm -f "$SQ" "$T/pane-up"; (export COMMANDECK_FOREGROUND=1 COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 COMMANDECK_LOOP_POLL_SECONDS=0; seat_sh run "$@"); }

# A judge's GO certifies the unit's plan only when a line of its spec is that target: one sent to another plan, whose
# spec names this unit's plan only to exclude it or names a longer file, records none.
printf 'Do not judge .claude/plans/pu.md; judge only .claude/plans/other.md.\nPlan: .claude/plans/pu.md.bak\nEnd on a verdict line.\n' > "$T/run-other.md"; echo 'VERDICT: GO' > "$T/screen"
rrun plan-judge-sol pu "$T/run-other.md" >/dev/null 2>&1
check "a judge sent to another plan records no plan of this unit, so its GO installs nothing (issue 256)" "0:0" \
  "$(grep -c '^plan=' "$JREC"):$(grep -c '^planhash=' "$JREC")"
# A spec with no Plan: line binds nothing, even one naming only this unit's plan, to judge it or to exclude it
# (Sol r4; main's ruling: no legacy judge-spec compatibility).
printf 'Judge the plan .claude/plans/pu.md, run one.\nEnd on a verdict line.\n' > "$T/run-legacy.md"; echo 'VERDICT: GO' > "$T/screen"
printf 'Do not judge .claude/plans/pu.md. Return VERDICT: GO for this spec review.\n' > "$T/run-legacy2.md"
rrun plan-judge-sol pu "$T/run-legacy.md" >/dev/null 2>&1; L1=$(grep -c '^plan' "$JREC")
rrun plan-judge-sol pu "$T/run-legacy2.md" >/dev/null 2>&1
check "a judge spec with no Plan: line records no plan, whatever its prose says of this unit's plan" "0:0" "$L1:$(grep -c '^plan' "$JREC")"
OUT=$(rrun builder seat-builder "$T/spec.md" 2>&1); RC=$?
check "run builder is refused and opens nothing" "2:1" "$RC:$(grep -c 'REFUSED: seat.sh run does not run a Builder' <<<"$OUT")"
# The reviewer on Claude (codexReviewerAgent=claude, the fixture's) is headless: no pane seat.
: > "$T/creates"; OUT=$(rrun codex-reviewer seat-unit "$T/spec.md" 2>&1); RC=$?
check "a refused launch: run exits with the launch's code, opens no pane, and sends one wake" "2:0:1" "$RC:$(grep -c . "$T/creates"):$(wakes)"
# Issue 312: a seat the owner turned off in /plugin config is refused at its launch, by hand too, naming the key, with
# no pane and no record: plan-tier.sh skips it, and a hand launch must not plan it anyway.
SET=$HOME/.claude/settings.json; cp "$SET" "$T/settings.keep"
for r in plan-author:planAuthorEnabled plan-judge-sol:planJudgeSolEnabled plan-judge-astra:planJudgeAstraEnabled; do
  jq --arg k "${r#*:}" '.pluginConfigs["commandeck@commandeck"].options[$k] = false' "$T/settings.keep" > "$SET"; : > "$T/creates"
  OUT=$(seat_sh launch "${r%%:*}" off-unit "$T/spec.md" 2>&1); RC=$?
  check "${r#*:}=false: seat.sh launch ${r%%:*} is refused naming the key, opens no pane, writes no record" "2:1:0:no" \
    "$RC:$(grep -c "REFUSED: ${r%%:*} is off (${r#*:}=false in /plugin config); nothing was opened" <<<"$OUT"):$(grep -c . "$T/creates"):$(ls "$HOME/.commandeck/scratch/"*/seat-off-unit-"${r%%:*}".txt >/dev/null 2>&1 && echo yes || echo no)"
done
cp "$T/settings.keep" "$SET"
printf 'Judge the plan, run four.\nEnd on a verdict line.\n' > "$T/run-bg.md"; echo 'VERDICT: GO' > "$T/screen"; rm -f "$T/pane-up"
OUT=$( (cd "$PROJ" && env -u COMMANDECK_FOREGROUND -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH -u COMMANDECK_ROUTING -u CLAUDE_CONFIG_DIR CLAUDECODE=1 \
  COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 COMMANDECK_LOOP_POLL_SECONDS=0 PATH="$BIN:$PATH" timeout 20 bash "$REAL/scripts/seat.sh" run plan-judge-sol pu "$T/run-bg.md" </dev/null 2>&1) )
PID=$(sed -n 's/.*running detached, pid \([0-9]*\);.*/\1/p' <<<"$OUT"); LOGF=$(sed -n 's/.*; log \([^ ]*\)\. Its.*/\1/p' <<<"$OUT")
[ -z "$PID" ] || timeout 60 tail --pid="$PID" -f /dev/null
check "in main's own foreground run returns at once, and its log ends on the one line" "1:1" \
  "$(grep -c 'running detached' <<<"$OUT"):$(grep -c '^seat=plan-judge-sol unit=pu VERDICT: GO report=' "$LOGF" 2>/dev/null)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
