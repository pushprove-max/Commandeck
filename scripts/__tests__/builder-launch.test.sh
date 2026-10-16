#!/usr/bin/env bash
# builder-launch.test.sh -- what a Builder is launched with, read from a hand-written commandeck.json (no setup
# run). What this pins: the default Builder is Opus at effort medium with no advisor, and runs at the effort setup
# recorded, the small tooling Builder too; every Builder launch,
# a risky one included, has the advisor switched off and a brief that says so, whatever advisor an older set-up
# stored (owner's order 2026-10-14; #85: a launch that leaves out --advisor gets Claude Code's default one); a seat
# that names an advisor keeps it; a batch's own headings stay inside the brief's sections the dashboard reads;
# the review-loop answers reach the brief and the build review's flags as saved; and an independent issue the brief
# sizes over setup's line is flagged to main before launch, while a shared one stays in the batch.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home
PROJ=$T/proj CFG=$T/proj/.claude/commandeck.json; mkdir -p "$HOME" "$T/bin" "$PROJ/.claude"
git init -q -b main "$PROJ" && git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
# The claude profile's pass preflight needs only a claude on PATH.
printf '#!/bin/sh\nexit 0\n' > "$T/bin/claude"; chmod +x "$T/bin/claude"
cfg() { jq -n "{version: 1, profile: \"claude\"} + ($1)" > "$CFG"; }
cfg '{}'
in_proj() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH -u COMMANDECK_ROUTING PATH="$T/bin:$PATH" "$@"); }
launch() { in_proj bash "$REAL/scripts/builder-launch.sh" --dry-run "$@" >"$T/brief" 2>"$T/err"; }
printf '## The issues\n1. #1: toy\n' > "$T/batch.md"

# --- the seat a Builder and the other roles launch as ---
route() { in_proj bash -c '. "$0" && pp_route_json builder "" "$1" | jq -c "[.model, .effort, .advisor]"' "$REAL/scripts/paths.sh" "${1:-}"; }
check "the default Builder is Opus at effort medium with no advisor" '["opus","medium",null]' "$(route)"
OFF=CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1
cmd_of() { in_proj env "${@:2}" bash -c '. "$0" && pp_route_json "$1" | jq -r ".cmd // (.argv | join(\" \"))"' "$REAL/scripts/paths.sh" "$1"; }
# The Builder's effort is a setup answer (builder.effort): each one reaches the command the Builder opens with.
for e in low medium high max; do
  cfg "{builder: {effort: \"$e\"}}"
  check "a recorded effort $e: the Builder launches with --effort $e" 1 "$(cmd_of builder | grep -c -- "--effort $e\( \|$\)")"
done
check "the small tooling Builder (--model sonnet) runs at the same recorded effort" '["sonnet","max",null]' "$(route sonnet)"
# The deployed format: a config from before the question, with the model alone, keeps its model at the default effort.
cfg '{builder: {model: "sonnet"}}'
check "a config with no recorded effort reads as before, at the default medium" '["sonnet","medium",null]' "$(route)"
cfg '{builder: {effort: "extreme"}}'
check "an effort that is not a level stops the launch, naming the key" 1 "$(route 2>&1 | grep -c 'builder.effort')"
cfg '{}'
check "a Builder and the headless reviewer launch with the advisor switched off" "1 1" "$(cmd_of builder | grep -c "$OFF") $(cmd_of claude-reviewer | grep -c "$OFF")"
jq '.roles["design-coauthor"].advisor = "opus"' "$REAL/config/routing.json" > "$T/routing.json"
check "a seat that names an advisor keeps it, switched on" "1 0" \
  "$(cmd_of design-coauthor COMMANDECK_ROUTING="$T/routing.json" | grep -c -- '--advisor opus') $(cmd_of design-coauthor COMMANDECK_ROUTING="$T/routing.json" | grep -c "$OFF")"

