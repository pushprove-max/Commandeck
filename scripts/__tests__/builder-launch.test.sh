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
cfg '{}'

# --- the effort override: main may raise one Builder to high, with a reason; the default stays setup's ---
launch toy-unit "$T/batch.md"
check "no override: the launch says it runs at the setup default, and the brief names no override" '1:0' \
  "$(grep -c '^effort: medium (the setup default)$' "$T/err"):$(grep -c '^effort override:' "$T/brief")"
launch --effort high --reason 'touches billing' toy-unit "$T/batch.md"
check "--effort high: the launch says high, raised by main, and the brief records the default, the raise and the reason" '1:1' \
  "$(grep -c '^effort: high, raised by main: touches billing$' "$T/err"):$(grep -c '^effort override: builder medium -> high: touches billing$' "$T/brief")"
check "the override line sits above the batch, where the dashboard reads no issues" 1 \
  "$(awk '/^effort override:/ { o = NR } /^## The batch/ && !b { b = NR } END { print (o && o < b) ? 1 : 0 }' "$T/brief")"
for e in low max extreme ''; do
  launch --effort "$e" --reason 'r' toy-unit "$T/batch.md"
  check "--effort '$e' is refused, naming the two levels a Builder may run at" '2:1' "$?:$(grep -c "^REFUSED: --effort takes medium or high" "$T/err")"
done
launch --effort high toy-unit "$T/batch.md"
check "--effort with no reason is refused" '2:1' "$?:$(grep -c '^REFUSED: --effort needs --reason' "$T/err")"
cfg '{builder: {effort: "high"}}'; launch --effort medium --reason 'r' toy-unit "$T/batch.md"
check "--effort medium under a setup default of high would lower it, and is refused" '2:1' "$?:$(grep -c '^REFUSED: --effort medium is below this project.s Builder default high' "$T/err")"
launch --effort high --reason 'r' toy-unit "$T/batch.md"
check "--effort at the setup default is allowed, and recorded" '0:1' "$?:$(grep -c '^effort override: builder high -> high: r$' "$T/brief")"
cfg '{}'
# A risky launch is two calls: the first writes the brief and evidence, the second opens the Builder. The second
# opened the Builder with its own options while the records kept the first's (high recorded, medium run). Main's
# ruling 1: a second call with no --effort keeps the recorded effort; one with --effort may change it, and the brief
# and evidence are rewritten before the pane opens. The first call is its dry run, laid out as the worktree it writes.
# The Orca stand-in logs each call, so the effort the pane opens with is read from the command it was given.
RWT=$(in_proj bash -c '. "$0" && echo "$PP_WORKSPACES"' "$REAL/scripts/paths.sh")/risky-unit RENV=() RB=$RWT/.claude/briefs
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$T/orca.log"
case "\$*" in
  "terminal create"*) [ ! -e "$T/slow" ] || sleep 3; touch "$T/pane-up"; echo '{"ok":true,"result":{"terminal":{"handle":"h1"}}}' ;;
  "terminal list"*) [ -e "$T/pane-up" ] && t='[{"handle":"h1","agentIdentity":"claude","worktreeId":"w1","worktreePath":"$RWT"}]' || t='[]'
    echo "{\"ok\":true,\"result\":{\"terminals\":\$t}}" ;;
  "orchestration task-create"*) echo '{"ok":true,"result":{"task":{"id":"task_1"}}}' ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
first() { rm -rf "$RWT" "$HOME/.commandeck" "$T/pane-up"; git -C "$PROJ" worktree prune; in_proj env ${RENV[@]+"${RENV[@]}"} bash "$REAL/scripts/builder-launch.sh" --dry-run --risky "$@" risky-unit "$T/batch.md" >"$T/brief" 2>/dev/null
  git -C "$PROJ" worktree add -q --detach "$RWT" && mkdir -p "$RB" && cp "$T/brief" "$RB/risky-unit.md" && mkdir -p "$PROJ/.claude/briefs" && cp "$T/brief" "$PROJ/.claude/briefs/risky-unit-builder-brief.md" && echo spec > "$RB/risky-unit-design-spec.md"
  grep '^effort override:' "$T/brief" > "$RB/risky-unit-evidence.md"; echo note > "$RB/risky-unit-design.md"; : > "$T/orca.log"; }
