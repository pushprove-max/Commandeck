#!/usr/bin/env bash
# covers: scripts/dashboard.sh
# dashboard-merged-unit.test.sh -- issue 343: a unit whose work is in main leaves the in-flight list even while its
# worktree still exists, so no FIXING card and no alert is drawn for it; a pass whose round report is gone shows
# "verdict file gone", never a blank. Only committed evidence says merged: the worktree tip is in main and is not the
# commit its branch began at, or a finished-builds line's merge commit is in main and the worktree does not contain it
# (a squash merge, which leaves no tip in main; a name reused for new work branches after its old merge). A stale line
# naming a commit main lacks, and a fresh worktree on main's own commit, stay live. Fixture: dashboard-built-setup.sh.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"
NOW=$(date +%s); iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
part() { jq -c "first(.[]) | $1" "$T/out/run/project.json" 2>&1; }
gc() { git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$2"; }
# unit <name>: a real worktree on its own branch, a Builder with a long-quiet event log (the QUIET alert's input).
unit() {
  git -C "$MAIN" worktree add -q -b "unit/$1" "$WS/$1" main
  mkdir -p "$WS/$1/.claude" && echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$WS/$1/.claude/settings.local.json"
  { jq -cn --arg t "$(iso $((NOW - 7300)))" '{ts: $t, event: "codex-start", pass: "review", round: 9, model: "m", effort: "high"}'
    jq -cn --arg t "$(iso $((NOW - 7200)))" '{ts: $t, event: "codex-end", pass: "review", round: 9}'; } > "$WS/$1/.claude/builder-events.jsonl"
}
record() { jq -cn --arg m "$(cd "$MAIN" && pwd -P)" --arg u "$1" --arg s "$2" --arg a "$(iso $((NOW - 60)))" '{main: $m, unit: $u, sha: $s, at: $a}' >> "$HOME/.commandeck/builds/demo.jsonl"; }
mkdir -p "$HOME/.commandeck/builds"

unit u-tip; gc "$WS/u-tip" "tip work"
unit u-fresh
unit u-squash; gc "$WS/u-squash" "squash work"
unit u-stale; gc "$WS/u-stale" "stale work"
# u-tip merges as a fast-forward; u-squash as a new commit that the worktree lacks.
git -C "$MAIN" merge -q --ff-only "unit/u-tip"
SQ=$(gc "$MAIN" "feat(u-squash)" && git -C "$MAIN" rev-parse HEAD); record u-squash "$SQ"
# u-reused: an old merge line, then new work branched after it.
OLD=$(gc "$MAIN" "feat(u-reused)" && git -C "$MAIN" rev-parse HEAD); record u-reused "$OLD"
unit u-reused; gc "$WS/u-reused" "new work"
# u-stale: its line names a commit that main does not hold.
record u-stale "$(printf '%040x' 7)"
DNOW=$NOW dash
live() { part '[.units.inFlight[]? | .unit | select(startswith("u-") and . != "u-verdicts")] | sort | join(" ")'; }
check "merged units (tip in main, squash line) are not in flight; fresh, reused and stale-line units are" '"u-fresh u-reused u-stale"' "$(live)"
# The alerts come from a whole collect (data.js), not the --project part dash writes.
alert_units() { rm -rf "$T/out3"; mkdir -p "$T/out3"
  env -u COMMANDECK_SCRATCH -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_WORKSPACES="$WS" COMMANDECK_DASHBOARD_DIR="$T/out3" COMMANDECK_MAIN="$MAIN" \
    DASH_NOW="$NOW" bash "$SOURCE/scripts/dashboard.sh" >"$T/out3.log" 2>&1
  sed 's/^window.DASH = //; s/;$//' "$T/out3/data.js" | jq -c '[.alerts[]? | .id | sub("-[0-9]{9,}$"; "") | select(test("/u-[a-z]+-quiet$")) | sub("^.*/"; "") | sub("-quiet$"; "")] | sort'; }
check "a merged unit with a leftover worktree raises no QUIET alert; the live quiet ones do" '["u-fresh","u-reused","u-stale"]' "$(alert_units)"

# A pass whose report is gone shows "verdict file gone", never a blank: round 9 has one report, so rounds 1-8 are gone.
printf 'Round 9.\nVERDICT: GO\n' > "$WS/u-fresh/.claude/briefs-r9.tmp"; mkdir -p "$WS/u-fresh/.claude/briefs"
mv "$WS/u-fresh/.claude/briefs-r9.tmp" "$WS/u-fresh/.claude/briefs/u-fresh-r9-reports.md"
rm -rf "$T/out/cache"; DNOW=$NOW dash
check "rounds with no report file say verdict file gone; the round with one keeps its own" '["verdict file gone","verdict file gone","VERDICT: GO"]' \
  "$(part '[.units.inFlight[]? | select(.unit == "u-fresh") | .builder.verdicts | .["1"], .["8"], .["9"]]')"
check "a Builder with no report file at all has a verdict for every round" '"verdict file gone"' \
  "$(part '.units.inFlight[]? | select(.unit == "u-stale") | .builder.verdicts["9"]')"

# Issue 354: a unit's plan commit lands on main and the Builder's launch resets the worktree onto it. The tip is in main
# and the branch has no commit of its own yet, so the newest reflog entry is `reset:` and the unit stays in flight.
unit u-plan; gc "$MAIN" "plan(u-plan): plan"; git -C "$WS/u-plan" reset -q --hard main
rm -rf "$T/out/cache"; DNOW=$NOW dash
check "a worktree reset onto its plan commit in main stays in flight" '"u-plan"' \
  "$(part '[.units.inFlight[]? | .unit | select(. == "u-plan")] | join(" ")')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
