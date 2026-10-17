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
# A launch refuses a batch with no Prior art section, or no Plan naming a plan committed in main, so every fixture
# carries both.
P='\n## Prior art\nInternal tooling; no outside library.\n\n## Plan\n.claude/plans/toy.md\n'
mkdir -p "$PROJ/.claude/plans" && echo plan > "$PROJ/.claude/plans/toy.md"
git -C "$PROJ" add .claude/plans/toy.md && git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q -m plan
printf "## The issues\n1. #1: toy\n$P" > "$T/batch.md"

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
# The plan main asks for before every build is written on Opus at high effort, whatever the build's size.
check "the plan-author seat is Claude on Opus at effort high" '["opus","high"]:1' \
  "$(in_proj bash -c '. "$0" && pp_route_json plan-author | jq -c "[.model, .effort]"' "$REAL/scripts/paths.sh"):$(cmd_of plan-author | grep -c '^claude \| claude ')"
# Owner's ruling 2026-10-17: the Panel's second planner, and the judges, which read the plans and never
# edit them: Sol and Astra on Codex, and a Claude judge for a project set up with no Codex.
check "the second planner writes on Fable at high; the three plan judges are read-only, two Codex and one Claude" \
  'claude fable high false|codex sol high true|codex astra high true|claude sonnet high true' \
  "$(jq -r '[.roles["plan-author-second", "plan-judge-sol", "plan-judge-astra", "plan-judge-claude"]
    | "\(.agent) \(.model) \(.effort) \(.sandbox == "read-only" or ((.tools // []) | index("Write") != null))"] | join("|")' "$REAL/config/routing.json")"
# Owner's ruling 2026-10-17: setup asks per plan seat whether it runs on the fast tier (planFast), default off.
FASTC='--settings '\''{"fastMode":true}'\'
cfg '{profile: "claude-openai", codexModels: {"plan-judge-sol": "gpt-6.1-sol"}, planFast: ["plan-author", "plan-judge-sol"]}'
check "a plan seat set to fast at setup launches on the fast tier; a seat left out does not" '1:1:0' \
  "$(cmd_of plan-author | grep -cF -- "$FASTC"):$(cmd_of plan-judge-sol | grep -c 'service_tier=fast'):$(cmd_of plan-author-second | grep -cF -- "$FASTC")"
cfg '{profile: "claude-openai", codexModels: {"plan-judge-sol": "gpt-6.1-sol"}}'
check "with no fast answer saved, the plan seats launch on the default tier" '0:1' \
  "$(cmd_of plan-author | grep -cF -- "$FASTC"):$(cmd_of plan-judge-sol | grep -c 'service_tier=default')"
cfg '{}'
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
printf "# Export batch\n## The issues\n### #3 Export times out\nSee #9 for the old report.\n### #4 Retry the upload\n$P" > "$T/batch2.md"
launch toy-unit "$T/batch2.md"
check "a batch's issue sub-headings stay inside The issues; its own title stays inside The batch" '[3,9,4]:1' \
  "$(bash "$REAL/scripts/brief-issues.sh" "$T/brief" | jq -c .):$(grep -c '^### Export batch$' "$T/brief")"
# A batch that never asked whether a standard, library or service already does the job is how hand-built
# versions of solved problems get in; one with no Prior art heading is refused, dry run included.
printf '## The issues\n1. #1: build an OTP input\nNo prior art here, just a mention.\n' > "$T/noprior.md"
launch toy-unit "$T/noprior.md"
check "a batch with no Prior art section is refused, naming the section and the registry" "2 1 1" \
  "$? $(grep -c 'Prior art' "$T/err") $(grep -c '.claude/paved-road.md' "$T/err")"
launch toy-unit "$T/batch.md"
check "a batch with its Prior art section is taken" 0 "$?"
# Owner's order 2026-10-17: a plan is written before every build, and the build starts from it. A batch that names
# no plan, one that is not there, or one main has not committed (the worktree is cut from main's commit, so the
# Builder could not read it) is refused, dry run included, unless main skips the plan with a reason.
printf '## The issues\n1. #1: toy\n\n## Prior art\nNone.\n' > "$T/noplan.md"
for p in gone draft link dir empty branch; do
  printf '## The issues\n1. #1: toy\n\n## Prior art\nNone.\n\n## Plan\n.claude/plans/%s.md\n' "$p" > "$T/${p}plan.md"
