#!/usr/bin/env bash
# dashboard-built.test.sh -- a Builder's card says how many of its issues are built, read from its evidence file.
# Builders record each issue's status in a table (Issue and Status columns), most under a "## Per issue" heading,
# so a count that read only "## #<n>" headings said 1 built for builds that had built most of their issues, and
# the owner would chase work that was done. What this pins, on copies of two real evidence files (taken
# 2026-10-16; issue numbers carry a leading 1 so the leak check passes): a row whose status starts "built" counts,
# under "## Per issue" or under the title; a "partly built" row does not, even with a heading of its own.
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

export HOME=$T/home
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
env -u COMMANDECK_SCRATCH -u COMMANDECK_HOOK_FIRE_LOG -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_DASHBOARD_DIR="$T/out" COMMANDECK_MAIN="$MAIN" DASH_NOW="$(date +%s)" bash "$SOURCE/scripts/dashboard.sh" --project "$T/out/run" >"$T/out.log" 2>&1
built() { jq -c --arg u "$1" 'first(.[]) | [.units.inFlight[]? | select(.unit == $u) | .builder.built]' "$T/out/run/project.json" 2>&1; }

check "every issue the Per issue table marks built counts as built" \
  '[[12639,12640,12641,12642,12643,12644,12645,12646,12647,12648,12649,12650,12651,12652,12653,12654,12655,12656]]' "$(built help-email-batch-2026-10-16)"
check "a table under the title counts too, and a partly built issue does not, though a heading names it" \
  '[[12556,12617,11775]]' "$(built api-batch-2026-10-16)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
