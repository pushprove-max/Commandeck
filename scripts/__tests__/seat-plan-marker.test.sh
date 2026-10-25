#!/usr/bin/env bash
# timeout: 240
# seat-plan-marker.test.sh -- seat.sh's plan seats, on the hand-written commandeck.json of fixtures/seat-setup.sh.
# What this pins: a plan seat opens only in its unit's planning worktree, and collect with no --marker closes on the
# last wait's marker, after a silent seat's relaunch too.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"

# A plan seat's driver waits on one marker after another and then collects with no --marker: the STOP hints print
# collect that way, and without the wait's marker a finished plan read as no verdict and kept its pane open.
# The pane ends each turn idle on the marker it was asked for (the screen file); a launch shows on-create's screen,
# which grows on every read after, so a slow machine cannot read the relaunched pane as silent too.
printf 'Plan the unit.\nEnd on a line of its own.\n' > "$T/plan-spec.md"
# A unit is planned and built in one worktree: a plan seat works in <unit>, which the Builder's launch takes over.
# An unmarked <unit> is a Builder's, never taken for planning.
UWT=$HOME/orca/workspaces/proj/pv; git -C "$PROJ" worktree add -q "$UWT"; : > "$T/creates"
srun launch plan-author pv "$T/plan-spec.md" >"$T/out" 2>&1
check "a plan seat for a unit whose unmarked worktree exists is refused before any pane opens" '2:1:0' \
  "$?:$(grep -c "REFUSED: $UWT is not pv's planning worktree" "$T/out"):$(grep -c . "$T/creates")"
# Issue 234: a plan seat's first launch opens the unit, so its spec must carry the order's Launch line for it.
: > "$T/creates"; srun launch plan-author pn "$T/plan-spec.md" >"$T/out" 2>&1
check "a plan seat that would open a new unit with no Launch line in its spec is refused, no worktree made" '2:1:0:no' \
  "$?:$(grep -c "REFUSED: $T/plan-spec.md has no 'Launch: new unit pn' line" "$T/out"):$(grep -c . "$T/creates"):$([ -e "$HOME/orca/workspaces/proj/pn" ] && echo yes || echo no)"
check "the refusal says the Order line must quote the owner's yes naming the unit or its issues (issue 287)" 1 \
  "$(grep -c "the Order line must quote the owner's yes naming this unit or its issues" "$T/out")"
printf 'Launch: new unit pn\nOrder: plan it\n' | cat - "$T/plan-spec.md" > "$T/plan-spec-pn.md"
srun launch plan-author pn "$T/plan-spec-pn.md" >"$T/out" 2>&1
check "with the line the check lets it through" 0 "$(grep -c "has no 'Launch: new unit" "$T/out")"
# Host issue 2999: the plan author is told to name a test file's time-bound checks, so a heavy case lands after them.
check "a plan-author's prompt carries the Timed checks line rule" 1 \
  "$(cat "$HOME"/.commandeck/scratch/*/seat-pn-plan-author.txt.prompt 2>/dev/null | grep -c 'names them on a `Timed checks:` line and orders the heavy case after them')"
# Issue 362: builder-launch.sh refuses a plan with no size line, a decision with no Test: line or no What can go wrong
# section, so the plan author is told what the plan must hold before it writes.
check "a plan-author's prompt names the size line, the Test: line, the Break: line and the What can go wrong section" 1 \
  "$(cat "$HOME"/.commandeck/scratch/*/seat-pn-plan-author.txt.prompt 2>/dev/null | grep -c 'A plan carries a `- Planned size: <n> files, <n> changed lines` line, a `Test:` line under each item.*a `Break:` line.*`## What can go wrong` section')"
# The planning worktree as a first plan launch leaves it (made and marked): the Orca stand-in makes no worktree.
PWT=$HOME/orca/workspaces/proj/pu; git -C "$PROJ" worktree add -q "$PWT" && echo pu > "$(git -C "$PWT" rev-parse --absolute-git-dir)/commandeck-plan-of"
srun launch plan-author pu "$T/plan-spec.md" >"$T/out" 2>&1; check "a plan seat launches in its planning worktree" 0 $?
check "which is the unit's own worktree, and its record names it" '1:1' \
  "$(grep -c -- "path:$PWT " "$T/creates"):$(grep -cx 'worktree=pu' "$HOME/.commandeck/scratch/"*/seat-pu-plan-author.txt)"
