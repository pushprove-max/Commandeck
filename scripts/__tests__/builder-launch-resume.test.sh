#!/usr/bin/env bash
# builder-launch-resume.test.sh -- the second call of a risky launch (the one that opens the Builder once the design
# note exists), on a real worktree and the real worktree-setup.sh, with seat.sh, the pass script and orca-ide stood
# in for. What this pins: a --keep given on the second call reaches the Builder's settings before its pane opens,
# as it does on a first call, so a billing exemption asked for late is not silently dropped. And a unit is planned and
# built in one worktree: a clean planning worktree is adopted and the Builder opens in it, based on local main; a
# dirty one is refused before any pane closes, and an unmarked one (another Builder's) is refused as before.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-launch-resume-setup.sh"
launch >"$T/out"; check "the first call opens the design pane and no Builder" "1:0" "$(grep -c 'design pane open' "$T/out"):$(test -e "$T/keep-at-open" && echo 1 || echo 0)"
mkdir -p "$WS/u1/.claude/briefs"; echo note > "$WS/u1/.claude/briefs/u1-design.md"
launch --keep billing >"$T/out"
check "a second call with --keep billing opens the Builder with Stripe kept" "billing:null" \
  "$(cat "$T/keep-at-open" 2>/dev/null):$(jq -c '.enabledPlugins["stripe@claude-plugins-official"]' "$WS/u1/.claude/settings.local.json")"

# --- a unit planned in its own worktree: the real plan-worktree-close.sh, a launch with no --risky ---
cp "$REAL/scripts/plan-worktree-close.sh" "$T/plug/scripts/"
planned u2; echo more > "$P/.claude/plans/u2.md"; git -C "$P" add -A && git -C "$P" -c user.name=t -c user.email=t@t commit -q -m plan-u2
: > "$T/seats"; : > "$T/orca.log"; build u2
check "a clean planning worktree is adopted: the Builder opens in it, on local main, its brief written, the mark gone" "0:1:0:yes:yes:" \
  "$RC:$(grep -cx 'launch builder u2' "$T/seats"):$(grep -c '^worktree create' "$T/orca.log"):$([ "$(git -C "$WS/u2" rev-parse HEAD)" = "$(git -C "$P" rev-parse main)" ] && echo yes || echo no):$([ -s "$WS/u2/.claude/briefs/u2.md" ] && echo yes || echo no):$(mark u2)"
planned u3; echo x > "$WS/u3/stray"; : > "$T/seats"; : > "$T/orca.log"; build u3
check "a dirty one is refused before any pane closes, its file named, the planner's mark kept" "2:1:0:0:u3" \
  "$RC:$(grep -c "^REFUSED: $WS/u3 already exists.*holds stray (untracked)" "$T/out"):$(grep -c . "$T/seats"):$(grep -c '^terminal close' "$T/orca.log"):$(mark u3)"
# Adoption takes the mark before the reset to main: a reset that failed (a stale index lock) left the worktree
# unmarked, so every later Builder and planner launch refused it.
planned u5; touch "$(git -C "$WS/u5" rev-parse --absolute-git-dir)/index.lock"; : > "$T/seats"; build u5
check "a launch that fails after adoption gives the planner its mark back" "1:0:u5" "$RC:$(grep -c . "$T/seats"):$(mark u5)"
rm "$(git -C "$WS/u5" rev-parse --absolute-git-dir)/index.lock"; build u5
check "so the same launch run again adopts it and opens the Builder" "0:1:" "$RC:$(grep -cx 'launch builder u5' "$T/seats"):$(mark u5)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