done
echo draft > "$PROJ/.claude/plans/draft.md"
# Sol r1: a committed directory, a broken link or an empty file at the path gave the Builder no plan, and passed.
ln -s /nonexistent "$PROJ/.claude/plans/link.md"; mkdir "$PROJ/.claude/plans/dir.md"; echo x > "$PROJ/.claude/plans/dir.md/x"; : > "$PROJ/.claude/plans/empty.md"
git -C "$PROJ" add .claude/plans/link.md .claude/plans/dir.md .claude/plans/empty.md && git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q -m 'not plans'
# Sol r1: the worktree is cut from local main, not the main checkout's HEAD: a plan committed only on the branch
# that checkout has out never reaches the Builder.
git -C "$PROJ" checkout -q -b plan-only && echo plan > "$PROJ/.claude/plans/branch.md"
git -C "$PROJ" add .claude/plans/branch.md && git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q -m 'branch plan'
for b in noplan goneplan draftplan linkplan dirplan emptyplan branchplan; do
  launch toy-unit "$T/$b.md"
  check "a batch whose Plan is $b is refused, naming the section and where the plan goes" '2:1:0' \
    "$?:$(grep -c '^REFUSED: .*## Plan.*\.claude/plans/' "$T/err"):$(wc -c < "$T/brief" | tr -d ' ')"
done
git -C "$PROJ" checkout -q main
launch --skip-plan toy-unit "$T/noplan.md"
check "--skip-plan with no reason is refused" '2:1' "$?:$(grep -c '^REFUSED: --skip-plan needs --reason' "$T/err")"
launch --skip-plan --reason 'a=b' toy-unit "$T/noplan.md"
check "--skip-plan with an = in its reason is refused: the routing log reads key=value words" '2:1' "$?:$(grep -c '^REFUSED: --skip-plan needs --reason' "$T/err")"
launch --skip-plan --reason 'owner chose no plan' toy-unit "$T/noplan.md"
check "--skip-plan with a reason launches, says so on stderr, and the brief records it above the batch" '0:1:1' \
  "$?:$(grep -c '^plan skipped: owner chose no plan$' "$T/err"):$(awk '/^plan skipped: owner chose no plan$/ { o = NR } /^## The batch/ && !b { b = NR } END { print (o && o < b) ? 1 : 0 }' "$T/brief")"

# --- Auto, the default answer to "Write a plan first?" (owner's ruling 2026-10-17): a tier from the trigger file ---
tier() { printf '## The issues\n%b\n## Prior art\nNone.\n' "$1" > "$T/tb.md"; in_proj bash "$REAL/scripts/plan-tier.sh" "$T/tb.md" > "$T/tier" 2>&1; }
tier '1. #1: fix tenant isolation in the export\n'
check "a batch that touches tenant isolation is a Panel, and says the trigger" 1 "$(grep -c '^tier: Panel (trigger: tenant isolation;' "$T/tier")"
tier '1. #1: fix a typo in the README\n2. #2: update the setup docs\n'
check "a batch whose every item is a typo or docs needs no plan, and says how to launch" '1:1:0' \
  "$(grep -c '^tier: No plan (trigger: ' "$T/tier"):$(grep -c "^launch: builder-launch.sh --skip-plan --reason 'Auto picked No plan: " "$T/tier"):$(grep -c '^seat:' "$T/tier")"
tier '1. #1: add a CSV export\n'
check "anything else is Plan + judge: one planner and the Sol judge" '1:plan-author opus|plan-judge-sol sonnet (as plan-judge-claude)' \
  "$(grep -c '^tier: Plan + judge (trigger: everything else;' "$T/tier"):$(sed -n 's/^seat: //p' "$T/tier" | paste -sd'|' -)"
