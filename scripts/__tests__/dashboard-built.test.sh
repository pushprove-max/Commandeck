#!/usr/bin/env bash
# dashboard-built.test.sh -- a Builder's card says how many of its issues are built, read from its evidence file.
# Builders record each issue's status in a table (Issue and Status columns), most under a "## Per issue" heading,
# so a count that read only "## #<n>" headings said 1 built for builds that had built most of their issues, and
# the owner would chase work that was done. What this pins, on copies of two real evidence files (taken
# 2026-10-16; issue numbers carry a leading 1 so the leak check passes): a row whose status starts "built" counts,
# under "## Per issue" or under the title; a "partly built" row does not, even with a heading of its own.
# A Builder also carries its live context, from its session log, beside the clear line setup recorded for it.
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
env -u COMMANDECK_SCRATCH -u COMMANDECK_HOOK_FIRE_LOG -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_DASHBOARD_DIR="$T/out" COMMANDECK_MAIN="$MAIN" DASH_NOW="$(date +%s)" bash "$SOURCE/scripts/dashboard.sh" --project "$T/out/run" >"$T/out.log" 2>&1
built() { jq -c --arg u "$1" 'first(.[]) | [.units.inFlight[]? | select(.unit == $u) | .builder.built]' "$T/out/run/project.json" 2>&1; }

check "every issue the Per issue table marks built counts as built" \
  '[[12639,12640,12641,12642,12643,12644,12645,12646,12647,12648,12649,12650,12651,12652,12653,12654,12655,12656]]' "$(built help-email-batch-2026-10-16)"
check "a table under the title counts too, and a partly built issue does not, though a heading names it" \
  '[[12556,12617,11775]]' "$(built api-batch-2026-10-16)"
check "a Builder carries the verdict of every round file by its own round, and the newest report's beside it" \
  '[{"1":"VERDICT: NO-GO","2":"VERDICT: GO"},"VERDICT: GO",2]' \
  "$(jq -c 'first(.[]) | .units.inFlight[]? | select(.unit == "u-verdicts") | [.builder.verdicts, .builder.verdict, .builder.verdictRound]' "$T/out/run/project.json" 2>&1)"
check "a Builder's live context from its session log, beside the clear line setup recorded" '[150012,"160000"]' \
  "$(jq -c 'first(.[]) | .units.inFlight[]? | select(.unit == "u-verdicts") | [.builder.context, .builder.clearLine]' "$T/out/run/project.json" 2>&1)"
check "one with no session log has no context to show" '[null]' "$(jq -c 'first(.[]) | [.units.inFlight[]? | select(.unit == "api-batch-2026-10-16") | .builder.context]' "$T/out/run/project.json" 2>&1)"
check "a raised Builder carries the effort main raised it to and why; one launched at the default carries none" '[{"effort":"high","reason":"touches billing"},null]' \
  "$(jq -c 'first(.[]) | [.units.inFlight[]? | select(.unit == "u-verdicts" or .unit == "api-batch-2026-10-16")] | sort_by(.unit) | reverse | map(.builder.raised)' "$T/out/run/project.json" 2>&1)"
# The stage list names each pass by its round, from the Builder's own log.
printf '%s\n' '{"event":"tool-start","ts":"2026-10-10T12:00:00Z","tool":"Read","use":"t1"}' '{"event":"tool-end","ts":"2026-10-10T12:00:01Z","use":"t1"}' \
  '{"event":"codex-start","ts":"2026-10-10T12:30:00Z","pass":"adversarial","round":1}' '{"event":"codex-end","ts":"2026-10-10T12:40:00Z","pass":"adversarial","round":1,"rc":0}' \
  '{"event":"codex-start","ts":"2026-10-10T12:50:00Z","pass":"review","round":2}' > "$T/log.jsonl"
check "each review stage carries its pass's round; building and fixing carry none" '[["building",null],["review",1],["fixing",null],["review",2]]' \
  "$(jq -s --argjson now 0 -f "$SOURCE/scripts/dashboard_builders.jq" "$T/log.jsonl" | jq -c '[.stageHistory[] | [.stage, .round]]')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
