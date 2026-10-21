# Sourced by dashboard-built.test.sh, dashboard-built-costs.test.sh, dashboard-built-planning.test.sh,
# dashboard-built-plan-worktrees.test.sh and dashboard-built-seats.test.sh: a scratch
# main with Builder worktrees (two from the evidence fixtures, u-verdicts with its round files and session log), stubbed
# orca-ide and gh, check, and dash (one dashboard.sh collect). Five files, not one: one file of every case ran 207 s at
# load ~150, past the runner's 120 s per-file cap, and the owner ruled that no file raises it.
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'chmod 755 "$T/locked" 2>/dev/null; rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

export HOME=$T/home COMMANDECK_CODEX_REVIEW_HOME=$T/review-home
unset CLAUDE_CONFIG_DIR  # a session run under a profile would point the readers at its folder, not this HOME's
MAIN=$T/demo BIN=$T/bin WS=$T/ws
mkdir -p "$HOME" "$BIN"
git init -q -b main "$MAIN" && git -C "$MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/orca-ide"; cp "$BIN/orca-ide" "$BIN/gh"; chmod +x "$BIN"/*
# builder <unit>: a Builder's worktree holding the unit's evidence file from the fixtures.
builder() {
  mkdir -p "$WS/$1/.claude/briefs" && touch "$WS/$1/.git"
  echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$WS/$1/.claude/settings.local.json"
  cp "$SOURCE/scripts/__tests__/fixtures/evidence/$1-evidence.md" "$WS/$1/.claude/briefs/"
}
builder help-email-batch-2026-10-16; builder api-batch-2026-10-16
# Each round file's own verdict, so each finished pass shows its own. r1 is older than
# r2, so r2 stays the newest report; a round file named with no number has no round.
V=$WS/u-verdicts/.claude/briefs; mkdir -p "$V" && touch "$WS/u-verdicts/.git"
echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$WS/u-verdicts/.claude/settings.local.json"
printf 'Round 2 review.\nVERDICT: GO\n\n' > "$V/u-verdicts-r2-reports.md"
printf 'Round 1 review.\n- [P1] one -- f:1 -- why\nVERDICT: NO-GO\n' > "$V/u-verdicts-r1-reports.md"; touch -t 202001010000 "$V/u-verdicts-r1-reports.md"
printf 'VERDICT: GO\n' > "$V/u-verdicts-rx-reports.md"; touch -t 202001010000 "$V/u-verdicts-rx-reports.md"
# A Builder main raised: its brief carries the override line builder-launch.sh writes, so its card can say so.
printf '# u-verdicts -- Builder batch\n\neffort override: builder medium -> high: touches billing\n\n## The batch\n' > "$V/u-verdicts.md"
mkdir -p "$MAIN/.claude" "$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$WS/u-verdicts")"
echo '{"builder": {"clearLine": "160000"}}' > "$MAIN/.claude/commandeck.json"
echo '{"type":"assistant","message":{"usage":{"cache_read_input_tokens":150000,"input_tokens":12}}}' > "$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$WS/u-verdicts")/s.jsonl"
dash() { env -u COMMANDECK_SCRATCH -u COMMANDECK_HOOK_FIRE_LOG -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_DASHBOARD_DIR="$T/out" COMMANDECK_MAIN="$MAIN" DASH_NOW="${DNOW:-$(date +%s)}" bash "$SOURCE/scripts/dashboard.sh" --project "$T/out/run" >"$T/out.log" 2>&1; }
built() { jq -c --arg u "$1" 'first(.[]) | [.units.inFlight[]? | select(.unit == $u) | .builder.built]' "$T/out/run/project.json" 2>&1; }