tier '1. #1: fix a typo in the README\n2. #2: add a CSV export\n'
check "a typo beside new logic is unsure: one tier up, to Plan + judge, naming why" 1 "$(grep -c '^tier: Plan + judge (trigger: typo matched only some items, so one tier up;' "$T/tier")"
# A subheading inside "The issues" stays in scope: only a heading of its level or higher closes it.
tier '1. #1: fix a typo\n\n### Details\nChange authentication permissions for every tenant.\n'
check "work under a ### subheading of The issues still counts: Panel, not No plan" 1 "$(grep -c '^tier: Panel ' "$T/tier")"
# The trigger file is the project's to edit: its own copy replaces the plugin's whole.
printf 'panel\tcsv\texports\n' > "$PROJ/.claude/plan-triggers.tsv"; tier '1. #1: add a CSV export\n'
check "an edited trigger file changes the pick, and is named" 1 "$(grep -c "^tier: Panel (trigger: exports; from $PROJ/.claude/plan-triggers.tsv)" "$T/tier")"
printf 'panl\tcsv\texports\n' > "$PROJ/.claude/plan-triggers.tsv"; tier '1. #1: add a CSV export\n'
check "a trigger line with no known tier is refused, naming the line" '2:1' "$?:$(grep -c 'plan-triggers.tsv line 1 is not' "$T/tier")"
rm "$PROJ/.claude/plan-triggers.tsv"
# The models a plan seat may run on are setup's (planModels); with none saved, every model routing names, Codex's only
# with the Claude+OpenAI profile. A model left out is never offered, and a seat that would use it says what ran instead.
cfg '{profile: "claude-openai"}'; tier '1. #1: change the billing export\n'
check "Panel with every model allowed: Opus and Fable plan, Astra and Sol judge, and the owner is asked for the second planner" \
  'plan-author opus|plan-author-second fable|plan-judge-astra astra|plan-judge-sol sol:1' \
  "$(sed -n 's/^seat: //p' "$T/tier" | paste -sd'|' -):$(grep -c '^ask the owner: which model writes the second plan? (default fable; allowed: ' "$T/tier")"
cfg '{profile: "claude-openai", planModels: ["opus", "sonnet", "sol", "astra"]}'; tier '1. #1: change the billing export\n'
check "Fable opted out: never offered, the second planner on Opus, the substitution named" \
  'plan-author-second opus:1:(default opus; allowed: opus sonnet sol astra)' \
  "$(sed -n 's/^seat: \(plan-author-second .*\)/\1/p' "$T/tier"):$(grep -c '^plan-author-second: fable is not one of the models this project allows.*; used opus instead$' "$T/tier"):$(grep -o '(default.*)$' "$T/tier")"
cfg '{profile: "claude-openai", planModels: ["opus", "sonnet", "fable"]}'; tier '1. #1: change the billing export\n'
check "Codex opted out: both judges run as the Claude judge under their own names, each substitution named" '2:2:0' \
  "$(grep -c '^seat: plan-judge-\(sol\|astra\) sonnet (as plan-judge-claude)$' "$T/tier"):$(grep -c '^plan-judge-\(sol\|astra\): no Codex model is allowed in this project; used plan-judge-claude instead$' "$T/tier"):$(grep -cE ' (sol|astra)$' "$T/tier")"
cfg '{}'

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
printf '## The issues\n1. #1: toy\n   Size: scripts/a.sh; shared with 2; ~60K tokens\n2. #2: toy two\n   Size: scripts/a.sh, scripts/b.sh; shared with 1; ~30K tokens\n3. #3: export\n   Size: scripts/export.sh; independent; ~45K tokens\n4. #4: small\n   Size: scripts/c.sh; independent; ~10K tokens\n5. #5: no size\n'"$P" > "$T/sized.md"
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
  "worktree create"*) n=\$(sed -n 's/.*--name \([^ ]*\).*/\1/p' <<<"\$*"); git -C "$PROJ" worktree add -q --detach "$(dirname "$RWT")/\$n" main >/dev/null 2>&1
    [ ! -e "$T/slow-wt" ] || sleep 3; echo '{"ok":true,"result":{}}' ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
first() { rm -rf "$RWT" "$HOME/.commandeck" "$T/pane-up"; git -C "$PROJ" worktree prune; in_proj env ${RENV[@]+"${RENV[@]}"} bash "$REAL/scripts/builder-launch.sh" --dry-run --risky "$@" risky-unit "${RBATCH:-$T/batch.md}" >"$T/brief" 2>/dev/null
  git -C "$PROJ" worktree add -q --detach "$RWT" && mkdir -p "$RB" && cp "$T/brief" "$RB/risky-unit.md" && mkdir -p "$PROJ/.claude/briefs" && cp "$T/brief" "$PROJ/.claude/briefs/risky-unit-builder-brief.md" && echo spec > "$RB/risky-unit-design-spec.md"
  grep '^effort override:' "$T/brief" > "$RB/risky-unit-evidence.md"; echo note > "$RB/risky-unit-design.md"; : > "$T/orca.log"; }
