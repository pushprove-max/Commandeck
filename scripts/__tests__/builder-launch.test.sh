#!/usr/bin/env bash
# builder-launch.sh --review-base (issue 430): main names the commit a unit's whole-branch passes read from, so a unit
# asked to re-review work already on main reads it. The base lives in main's briefs folder, where the Builder never
# edits, and a sha that is not a commit on main is refused: a mistyped or unmerged one made every pass diff a wrong range.
set -u
. "$(dirname "$0")/fixtures/builder-launch-resume-setup.sh"
# rb <unit> <sha> -- a launch of <unit> with --review-base; RC and $T/out hold its exit and output.
rb() { batchfor "$1"; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS \
  bash "$T/plug/scripts/builder-launch.sh" --review-base "$2" "$1" "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?; }

FULL=$(git -C "$P" rev-parse HEAD)
rb rb1 "${FULL:0:10}"
check "--review-base writes main's review-base file with the full sha (issue 430)" "0 $FULL" \
  "$RC $(cat "$P/.claude/briefs/rb1-review-base.md" 2>/dev/null)"

git -C "$P" checkout -q -b side && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m side
OFF=$(git -C "$P" rev-parse HEAD); git -C "$P" checkout -q main
rb rb2 "$OFF"
check "--review-base refuses a commit that is not on main (issue 430)" "2 1 no-file no-worktree" \
  "$RC $(grep -c "REFUSED: --review-base $OFF is not a commit on main" "$T/out") $([ -e "$P/.claude/briefs/rb2-review-base.md" ] && echo file || echo no-file) $([ -e "$WS/rb2" ] && echo worktree || echo no-worktree)"

# Issue 560: the launcher and the merge read one plan reader (paths.sh pp_plan_section_paths and pp_brief_plans). A plan
# named in plain text under Plan passes the launcher, and the merge, reading main's copy of the brief the launch wrote,
# finds that same plan, so a deletion the plan lists is not refused at the merge for a plan it read as empty.
build pr1
check "the launcher and the merge read the same plan paths" "0 .claude/plans/toy.md .claude/plans/toy.md" \
  "$RC $(. "$T/plug/scripts/paths.sh" >/dev/null 2>&1; pp_plan_section_paths "$T/batch.md" | paste -sd' ' -) $(. "$T/plug/scripts/paths.sh" >/dev/null 2>&1; pp_brief_plans "$P/.claude/briefs/pr1-builder-brief.md" | paste -sd' ' -)"

# Issue 640: a Plan heading indented up to three spaces is still the Plan section; missed, the launcher finds no plan.
printf '# b\n\n  ## Plan\n\n.claude/plans/pind.md\n' > "$T/pind.md"
check "Plan heading indented is read" ".claude/plans/pind.md" "$(. "$T/plug/scripts/paths.sh" >/dev/null 2>&1; pp_plan_section_paths "$T/pind.md" | paste -sd' ' -)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
