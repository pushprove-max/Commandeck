#!/usr/bin/env bash
# builder-launch-resume-rollback.test.sh -- a unit planned in its own worktree, launched with no --risky: a launch that
# fails after adoption takes its own files back and gives the planner its mark back, unless a pane opened in the
# worktree; an unmarked one (another Builder's) is refused as before. The fixture is builder-launch-resume.test.sh's.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-launch-resume-setup.sh"
cp "$REAL/scripts/plan-worktree-close.sh" "$T/plug/scripts/"
# Pass 2: a launch that failed after it wrote the brief and the Builder settings (here, a routing log it cannot
# append to) gave the mark back but left both, so every retry's adoption refused them. The launch's own files go,
# and the planner's settings come back byte for byte.
planned u6; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS bash "$T/plug/scripts/worktree-setup.sh" "$WS/u6" >/dev/null 2>&1)
cp "$WS/u6/.claude/settings.local.json" "$T/u6-settings"
skip() { batchfor u6; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS "$@" bash "$T/plug/scripts/builder-launch.sh" --skip-plan --reason retry-test u6 "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?; }
: > "$T/seats"; skip COMMANDECK_ROUTING_LOG=.
check "a launch that fails after its brief and Builder settings are written takes both back, and the mark comes back" "1:0:0:same:u6" \
  "$RC:$(grep -c . "$T/seats"):$(ls "$WS/u6/.claude/briefs" 2>/dev/null | grep -c '^u6'):$(cmp -s "$T/u6-settings" "$WS/u6/.claude/settings.local.json" && echo same || echo changed):$(mark u6)"
skip
check "so the same launch run again adopts it and opens the Builder" "0:1:" "$RC:$(grep -cx 'launch builder u6' "$T/seats"):$(mark u6)"
# The same for a risky launch whose design pane did not open: its design spec, left behind, made the retry read
# as the second call and wait for a design note no pane would write.
planned u7; touch "$T/seat-fails"; : > "$T/seats"
batchfor u7; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS bash "$T/plug/scripts/builder-launch.sh" --risky u7 "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?
check "a risky launch whose design pane fails takes its design spec and brief back, and the mark comes back" "1:0:u7" "$RC:$(ls "$WS/u7/.claude/briefs" 2>/dev/null | grep -c '^u7'):$(mark u7)"
rm "$T/seat-fails"
batchfor u7; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS bash "$T/plug/scripts/builder-launch.sh" --risky u7 "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?
check "so the retry adopts it and opens the design pane" "0:1:" "$RC:$(grep -cx 'launch design-coauthor u7' "$T/seats"):$(mark u7)"
# Pass 3: seat.sh can fail after its pane opened (its last screen read, after the dispatch). The rollback then took
# the brief and settings from under the running Builder and gave its worktree the planner's mark, so the next launch
# could adopt it under that Builder. A pane open in the worktree keeps the launch's state, and says so.
planned u8; touch "$T/seat-opens-fails"; : > "$T/seats"; build u8
check "a launch whose seat fails after its pane opened keeps the Builder's brief and settings, names the pane, gives no mark back" "1:yes:yes:1:" \
  "$RC:$([ -s "$WS/u8/.claude/briefs/u8.md" ] && echo yes || echo no):$([ -f "$WS/u8/.claude/settings.local.json" ] && echo yes || echo no):$(grep -c 'term_b8' "$T/out"):$(mark u8)"
rm "$T/pane-open"; planned u9
batchfor u9; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS bash "$T/plug/scripts/builder-launch.sh" --risky u9 "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?
check "the same for a risky launch's design pane: its spec stays, so the retry waits for the note that pane writes" "1:yes:" \
  "$RC:$([ -s "$WS/u9/.claude/briefs/u9-design-spec.md" ] && echo yes || echo no):$(mark u9)"
rm "$T/pane-open"; planned u10; touch "$T/list-fails"; build u10
check "and when the pane list cannot be read, nothing says no pane opened: the launch's files stay too" "1:yes:1:" \
  "$RC:$([ -s "$WS/u10/.claude/briefs/u10.md" ] && echo yes || echo no):$(grep -c 'pane list could not be read' "$T/out"):$(mark u10)"
rm "$T/seat-opens-fails" "$T/pane-open" "$T/list-fails"
git -C "$P" worktree add -q "$WS/u4"; : > "$T/seats"; build u4
check "an existing unmarked worktree (another Builder's) is refused as before" "2:1:0" \
  "$RC:$(grep -c "^REFUSED: $WS/u4 already exists" "$T/out"):$(grep -c . "$T/seats")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