for m in PLAN-DONE REVISED PLAN-DONE; do echo "$m" > "$T/screen"; srun wait plan-author pu --marker "$m" --timeout-s 10 >"$T/out" 2>&1 || echo "wait $m: $(tail -2 "$T/out")"; done
MW=$(ls -d "$HOME/.commandeck/scratch/"*/ | head -1)main-watch; mkdir -p "$MW"; : > "$T/updates"
printf 'posted=1\ntask=task_item_s\n' > "$MW/item-seat-h1-task_1"; printf 'posted=1\ntask=task_item_o\n' > "$MW/item-seat-h9-task_9"
# r1: a collect before the marker writes the unfinished report and keeps the pane; the collect after it rewrites it.
printf '# Draft\nstill planning\n' > "$T/screen"; srun collect plan-author pu >"$T/out" 2>&1
check "an early collect keeps the pane open and writes the report so far" "3:1" \
  "$?:$(grep -c 'still planning' "$(sed -n 's/^report=//p' "$HOME/.commandeck/scratch/"*/seat-pu-plan-author.txt | tail -1)" 2>/dev/null)"
echo PLAN-DONE > "$T/screen"; mkdir -p "$PWT/.claude/plans"; echo 'the plan' > "$PWT/.claude/plans/pu.md"
PH=$(sha256sum < "$PWT/.claude/plans/pu.md" | cut -d' ' -f1)
srun collect plan-author pu >"$T/out" 2>&1
check "collect with no --marker closes on the marker the last wait saw" '0:1' "$?:$(grep -c 'closed seat=plan-author unit=pu PLAN-DONE' "$T/out")"
# Issue 256: builder-launch.sh --from-plan installs only the plan the author left or the judge read, by these lines.
check "the plan author's collect records the plan it leaves, its hash and when" "1:1:1" \
  "$(grep -cx "plan=$PWT/.claude/plans/pu.md" "$HOME/.commandeck/scratch/"*/seat-pu-plan-author.txt):$(grep -cx "planhash=$PH" "$HOME/.commandeck/scratch/"*/seat-pu-plan-author.txt):$(grep -cE '^collected=[0-9]+$' "$HOME/.commandeck/scratch/"*/seat-pu-plan-author.txt)"
# Issue 227: main closed a collected seat's main-watch item task by hand; collect does it.
check "collect completes the seat's main-watch item task, and not another pane's" "1:0" \
  "$(grep -c -- '--id task_item_s --status completed' "$T/updates"):$(grep -c task_item_o "$T/updates")"
# Issue 236: with no --report a seat's findings lived only in the pane, and collect closes the pane.
RP=$(sed -n 's/^report=//p' "$HOME/.commandeck/scratch/"*/seat-pu-plan-author.txt | tail -1)
check "collect with no --report keeps the report under the scratch folder's reports/, prints and records its path" '1:1:1' \
  "$(grep -cxF "report: $RP ($(wc -l < "$RP" 2>/dev/null | tr -d ' ') lines)" "$T/out"):$(grep -c PLAN-DONE "$RP" 2>/dev/null):$(case $RP in "$HOME"/.commandeck/scratch/*/reports/pu-plan-author-[0-9]*.md) echo 1 ;; esac)"
check "the finishing collect rewrote the report an early collect left" 0 "$(grep -c 'still planning' "$RP" 2>/dev/null)"
check "read-verdict.sh --seat prints the verdict collect closed on, then that report" "PLAN-DONE:$(cat "$RP" 2>/dev/null)" \
  "$(cd "$PROJ" && env -u COMMANDECK_SCRATCH -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR bash "$REAL/scripts/read-verdict.sh" --seat pu plan-author 2>&1 | { read -r v; printf '%s:%s' "$v" "$(cat)"; })"
