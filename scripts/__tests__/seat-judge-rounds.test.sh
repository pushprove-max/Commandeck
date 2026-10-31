#!/usr/bin/env bash
# seat-judge-rounds.test.sh -- seat.sh caps the judge rounds one plan gets. What this pins: a judge seat that already
# gave review-limits.planJudgeRounds verdicts on a plan is refused and opens no pane, so main rules on the open
# findings instead of buying a third round; a collected verdict is what counts a round, once per launch.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"
PWT=$HOME/orca/workspaces/proj/pr; git -C "$PROJ" worktree add -q "$PWT" && echo pr > "$(git -C "$PWT" rev-parse --absolute-git-dir)/commandeck-plan-of"
printf 'Judge the plan.\nEnd on a verdict line.\n' > "$T/judge-spec.md"
rrun() { rm -f "$T/pane-up"; (export COMMANDECK_SEAT_FORCE=1 COMMANDECK_FOREGROUND=1 COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 COMMANDECK_LOOP_POLL_SECONDS=0; seat_sh run plan-judge-sol pr "$T/judge-spec.md"); }
jl() { rm -f "$T/pane-up"; : > "$T/creates"; COMMANDECK_SEAT_FORCE=1 COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 seat_sh launch plan-judge-sol pr "$T/judge-spec.md" >"$T/out" 2>&1; }

# Two judged rounds are allowed: each collected verdict writes one line tagged with its launch.
echo 'VERDICT: NO-GO' > "$T/screen"
rrun >/dev/null 2>&1
RND=$(ls "$HOME/.commandeck/scratch/"*/seat-pr-plan-judge-sol.txt).rounds
check "round 1's collected verdict is counted once, tagged with its launch" "1:1" \
  "$(grep -c . "$RND" 2>/dev/null):$(grep -c '^seat-plan-judge-sol-[0-9-]* VERDICT: NO-GO$' "$RND" 2>/dev/null)"
rrun >/dev/null 2>&1
check "round 2 still launches and is counted" 2 "$(cut -d' ' -f1 "$RND" | sort -u | grep -c .)"

# A third round started by hand is refused before any pane opens, and says what to do instead.
jl; RC=$?
check "a third round is refused, names the cap, and opens no pane" "2:1:0" \
  "$RC:$(grep -c 'REFUSED: the pr plan has had 2 judge rounds, the review-limits.planJudgeRounds cap of 2; rule on its open findings instead' "$T/out"):$(grep -c . "$T/creates")"

# The cap is per plan: a judge renamed or swapped in after two rounds under another name is still refused.
mv "$RND" "${RND%/*}/seat-pr-plan-judge-oldname.txt.rounds"
jl; RC=$?
check "a judge new to the plan is refused once another judge of it has had two rounds" "2:1:0" \
  "$RC:$(grep -c 'REFUSED: the pr plan has had 2 judge rounds' "$T/out"):$(grep -c . "$T/creates")"
mv "${RND%/*}/seat-pr-plan-judge-oldname.txt.rounds" "$RND"

# A verdict collected twice for one launch is still one round: only distinct launches count.
head -1 "$RND" > "$T/r1" && cat "$T/r1" "$T/r1" > "$RND"
jl; RC=$?
check "one launch's verdict written twice counts as one round, so a second round launches" "0:1" "$RC:$(grep -c . "$T/creates")"
settle pr plan-judge-sol

# The cap is configured, never assumed: an unreadable value refuses the launch.
head -1 "$RND" > "$T/r1" && cp "$T/r1" "$RND"
jq '."review-limits".planJudgeRounds = "two"' "$REAL/config/routing.json" > "$T/bad-routing.json"
rm -f "$T/pane-up"; : > "$T/creates"
ROUTING=$T/bad-routing.json COMMANDECK_SEAT_FORCE=1 COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 seat_sh launch plan-judge-sol pr "$T/judge-spec.md" >"$T/out" 2>&1; RC=$?
check "a cap that is not a whole number refuses the launch and opens no pane" "2:1:0" \
  "$RC:$(grep -c 'REFUSED: cannot read review-limits.planJudgeRounds' "$T/out"):$(grep -c . "$T/creates")"

# Other seats are not capped: a plan author relaunched past two verdicts still opens.
rm -f "$T/pane-up"; : > "$T/creates"
COMMANDECK_SEAT_FORCE=1 COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 seat_sh launch plan-author pr "$T/judge-spec.md" >"$T/out" 2>&1
check "a plan author is not capped by judge rounds" "0:1" "$?:$(grep -c . "$T/creates")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