second() { in_proj env ${RENV[@]+"${RENV[@]}"} COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 bash "$REAL/scripts/builder-launch.sh" --risky "$@" risky-unit "$T/batch.md" >/dev/null 2>"$T/err"; }
opened() { grep -m1 '^terminal create' "$T/orca.log" | grep -oE -- '--effort [a-z]+' || echo 'no pane'; }
first --effort high --reason 'touches billing'
second
check "first call raised to high, second call with no --effort: the pane opens at high, the brief and evidence unchanged" \
  '--effort high:1:1' "$(opened):$(grep -c '^effort override: builder medium -> high: touches billing$' "$RB/risky-unit.md"):$(wc -l < "$RB/risky-unit-evidence.md" | tr -d ' ')"
first
second --effort high --reason 'design found billing risk'
check "first call at the default, second raises to high: the pane opens at high, and the brief, main's copy and evidence say so" \
  '--effort high:1:1:1' "$(opened):$(grep -c '^effort override: builder medium -> high: design found billing risk$' "$RB/risky-unit.md"):$(grep -c '^effort override: builder medium -> high: design found billing risk$' "$PROJ/.claude/briefs/risky-unit-builder-brief.md"):$(grep -c '^effort changed at Builder launch: medium -> high, reason: design found billing risk$' "$RB/risky-unit-evidence.md")"
check "the rewritten brief differs from the first call's only by the override line (and the blank line under it)" \
  '1' "$(diff "$T/brief" "$RB/risky-unit.md" | grep -c '^[<>] .')"
first --effort high --reason 'touches billing'
second --effort high --reason 'billing and auth'
check "a second call with another reason: the brief's reason is the new one, and the evidence logs the change" '1:1' \
  "$(grep -c ': billing and auth$' "$RB/risky-unit.md"):$(grep -c '^effort changed at Builder launch: high -> high, reason: billing and auth$' "$RB/risky-unit-evidence.md")"
first
second
check "first call at the default, second the same: the pane opens at the setup default, nothing rewritten" '--effort medium:0' \
  "$(opened):$(grep -c '^effort' "$RB/risky-unit-evidence.md")"
# Sol r2: run again while that Builder works, a raising call rewrote its records to high and only then did seat.sh
# refuse, so the running medium Builder's brief and evidence claimed high. A live Builder's records are not touched.
: > "$T/orca.log"; second --effort high --reason billing
check "a raising call while the Builder runs is refused, and its brief and evidence stay at what runs" '2:1:0:0:0' \
  "$?:$(grep -c '^REFUSED: a Builder for risky-unit is already running' "$T/err"):$(grep -c '^effort override:' "$RB/risky-unit.md" "$PROJ/.claude/briefs/risky-unit-builder-brief.md" | awk -F: '{ s += $2 } END { print s }'):$(grep -c '^effort' "$RB/risky-unit-evidence.md"):$(grep -c '^terminal create' "$T/orca.log")"
# Sol r2: a raise whose later write failed left the worktree brief at high, and the retry, reading that, skipped
# every write still owed. Each record is now brought to what runs on its own, so the retry finishes the job.
# Records are replaced whole, so a write is failed here through its directory, not the file's mode.
for d in "$RB" "$PROJ/.claude/briefs"; do
  first; chmod a-w "$d"; second --effort high --reason billing
  r1=$?:$(grep -c '^terminal create' "$T/orca.log"); chmod u+w "$d"; second --effort high --reason billing
  check "a raise that could not write into $d: refused with no pane; the retry opens at high with every record saying so once" \
    '1:0:0:--effort high:1:1:1' "$r1:$?:$(opened):$(grep -c '^effort override: builder medium -> high: billing$' "$RB/risky-unit.md"):$(grep -c '^effort override: builder medium -> high: billing$' "$PROJ/.claude/briefs/risky-unit-builder-brief.md"):$(grep -c '^effort changed at Builder launch: medium -> high, reason: billing$' "$RB/risky-unit-evidence.md")"
