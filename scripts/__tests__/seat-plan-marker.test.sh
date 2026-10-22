#!/usr/bin/env bash
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

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