# A silent read-only seat is relaunched from its record, which the relaunch writes again: the marker must survive it.
printf 'Judge the plan.\nEnd on a line of its own.\n' > "$T/judge-spec.md"
# Issue 291: under an account profile (CLAUDE_CONFIG_DIR) Claude Code keeps .claude.json in that folder, not in HOME.
mkdir -p "$T/prof-off" "$T/prof-on"
# The profile's own settings put the judge on Claude: the check is a Claude seat's, and a Codex judge skips it.
tee "$T/prof-off/settings.json" < "$HOME/.claude/settings.json" > "$T/prof-on/settings.json"
jq -n --arg p "$PROJ" '{projects: {($p): {disabledMcpServers: ["serena"]}}}' | tee "$T/prof-off/.claude.json" > "$HOME/.claude.json"
PROFILE=$T/prof-off srun launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1
check "issue 291: a profile's .claude.json that disables a needed server refuses the launch" "2:1" "$?:$(grep -c 'BLOCKED: serena disabled' "$T/out")"
PROFILE=$T/prof-on srun launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1; check "the judge launches; under a profile HOME's .claude.json is not read" 0 $?
rm "$HOME/.claude.json"
JREC=$(ls "$HOME/.commandeck/scratch/"*/seat-pu-plan-judge-sol.txt)
printf 'Reading the plan.\nesc to interrupt\n' > "$T/screen"; echo PLAN-DONE > "$T/on-create"
COMMANDECK_SEAT_SILENT_SECONDS=1 srun wait plan-judge-sol pu --marker PLAN-DONE --timeout-s 20 >"$T/out" 2>&1
check "a silent judge is relaunched once and its wait then sees the marker" '0:1' "$?:$(grep -c 'relaunching once' "$T/out")"
check "the relaunched record keeps relaunched=1 and the wait's marker" '1:1' "$(grep -cx 'relaunched=1' "$JREC"):$(grep -cx 'marker=PLAN-DONE' "$JREC")"
srun collect plan-judge-sol pu >"$T/out" 2>&1
check "and collect with no --marker closes it" '0:1' "$?:$(grep -c 'closed seat=plan-judge-sol unit=pu PLAN-DONE' "$T/out")"
rm -f "$T/on-create" "$T/grow"
COMMANDECK_SEAT_FORCE=1 srun launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1
check "a plain launch writes a record with no marker of an earlier wait" '0:0' "$?:$(grep -c '^marker=' "$JREC")"
check "and keeps the seat's first launch, so a relaunch does not move its planning's start" 1 \
  "$(awk -F= '$1 == "first" { f = $2 } $1 == "launched" { l = $2 } END { print (f != "" && f < l) }' "$JREC")"
# A wait that gives up has proven nothing: an unfinished pane quoting the marker in a fence must not be collected on it.
printf 'Still judging.\n```\nPLAN-DONE\n```\nesc to interrupt\n' > "$T/screen"
srun wait plan-judge-sol pu --marker PLAN-DONE --timeout-s 0 >"$T/out" 2>&1
check "a wait that times out fails and saves no marker" '1:0' "$?:$(grep -c '^marker=' "$JREC")"
srun collect plan-judge-sol pu >"$T/out" 2>&1
check "so collect with no --marker keeps the unfinished pane open" '3:0' "$?:$(grep -c 'closed seat' "$T/out")"