# --- the brief ---
launch --risky toy-unit "$T/batch.md"
check "a risky launch gets no advisor either, and says so" '1:0' "$(grep -c '^advisor: none' "$T/err"):$(grep -c 'advisor consult' "$T/brief")"
check "and its brief keeps the design check" 1 "$(grep -c '^## Design check' "$T/brief")"
check "the brief's first line names no model: the launch may pick another" 1 "$(grep -c '^You are the Builder for `toy-unit`: one pane in your own worktree\.' "$T/brief")"
# An advisor an older set-up stored is not given, and a stored "none" is not told to consult one.
for a in opus none; do
  cfg "{builder: {advisor: \"$a\"}}"; launch toy-unit "$T/batch.md"
  check "a stored advisor '$a', launched without --small: no advisor, and the brief says so" '1:1:0' \
    "$(grep -c '^advisor: none' "$T/err"):$(grep -c '^This build has no advisor\.' "$T/brief"):$(grep -c 'advisor consult' "$T/brief")"
done
cfg '{}'
# The dashboard's issue list is read from the rendered brief: a batch's sub-headings stay inside "The issues".
printf '# Export batch\n## The issues\n### #3 Export times out\nSee #9 for the old report.\n### #4 Retry the upload\n' > "$T/batch2.md"
launch toy-unit "$T/batch2.md"
check "a batch's issue sub-headings stay inside The issues; its own title stays inside The batch" '[3,9,4]:1' \
  "$(bash "$REAL/scripts/brief-issues.sh" "$T/brief" | jq -c .):$(grep -c '^### Export batch$' "$T/brief")"

# --- the review loop, as setup saves it: strings, as typed ---
cfg '{reviewLoop: {maxRounds: "6", closingPass: "no", smallBuild: "150", maxReviewMinutes: "45.50", maxTestPercent: "40", maxUsd: "25"}}'
launch toy-unit "$T/batch.md"
check "a Builder's brief carries them: the small-build line, the round cap, no closing pass" '1:1:1' \
  "$(grep -c 'under 150 changed lines' "$T/brief"):$(grep -c 'at most 6 rounds' "$T/brief"):$(grep -c 'This project runs no closing pass' "$T/brief")"
check "the build review flags at the saved thresholds" '[45.5, 0.4, 25.0]' \
  "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import collect; print(list(collect.loop_limits(sys.argv[2])))' "$REAL/skills/worktreereview/scripts" "$PROJ")"
cfg '{reviewLoop: {smallBuild: "off"}}'
launch toy-unit "$T/batch.md"
check "small build off: the brief says the first pass is never one reviewer" '1:0' "$(grep -c 'three reviewers at once, never one: this project turned the small build off' "$T/brief"):$(grep -c 'under off' "$T/brief")"

# --- issue sizing: each item's Size line, against setup's line (issueSizing, default 40000 tokens) ---
printf '## The issues\n1. #1: toy\n   Size: scripts/a.sh; shared with 2; ~60K tokens\n2. #2: toy two\n   Size: scripts/a.sh, scripts/b.sh; shared with 1; ~30K tokens\n3. #3: export\n   Size: scripts/export.sh; independent; ~45K tokens\n4. #4: small\n   Size: scripts/c.sh; independent; ~10K tokens\n5. #5: no size\n' > "$T/sized.md"
launch toy-unit "$T/sized.md"
check "an independent issue over the 40K default is flagged to main, with the split proposed" 1 "$(grep -c '^sizing: item 3 (#3) is independent and ~45K tokens to read, over this project.s 40K line: propose it as its own unit' "$T/err")"
check "a shared issue over the line stays in the batch; an independent small one too" 0 "$(grep -cE '^sizing: item (1|2|4) ' "$T/err")"
check "an item with no Size line is named, so the brief lists every one" 1 "$(grep -c '^sizing: item 5 (#5) has no Size line' "$T/err")"
cfg '{issueSizing: "off"}'; launch toy-unit "$T/sized.md"
check "sizing off keeps today's grouping: nothing flagged" 0 "$(grep -c '^sizing:' "$T/err")"
cfg '{issueSizing: "50000"}'; launch toy-unit "$T/sized.md"
check "a line set at setup is the one read: 45K is under 50K" 0 "$(grep -c '^sizing: item 3' "$T/err")"
cfg '{issueSizing: "lots"}'; launch toy-unit "$T/sized.md"
check "a saved line that is not a number stops the launch, naming the key" "2:1" "$?:$(grep -c 'issueSizing' "$T/err")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
