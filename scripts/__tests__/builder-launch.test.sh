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

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