done
# Sol r4: the brief was rewritten in place, so a short write (here a 1 KB file-size limit, the brief is ~10 KB) left
# half a brief, which the retry refused as another brief than the first call wrote: the promised retry could not run.
first; (ulimit -f 1; second --effort high --reason billing)
r1=$?:$(grep -c '^terminal create' "$T/orca.log"); second --effort high --reason billing
check "a raise cut short mid-write: no pane; the retry opens at high with every record saying so once" \
  'failed:0:0:--effort high:1:1:1' "$([ "${r1%%:*}" != 0 ] && echo failed || echo 'exit 0'):${r1#*:}:$?:$(opened):$(grep -c '^effort override: builder medium -> high: billing$' "$RB/risky-unit.md"):$(grep -c '^effort override: builder medium -> high: billing$' "$PROJ/.claude/briefs/risky-unit-builder-brief.md"):$(grep -c '^effort changed at Builder launch: medium -> high, reason: billing$' "$RB/risky-unit-evidence.md")"
# Sol r3: two second calls at once, one at the default and one raising, both saw no Builder; the default one opened
# medium while the raising one rewrote the records to high, and only then did seat.sh refuse. The pane is slow to
# open here, so the raise's check falls inside the other's launch: one call at a time, the raise sees it and refuses.
first; touch "$T/slow"
second & sleep 1; in_proj env COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 bash "$REAL/scripts/builder-launch.sh" --risky --effort high --reason billing risky-unit "$T/batch.md" >/dev/null 2>"$T/err2"
r2=$?; wait; rm -f "$T/slow"
check "concurrent second calls, default then raise: one pane at medium, the raise refused, every record at medium" '2:1:--effort medium:0:0' \
  "$r2:$(grep -c '^terminal create' "$T/orca.log"):$(opened):$(grep -c '^effort override:' "$RB/risky-unit.md" "$PROJ/.claude/briefs/risky-unit-builder-brief.md" | awk -F: '{ s += $2 } END { print s }'):$(grep -c '^effort' "$RB/risky-unit-evidence.md")"
# Sol r4: the same race from the other entry point. A Builder opened by hand with seat.sh took no unit lock, so a
# raising second call saw no pane yet and rewrote the records to high under the medium one opening.
first; touch "$T/slow"
in_proj env COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 bash "$REAL/scripts/seat.sh" launch builder risky-unit "$RB/risky-unit.md" --no-advisor >/dev/null 2>&1 &
sleep 1; second --effort high --reason billing
r2=$?; wait; rm -f "$T/slow"
check "a hand-opened Builder and a raising second call at once: one pane at medium, the raise refused, every record at medium" '2:1:--effort medium:0:0' \
  "$r2:$(grep -c '^terminal create' "$T/orca.log"):$(opened):$(grep -c '^effort override:' "$RB/risky-unit.md" "$PROJ/.claude/briefs/risky-unit-builder-brief.md" | awk -F: '{ s += $2 } END { print s }'):$(grep -c '^effort' "$RB/risky-unit-evidence.md")"
# The same fault through the advisor: a seat routing.json gives one keeps it unless --small, and the brief says which;
# only the effort may change between the calls, so a second call that changes the advisor is refused.
jq '.roles.builder.advisor = "opus"' "$REAL/config/routing.json" > "$T/routing.json"; RENV=(COMMANDECK_ROUTING="$T/routing.json")
first
second --small
check "first call kept the advisor, second drops it with --small: refused before any pane opens" '2:1:0' \
  "$?:$(grep -c '^REFUSED: this call renders another brief' "$T/err"):$(grep -c '^terminal create' "$T/orca.log")"
RENV=(); rm -rf "$RWT" "$T/bin/orca-ide"; git -C "$PROJ" worktree prune

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