second() { in_proj env ${RENV[@]+"${RENV[@]}"} COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 bash "$REAL/scripts/builder-launch.sh" --risky "$@" risky-unit "${RBATCH:-$T/batch.md}" >/dev/null 2>"$T/err"; }
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
# A bare --reason is read as the model pick's; the skip's own --reason must not turn into one.
first --skip-plan --reason 'owner chose no plan'; rm -f "$PROJ/.claude/routing-log"
second --skip-plan --reason 'owner chose no plan'
r1=$?; check "--skip-plan --reason opens the Builder on its default model, the skip logged as a routing override, no model pick" \
  "0:$(cmd_of builder | grep -oE -- '--model [^ ]+'):1:0" "$r1:$(grep -m1 '^terminal create' "$T/orca.log" | grep -oE -- '--model [^ ]+'):$(grep -c 'note=routing-override plan skipped: owner chose no plan$' "$PROJ/.claude/routing-log"):$(grep -c 'routing-override builder' "$PROJ/.claude/routing-log")"
# Sol r1: a risky launch whose first call ran before the Plan rule has no Plan in its batch and no skip line in its
# brief. Its first call wrote the brief the Builder opens with, so its second call opens the Builder as it was.
RBATCH=$T/noplan.md; first --skip-plan --reason legacy
for f in "$RB/risky-unit.md" "$PROJ/.claude/briefs/risky-unit-builder-brief.md"; do
  awk '/^plan skipped: / { s = 1; next } s && /^$/ { s = 0; next } { s = 0; print }' "$f" > "$f.old" && mv "$f.old" "$f"
done
second
check "a risky launch begun before the Plan rule: its second call opens the Builder" '0:1' "$?:$(grep -c '^terminal create' "$T/orca.log")"
RBATCH=
# Sol r1: the owner picks each plan seat's model and effort, and seat.sh took a launch option only for a Builder.
first; in_proj env COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 bash "$REAL/scripts/seat.sh" launch plan-author risky-unit "$RB/risky-unit-design-spec.md" --model sonnet --effort medium >/dev/null 2>"$T/err"
check "the plan-author seat opens on the model and effort the owner picked" '0:1' "$?:$(grep '^terminal create' "$T/orca.log" | grep -c -- '--model sonnet --effort medium')"
# seat.sh holds the plan seats to setup's planModels too: a pick outside them is refused, a default outside them
# is swapped, and the launch says so (the Claude-only profile has no Codex, so the Sol judge runs as the Claude judge).
cfg '{planModels: ["opus", "sonnet"]}'
in_proj bash "$REAL/scripts/seat.sh" launch plan-author-second risky-unit "$RB/risky-unit-design-spec.md" --model fable >/dev/null 2>"$T/err"
check "a plan seat picked onto a model setup left out is refused" '2:1:0' "$?:$(grep -c '^REFUSED: --model fable is not one of the models this project allows a plan seat' "$T/err"):$(grep -c 'Plan author second' "$T/orca.log")"
cfg '{}'; : > "$T/orca.log"
in_proj env COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 bash "$REAL/scripts/seat.sh" launch plan-judge-sol risky-unit "$RB/risky-unit-design-spec.md" >/dev/null 2>"$T/err"
check "the Sol judge with no Codex opens the Claude judge, and says so" '0:1:1' \
  "$?:$(grep -c '^plan-judge-sol: no Codex model is allowed in this project; used plan-judge-claude instead$' "$T/err"):$(grep '^terminal create' "$T/orca.log" | grep -c 'Plan judge sol.*claude.*--model sonnet')"