# Issue 320: a planner that finished by its own message or a fresh plan commit, never printing PLAN-DONE, read as
# stalled and kept its pane. Each planner below was prompted 900 s ago and ended its turn 600 s ago, so its wait is at
# the idle limit; what it left (a message, a commit) is dated 700 s ago, inside that turn and before the wait starts:
# the latest prompt bounds the episode, never the wait's own start.
RWT=$HOME/orca/workspaces/proj/pr; git -C "$PROJ" worktree add -q "$RWT" && echo pr > "$(git -C "$RWT" rev-parse --absolute-git-dir)/commandeck-plan-of"
RPS=$HOME/.claude/projects/$(printf '%s' "$RWT" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$RPS"; NOW=$(date +%s)
rrec() { ls "$HOME/.commandeck/scratch/"*/"seat-pr-$1.txt"; }
rlog() { local r; r=$(rrec "$1"); echo "$RPS/s-$1-$(sed -n 's/^tag=//p' "$r").jsonl"; }
at() { jq -rn --argjson t "$1" '$t | todate'; }
idle() { # <role> <last words> [earlier block] -- the seat's session: one turn, prompted 900 s ago, its tool call, its last words, ended 600 s ago;
  # an earlier block is the same reply's first text record (Claude Code writes one record per block, under one message id)
  local r; r=$(rrec "$1"); sed -i "s/^launched=.*/launched=$((NOW - 1000))/" "$r"
  jq -cn --arg p "$(at $((NOW - 900)))" --arg t "$(at $((NOW - 600)))" --arg tag "$(sed -n 's/^tag=//p' "$r")" --arg w "$2" --arg e "${3:-}" '
    {type: "user", timestamp: $p, message: {role: "user", content: "Your task spec. Seat tag \($tag)."}},
    {type: "assistant", timestamp: $t, message: {content: [{type: "tool_use", id: "u1", name: "Read", input: {}}]}},
    if $e == "" then empty else {type: "assistant", timestamp: $t, message: {id: "m1", content: [{type: "text", text: $e}]}} end,
    {type: "assistant", timestamp: $t, message: {id: "m1", content: [{type: "text", text: $w}]}},
    {type: "system", subtype: "turn_duration", timestamp: $t}' > "$(rlog "$1")"; }
followup() { # <role> [ended] -- main types a follow-up 400 s ago; with `ended`, that turn ended 350 s ago with no marker
  jq -cn --arg p "$(at $((NOW - 400)))" --arg t "$(at $((NOW - 350)))" --arg e "${2:-}" '
    {type: "user", timestamp: $p, message: {role: "user", content: "Also cover the rollback in section 4."}},
    if $e == "" then empty else {type: "assistant", timestamp: $t, message: {content: [{type: "text", text: "Looking at section 4."}]}},
    {type: "system", subtype: "turn_duration", timestamp: $t} end' >> "$(rlog "$1")"; }
said() { # <to> <subject> <body> [epoch] [type] [read] -- the seat's one message in Orca's inbox
  jq -nc --arg to "$1" --arg s "$2" --arg b "$3" --argjson at "${4:-$((NOW - 700))}" --arg ty "${5:-worker_done}" --argjson rd "${6:-0}" \
    '{ok: true, result: {messages: [{from_handle: "h1", to_handle: $to, type: $ty, subject: $s, body: $b, read: $rd, created_at: ($at | todate)}]}}' > "$T/inbox.json"; }
rlaunch() { rm -f "$T/pane-up" "$T/inbox.json"; COMMANDECK_SEAT_FORCE=1 srun launch "$1" pr "$2" >"$T/out" 2>&1 || echo "launch $1: $(tail -2 "$T/out")"; }
rwait() { srun wait "$1" pr --marker PLAN-DONE --timeout-s 20 >"$T/out" 2>&1; }
commit_plan() { echo "$1" > "$RWT/.claude/plans/pr.md"; git -C "$RWT" add .claude/plans/pr.md
  GIT_COMMITTER_DATE="@${2:-$((NOW - 700))} +0000" git -C "$RWT" -c user.name=t -c user.email=t@t commit -qm plan; }
printf 'Launch: new unit pr\nPlan the unit.\nEnd on a line of its own.\n' > "$T/pr-spec.md"; mkdir -p "$RWT/.claude/plans"
rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'Plan revised: see the file.'; said run:run-1 'Plan revised: section 3 rewritten' 'See the plan file.'
rwait plan-author
check "a planner that sends 'Plan revised' to the run but prints no marker: wait exits 0, no STOP stalled line" '0:0' "$?:$(grep -c 'route=stalled' "$T/out")"
# The wait's own state goes between two waits: the finish is still the seat's, so the second wait releases too.
rm -f "$HOME/.commandeck/scratch/"*/waiting-h1; sed -i '/^marker=/d' "$(rrec plan-author)"; rwait plan-author
check "a second wait on the same finish, its claim and marker removed between the two: exits 0 again" '0:0' "$?:$(grep -c 'route=stalled' "$T/out")"
echo 'Plan revised: see the file.' > "$T/screen"; srun collect plan-author pr >"$T/out" 2>&1
check "and collect closes the pane on PLAN-DONE" '0:1:0' "$?:$(grep -c 'closed seat=plan-author unit=pr PLAN-DONE' "$T/out"):$([ -e "$T/pane-up" ] && echo 1 || echo 0)"
# A finish the seat reported before main's follow-up is history, whether or not main-watch or a wait saw the follow-up:
# each collect below runs on a fresh launch with no wait before it.
echo 'Looking at section 4.' > "$T/screen"
rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'Plan written.'; said run:run-1 'Plan written: pr' 'PLAN-DONE'; followup plan-author ended
srun collect plan-author pr >"$T/out" 2>&1; check "a report from before main's follow-up, the follow-up turn ended with none: collect keeps the pane open" 3 $?
rwait plan-author; check "and wait stops stalled" '1:1' "$?:$(grep -c 'route=stalled' "$T/out")"
rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'Plan written.'; said run:run-1 'Plan written: pr' 'PLAN-DONE' $((NOW - 380)); followup plan-author
srun collect plan-author pr >"$T/out" 2>&1; check "a report inside a follow-up turn that still runs: collect keeps the pane open" 3 $?
rlaunch plan-author "$T/pr-spec.md"; commit_plan 'the first plan'; idle plan-author 'Plan written.'; followup plan-author ended
srun collect plan-author pr >"$T/out" 2>&1; check "a plan commit from before main's follow-up: collect keeps the pane open" 3 $?
# A marker quoted in a fence, or under a question or refusal, is not the seat's finish.
rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'Waiting for an answer.'
quoted() { # <case> <subject> <body>
  said run:run-1 "$2" "$3"; rwait plan-author; local rc=$?
  check "a message whose marker is $1: wait stops stalled" '1:1' "$rc:$(grep -c 'route=stalled' "$T/out")"; }
quoted 'fenced under a refusal' 'Question about required output' $'"BLOCKED: I cannot finish. Is this the required line?\n```\nPLAN-DONE\n```"'
quoted "fenced under a question, its subject 'Plan revised'" 'Plan revised: one question' $'QUESTION: Should the final line be this?\n```\nPLAN-DONE\n```'
quoted 'bare under a refusal' 'Status' $'BLOCKED: I cannot finish. Is this the required line?\nPLAN-DONE'
quoted 'in a tilde fence' 'Status' $'The required line:\n~~~\nPLAN-DONE\n~~~'
quoted 'in a blockquoted fence' 'Status' $'"> ```\n> PLAN-DONE\n> ```"'
# The finish is a fixed list, no parse: decoration or text around the marker is not one.
quoted 'in bold' 'Status' '**PLAN-DONE**'
quoted 'under a line of prose' 'Status' $'Done with the plan.\nPLAN-DONE'
# A failure report is no finish whatever its subject says, and a verdict line is never a plan author's PLAN-DONE.
quoted 'PLAN-BLOCKED under a Plan revised subject' 'Plan revised: rollback pending' 'PLAN-BLOCKED'
quoted 'a NO-GO verdict' 'Status' 'VERDICT: NO-GO'
# Read again by collect with the wait's claim and marker removed: the rule reads only the message.
rm -f "$HOME/.commandeck/scratch/"*/waiting-h1; sed -i '/^marker=/d' "$(rrec plan-author)"
srun collect plan-author pr >"$T/out" 2>&1; check "and collect keeps that pane open" 3 $?
rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'I stopped to think about section 3.'
rwait plan-author
check "a planner that really stopped mid-plan (no commit, no message, idle past the limit): STOP route=stalled, and the line carries its last message" '1:1' \
  "$?:$(grep -c 'route=stalled.*last message: I stopped to think about section 3\.' "$T/out")"
said term_helper 'Plan revised: section 3 rewritten' 'See the plan file.'; rwait plan-author
check "a 'Plan revised' message to another pane (to_handle: term_helper): wait stops stalled" '1:1' "$?:$(grep -c 'route=stalled' "$T/out")"
said run:run-1 'Status' $'Cannot print PLAN-DONE; permission denied.'; rwait plan-author
check "a message whose body says 'Cannot print PLAN-DONE; permission denied.': wait stops stalled" '1:1' "$?:$(grep -c 'route=stalled' "$T/out")"
srun collect plan-author pr >"$T/out" 2>&1; check "and collect keeps that pane open" 3 $?
# The previous seat committed the plan; its replacement launches over it (planref) and does nothing. The commit is
# dated inside the new seat's own turn, so only the blob tells the two seats apart.
commit_plan 'the first seat plan'; rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'Taking over the plan.'; rwait plan-author
check "the same-second replacement: the previous seat's commit is its planref, so wait still stops stalled" '1:1:1' \
  "$?:$(grep -c 'route=stalled' "$T/out"):$(grep -cx "planref=$(git -C "$RWT" rev-parse HEAD:.claude/plans/pr.md)" "$(rrec plan-author)")"
srun collect plan-author pr >"$T/out" 2>&1; check "and collect keeps the pane" 3 $?
commit_plan 'the replacement plan'; rwait plan-author
check "the planner's own plan commit since its wait began releases the wait" '0:0' "$?:$(grep -c 'route=stalled' "$T/out")"
# The commit stands in for PLAN-DONE only: a caller's other marker, a verdict above all, is never made from it.
srun wait plan-author pr --marker 'VERDICT: GO' --timeout-s 20 >"$T/out" 2>&1
check "a wait for 'VERDICT: GO' on that planner is not released by its commit" '1:1' "$?:$(grep -c 'route=stalled' "$T/out")"
srun collect plan-author pr --marker 'VERDICT: GO' --on-go 'echo APPROVED' >"$T/out" 2>&1
check "collect --marker 'VERDICT: GO' --on-go makes no verdict of the commit: no APPROVED, the pane stays" '3:0:0' \
  "$?:$(grep -c APPROVED "$T/out"):$(grep -c 'closed seat' "$T/out")"
srun collect plan-author pr >"$T/out" 2>&1; check "and collect closes it on PLAN-DONE" '0:1' "$?:$(grep -c 'closed seat=plan-author unit=pr PLAN-DONE' "$T/out")"
# A committed draft is not the finish while the working plan differs from it, staged or not: the seat is still writing.
rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'Plan written.'; commit_plan 'the committed draft'
echo 'TODO: finish rollback' >> "$RWT/.claude/plans/pr.md"
srun collect plan-author pr >"$T/out" 2>&1; check "a committed plan with later uncommitted edits, no message or marker: collect keeps the pane open" 3 $?
rwait plan-author; check "and wait stops stalled" '1:1' "$?:$(grep -c 'route=stalled' "$T/out")"
git -C "$RWT" add .claude/plans/pr.md
srun collect plan-author pr >"$T/out" 2>&1; check "and with those edits staged, not committed: collect keeps the pane open" 3 $?
git -C "$RWT" checkout -q HEAD -- .claude/plans/pr.md
srun collect plan-author pr >"$T/out" 2>&1
check "and once the working plan is the commit, collect closes it on PLAN-DONE" '0:1' "$?:$(grep -c 'closed seat=plan-author unit=pr PLAN-DONE' "$T/out")"
# An index flag (assume-unchanged, skip-worktree) hides a working edit from git's own diff: the working file itself
# must be the commit. Nothing is kept between two reads: with the wait's claim and marker removed and the flag still
# set, the next collect, the file the commit again, closes the pane.
for f in assume-unchanged skip-worktree; do
  rlaunch plan-author "$T/pr-spec.md"; idle plan-author 'Plan written.'; commit_plan "the $f draft"
  git -C "$RWT" update-index --$f .claude/plans/pr.md; printf '\nTODO: finish rollback\n' >> "$RWT/.claude/plans/pr.md"
  srun collect plan-author pr >"$T/out" 2>&1; check "a committed plan, a later edit hidden by --$f: collect keeps the pane open" 3 $?
  rwait plan-author; check "and wait stops stalled" '1:1' "$?:$(grep -c 'route=stalled' "$T/out")"
  rm -f "$HOME/.commandeck/scratch/"*/waiting-h1; sed -i '/^marker=/d' "$(rrec plan-author)"
  git -C "$RWT" show HEAD:.claude/plans/pr.md > "$RWT/.claude/plans/pr.md"
  srun collect plan-author pr >"$T/out" 2>&1
  check "and with the claim and marker removed, the flag still set, the file the commit: collect closes it on PLAN-DONE" '0:1' \
    "$?:$(grep -c 'closed seat=plan-author unit=pr PLAN-DONE' "$T/out")"
  git -C "$RWT" update-index --no-$f .claude/plans/pr.md
done
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