cfg '{profile: "claude-openai"}'; in_proj bash "$REAL/scripts/seat.sh" launch plan-judge-sol risky-unit "$RB/risky-unit-design-spec.md" --model opus >/dev/null 2>"$T/err"
check "a Codex judge picked onto a Claude model is refused" '2:1' "$?:$(grep -c '^REFUSED: --model opus' "$T/err")"
cfg '{}'
# Sol r2: a plan seat needed its unit's worktree, which only the Builder's launch makes, and that launch refuses one
# already made. A plan seat works in its own planning worktree, <unit>-plan, which its first launch makes from main.
WS=$(dirname "$RWT") SCR=$(in_proj bash -c '. "$0" && echo "$PP_SCRATCH"' "$REAL/scripts/paths.sh")
echo 'Write the plan.' > "$T/plan-spec.md"; echo 'Read the plan and print your findings.' > "$T/judge-spec.md"
seat() { in_proj env COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 "${@:4}" bash "$REAL/scripts/seat.sh" launch "$1" "$2" "$3" >/dev/null 2>>"$T/err"; }
: > "$T/orca.log" > "$T/err"; seat plan-author fresh-unit "$T/plan-spec.md"; r=$?
check "a plan seat for a unit with no worktree opens in a planning worktree cut from main" "0:1:$(git -C "$PROJ" rev-parse main)" \
  "$r:$(grep '^terminal create' "$T/orca.log" | grep -c -- "--worktree path:$WS/fresh-unit-plan "):$(git -C "$WS/fresh-unit-plan" rev-parse HEAD 2>&1)"
launch fresh-unit "$T/batch.md"
check "planned, the unit's Builder still launches in its own new worktree" 0 "$?"
# Sol r3: collect and wait went to <unit>-plan for every plan seat, so a planner launched before the planning
# worktree, still in <unit> with no <unit>-plan, could not be collected. A seat is read where its record says it ran.
check "a plan seat's record names the planning worktree it runs in" 1 "$(grep -cx 'worktree=fresh-unit-plan' "$SCR/seat-fresh-unit-plan-author.txt")"
git -C "$PROJ" worktree add -q --detach "$WS/old-unit"
printf 'handle=h1\ntask=task_1\nrole=plan-author\nunit=old-unit\nlaunched=1\n' > "$SCR/seat-old-unit-plan-author.txt"
in_proj bash "$REAL/scripts/seat.sh" collect plan-author old-unit --marker PLAN-DONE >/dev/null 2>"$T/err"
check "a planner launched before the planning worktree is still collected, from the unit's worktree" 0 "$(grep -c 'no worktree at' "$T/err")"
# Sol r3: <unit>-plan is also a name a Builder unit can take, and a plan seat took any such worktree as its own.
git -C "$PROJ" worktree add -q --detach "$WS/busy-plan"
: > "$T/orca.log" > "$T/err"; seat plan-author busy "$T/plan-spec.md"
check "a plan seat is refused a Builder's worktree named <unit>-plan, before any pane opens" '2:0:1' \
  "$?:$(grep -c '^terminal create' "$T/orca.log"):$(grep -c "^REFUSED: $WS/busy-plan is not busy's planning worktree" "$T/err")"
# Sol r4: the Panel's two planners launch in parallel. The second checked <unit>-plan after the first made it and
# before the first marked it, and refused it. The check, the make and the mark are one step under a lock.
: > "$T/orca.log" > "$T/err"; touch "$T/slow-wt"
seat plan-author panel-unit "$T/plan-spec.md" & sleep 1; seat plan-author-second panel-unit "$T/plan-spec.md"; r2=$?; wait $!; r1=$?; rm -f "$T/slow-wt"
check "two planners launched in parallel both open in the one planning worktree" '0:0:2:0' \
  "$r1:$r2:$(grep '^terminal create' "$T/orca.log" | grep -c -- "--worktree path:$WS/panel-unit-plan "):$(grep -c '^REFUSED' "$T/err")"
# Sol r2: with no Codex both judges ran as plan-judge-claude, one title and one record, so the second launch reused
# the first judge. Each keeps its own name, pane and record; only its routing is the Claude judge's.
: > "$T/orca.log"; seat plan-judge-astra fresh-unit "$T/judge-spec.md"; seat plan-judge-sol fresh-unit "$T/judge-spec.md"
check "with no Codex, the Astra and Sol judges are two Claude judges, each with its own pane and record" '2:2:role=plan-judge-astra|role=plan-judge-sol' \
  "$(grep '^terminal create' "$T/orca.log" | grep -cE "Plan judge (astra|sol) — fresh-unit .*claude .*--model sonnet"):$(grep -c '^terminal create' "$T/orca.log"):$(cat "$SCR/seat-fresh-unit-plan-judge-astra.txt" "$SCR/seat-fresh-unit-plan-judge-sol.txt" 2>/dev/null | grep '^role=' | paste -sd'|' -)"
# Sol r2: a plan judge's Codex family went to the command as given (codex --model sol), past the resolver every other
# Codex role's model goes through. A family resolves to the account's model id; the project's saved id is the role's own.
mkdir -p "$T/codex" && echo '{"models": [{"slug": "gpt-6.1-sol"}, {"slug": "gpt-6.2-astra"}]}' > "$T/codex/models_cache.json"
jmodel() { in_proj env CODEX_HOME="$T/codex" bash -c '. "$0" && pp_route_json plan-judge-sol "" "$1" | jq -r ".cmd // (.argv | join(\" \"))"' "$REAL/scripts/paths.sh" "$1" | grep -oE -- '--model [^ ]+'; }
cfg '{profile: "claude-openai"}'
check "a Codex judge's family, its own or the other picked, resolves to the account's model id" '--model gpt-6.1-sol|--model gpt-6.2-astra' "$(jmodel sol)|$(jmodel astra)"
cfg '{profile: "claude-openai", codexModels: {"plan-judge-sol": "gpt-6.0-sol-pinned"}}'
check "the saved model id is the role's own model's, never another family's the owner picked" '--model gpt-6.0-sol-pinned|--model gpt-6.2-astra' "$(jmodel sol)|$(jmodel astra)"
cfg '{profile: "claude-openai"}'; : > "$T/orca.log"; seat plan-judge-sol codex-unit "$T/judge-spec.md" CODEX_HOME="$T/codex"
check "the Sol judge's launch opens Codex on the resolved model id" '0:1' "$?:$(grep '^terminal create' "$T/orca.log" | grep -c 'codex .*--model gpt-6.1-sol')"
cfg '{}'
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
# Sol r5: a record that could not be read was taken as empty, so the raise rewrote the evidence with only its new
# line (its history gone), and a directory where main's brief belongs took the new brief inside it and launched.
first --effort high --reason 'touches billing'; chmod 000 "$RB/risky-unit-evidence.md"; second --effort high --reason billing
r1=$?:$(grep -c '^terminal create' "$T/orca.log"); chmod 644 "$RB/risky-unit-evidence.md"
check "an unreadable evidence file: refused with no pane, and its history is kept" '1:0:1:0' \
  "$r1:$(grep -c '^effort override: builder medium -> high: touches billing$' "$RB/risky-unit-evidence.md"):$(grep -c '^effort changed' "$RB/risky-unit-evidence.md")"
second --effort high --reason billing
check "the retry once it reads: opens at high, the evidence keeps the first line and logs the change" '0:--effort high:1:1' \
  "$?:$(opened):$(grep -c '^effort override: builder medium -> high: touches billing$' "$RB/risky-unit-evidence.md"):$(grep -c '^effort changed at Builder launch: high -> high, reason: billing$' "$RB/risky-unit-evidence.md")"
first; MB=$PROJ/.claude/briefs/risky-unit-builder-brief.md; rm "$MB"; mkdir "$MB"; second --effort high --reason billing
check "a directory where main's brief belongs: refused with no pane, nothing put inside it" '1:0:0' \
  "$?:$(grep -c '^terminal create' "$T/orca.log"):$(ls -A "$MB" | wc -l | tr -d ' ')"
rmdir "$MB"
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

# Sol r1: a launch fast-forwards main from origin before it cuts the worktree, so a plan origin's main deleted
# never reaches the Builder: the plan is checked again on the main the worktree is cut from.
git clone -q --bare "$PROJ" "$T/origin.git" && git clone -q "$T/origin.git" "$T/up" && git -C "$T/up" rm -q .claude/plans/toy.md \
  && git -C "$T/up" -c user.name=t -c user.email=t@t commit -q -m 'drop plan' && git -C "$T/up" push -q origin main && git -C "$PROJ" remote add origin "$T/origin.git"
in_proj bash "$REAL/scripts/builder-launch.sh" toy-unit "$T/batch.md" >/dev/null 2>"$T/err"
check "a plan origin's main deleted is refused once main is fast-forwarded, before any worktree" '2:1:0' \
  "$?:$(grep -c '^REFUSED: .*## Plan' "$T/err"):$(ls "$(in_proj bash -c '. "$0" && echo "$PP_WORKSPACES"' "$REAL/scripts/paths.sh")" 2>/dev/null | grep -c '^toy-unit$')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
