#!/usr/bin/env bash
# seat.test.sh -- seat.sh launches and reads the panes main works through, on a hand-written commandeck.json (no
# setup run). What this pins: a headless role is never opened as a pane; a read-only seat is refused a spec
# that asks it to write a file, but not prose that ends on the verb; a live Builder pane is reused only while the
# project's Builder settings are the ones it opened with; a pane quoting a verdict in a fence is still working; and
# collect with no --marker closes on the last wait's marker, after a silent seat's relaunch too.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home
PROJ=$T/proj CFG=$T/proj/.claude/commandeck.json BIN=$T/bin; mkdir -p "$HOME" "$BIN" "$PROJ/.claude"
git init -q -b main "$PROJ" && git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
echo '{"version": 1, "profile": "claude"}' > "$CFG"
# A Codex seat's model is read from Codex's own model list.
mkdir -p "$HOME/.codex" && jq -n --arg f "$(jq -r '.roles["codex-reviewer"].model' "$REAL/config/routing.json")" '{models: [{slug: "gpt-9.1-\($f)"}]}' > "$HOME/.codex/models_cache.json"
seat_sh() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH -u COMMANDECK_ROUTING -u CODEX_HOME \
  PATH="$BIN:$PATH" timeout 120 bash "$REAL/scripts/seat.sh" "$@" </dev/null); }
# settle <unit> <role> -- wait out a launch's background part (issue 233), by the pid its record names.
settle() { local p; p=$(sed -n 's/^pid=//p' "$HOME/.commandeck/scratch/"*/"seat-$1-$2.txt" 2>/dev/null | tail -1)
  while [ -n "$p" ] && kill -0 "$p" 2>/dev/null; do sleep 0.1; done; }
# run -- seat.sh, and a launch is waited out, so each case reads the launch whole.
run() { seat_sh "$@"; local rc=$?; [ "$1" != launch ] || settle "$3" "$2"; return $rc; }
# The Orca stand-in has one pane: the first launch makes it, and it stays live.
SWT=$HOME/orca/workspaces/proj/seat-builder; mkdir -p "$HOME/orca/workspaces/proj/seat-unit"; git -C "$PROJ" worktree add -q "$SWT"
cat > "$BIN/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "terminal create"*) echo "\$*" >> "$T/creates"; touch "$T/pane-up"; [ ! -e "$T/on-create" ] || { cp "$T/on-create" "$T/screen"; touch "$T/grow"; }; echo '{"ok":true,"result":{"terminal":{"handle":"h1"}}}' ;;
  "terminal list"*) [ -e "$T/pane-up" ] && t='[{"handle":"h1","agentIdentity":"claude","worktreeId":"w1","worktreePath":"$SWT"}]' || t='[]'
    echo "{\"ok\":true,\"result\":{\"terminals\":\$t}}" ;;
  "terminal read"*) [ ! -e "$T/read-fails" ] || exit 1; [ ! -e "$T/grow" ] || echo . >> "$T/screen"; [ ! -e "$T/screen" ] || { jq -Rsn --rawfile s "$T/screen" '{ok: true, result: {terminal: {tail: (\$s | rtrimstr("\n") | split("\n"))}}}'; exit; }
    jq -n '{ok: true, result: {terminal: {tail: "Reviewing.\nThe last line will read:\n\`\`\`\nVERDICT: GO\n\`\`\`\nStill reading the diff."}}}' ;;
  "terminal close"*) rm -f "$T/pane-up"; echo '{"ok":true,"result":{}}' ;;
  "terminal wait"*) while [ -e "$T/slow-idle" ]; do sleep 0.1; done; echo '{"ok":true,"result":{}}' ;;
  "orchestration task-update"*) echo "\$*" >> "$T/updates"; echo '{"ok":true,"result":{}}' ;;
  "orchestration task-create"*) echo '{"ok":true,"result":{"task":{"id":"task_1"}}}' ;;
  "orchestration worker-start"*) [ -e "$T/no-dispatch" ] && { echo '{"ok":false,"error":{"message":"refused for the test"}}'; exit; }; echo '{"ok":true,"result":{}}' ;;
  "terminal send"*) [ ! -e "$T/send-fails" ] || { echo '{"ok":false,"error":{"message":"SEND-PROBE"}}'; exit; }
    [ -e "$T/no-dispatch" ] || { echo '{"ok":true,"result":{}}'; exit; }
    while [ \$# -gt 0 ]; do [ "\$1" != --text ] || printf '%s\n' "\$2" >> "$T/sent"; shift; done; echo '{"ok":true,"result":{"stages":["turn_started"]}}' ;;
  "worktree ps --json") echo '{"result":{"worktrees":[]}}' ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
EOF
chmod +x "$BIN/orca-ide"
echo "review this" > "$T/spec.md"

run launch claude-reviewer seat-unit "$T/spec.md" >"$T/out" 2>&1
check "a headless role is refused as a pane seat" "2:1" "$?:$(grep -c 'is not a pane seat' "$T/out")"
printf 'Write the findings to out.md.\n' > "$T/spec-w.md"; printf 'Read the fenced write). Map: x.md\n' > "$T/spec-p.md"
check "a read-only seat asked to write a file is refused; a clause ending on the verb is not an ask" '1:0' \
  "$(run launch codex-reviewer seat-unit "$T/spec-w.md" 2>&1 | grep -c 'spec asks it to write'):$(run launch codex-reviewer seat-unit "$T/spec-p.md" 2>&1 | grep -c 'spec asks it to write')"

seat() { COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch builder seat-builder "$T/spec.md"; }
jq '.builder = {model: "sonnet"}' "$CFG" > "$T/cfg" && cp "$T/cfg" "$CFG"
seat >"$T/out" 2>&1; check "the first Builder launch opens a pane" 0 $?
seat >"$T/out" 2>&1; check "a second launch on the same settings reuses it" '0:1' "$?:$(grep -c 'state=reused' "$T/out")"
jq 'del(.builder)' "$CFG" > "$T/cfg" && cp "$T/cfg" "$CFG"
seat >"$T/out" 2>&1
check "once the project's Builder model changed, the live pane is refused, and the refusal says why" '2:0:1' \
  "$?:$(grep -c 'state=reused' "$T/out"):$(grep -c 'REFUSED: live builder seat h1 for seat-builder was opened with other launch settings' "$T/out")"
# The reader prints an unfinished pane's last lines under "NO VERDICT YET"; reading a verdict there closed the seat.
run collect builder seat-builder >"$T/out" 2>&1
check "a fenced verdict in an unfinished pane's last lines is no verdict" '3:0' "$?:$(grep -c 'closed seat' "$T/out")"
# A Builder main raised (builder-launch.sh --effort) opens at that effort; a level other than medium or high is refused here too.
rm -f "$T/pane-up"
COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch builder seat-builder "$T/spec.md" --effort high >"$T/out" 2>&1
check "a raised Builder's pane opens with --effort high" '0:1' "$?:$(grep -cE -- '^cmd=.* --effort high( |$)' "$HOME/.commandeck/scratch/"*/seat-seat-builder-builder.txt)"
# Pass 3: the screen read that prints a launched seat's state failed the whole launch, and builder-launch.sh then
# undid the files the running Builder had opened on.
rm -f "$T/pane-up"; touch "$T/read-fails"
COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch builder seat-builder "$T/spec.md" --effort high >"$T/out" 2>&1
check "a launched seat whose last screen read fails exits 0, its state unknown" '0:1' "$?:$(grep -c 'state=unknown' "$HOME/.commandeck/scratch/"*/seat-seat-builder-builder.txt.log)"
rm "$T/read-fails"
run launch builder seat-builder "$T/spec.md" --effort max >"$T/out" 2>&1
check "--effort max is refused before any pane opens" '2:1' "$?:$(grep -c 'REFUSED: --effort takes medium or high' "$T/out")"
# A seat launched by hand is held to the launcher's floor: medium under a project default of high would lower it.
jq '.builder = {effort: "high"}' "$CFG" > "$T/cfg" && mv "$T/cfg" "$CFG"
run launch builder seat-builder "$T/spec.md" --effort medium >"$T/out" 2>&1
check "--effort medium under a Builder default of high is refused before any pane opens" '2:1' \
  "$?:$(grep -c "REFUSED: --effort medium is below this project's Builder default high" "$T/out")"

# A plan seat's driver waits on one marker after another and then collects with no --marker: the STOP hints print
# collect that way, and without the wait's marker a finished plan read as no verdict and kept its pane open.
# The pane ends each turn idle on the marker it was asked for (the screen file); a launch shows on-create's screen,
# which grows on every read after, so a slow machine cannot read the relaunched pane as silent too.
# A wait that never sees its marker ends at its own --timeout-s, not the test's.
srun() { (export COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 COMMANDECK_LOOP_POLL_SECONDS=0 COMMANDECK_DRIVER=1; run "$@"); }
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
echo PLAN-DONE > "$T/screen"
srun collect plan-author pu >"$T/out" 2>&1
check "collect with no --marker closes on the marker the last wait saw" '0:1' "$?:$(grep -c 'closed seat=plan-author unit=pu PLAN-DONE' "$T/out")"
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
srun launch plan-judge-claude pu "$T/judge-spec.md" >"$T/out" 2>&1; check "the judge launches" 0 $?
JREC=$(ls "$HOME/.commandeck/scratch/"*/seat-pu-plan-judge-claude.txt)
printf 'Reading the plan.\nesc to interrupt\n' > "$T/screen"; echo PLAN-DONE > "$T/on-create"
COMMANDECK_SEAT_SILENT_SECONDS=1 srun wait plan-judge-claude pu --marker PLAN-DONE --timeout-s 20 >"$T/out" 2>&1
check "a silent judge is relaunched once and its wait then sees the marker" '0:1' "$?:$(grep -c 'relaunching once' "$T/out")"
check "the relaunched record keeps relaunched=1 and the wait's marker" '1:1' "$(grep -cx 'relaunched=1' "$JREC"):$(grep -cx 'marker=PLAN-DONE' "$JREC")"
srun collect plan-judge-claude pu >"$T/out" 2>&1
check "and collect with no --marker closes it" '0:1' "$?:$(grep -c 'closed seat=plan-judge-claude unit=pu PLAN-DONE' "$T/out")"
rm -f "$T/on-create" "$T/grow"
COMMANDECK_SEAT_FORCE=1 srun launch plan-judge-claude pu "$T/judge-spec.md" >"$T/out" 2>&1
check "a plain launch writes a record with no marker of an earlier wait" '0:0' "$?:$(grep -c '^marker=' "$JREC")"
check "and keeps the seat's first launch, so a relaunch does not move its planning's start" 1 \
  "$(awk -F= '$1 == "first" { f = $2 } $1 == "launched" { l = $2 } END { print (f != "" && f < l) }' "$JREC")"
# A wait that gives up has proven nothing: an unfinished pane quoting the marker in a fence must not be collected on it.
printf 'Still judging.\n```\nPLAN-DONE\n```\nesc to interrupt\n' > "$T/screen"
srun wait plan-judge-claude pu --marker PLAN-DONE --timeout-s 0 >"$T/out" 2>&1
check "a wait that times out fails and saves no marker" '1:0' "$?:$(grep -c '^marker=' "$JREC")"
srun collect plan-judge-claude pu >"$T/out" 2>&1
check "so collect with no --marker keeps the unfinished pane open" '3:0' "$?:$(grep -c 'closed seat' "$T/out")"
# Sol r4: with no session log to read, the idle screen decides, and a marker it shows inside a fence is a quoted
# sample, never the pane's own: three idle polls of it saved the marker and flagless collect closed the seat.
printf 'Still judging.\n```\nPLAN-DONE\n```\nPlease clarify the scope.\n' > "$T/screen"
srun wait plan-judge-claude pu --marker PLAN-DONE --timeout-s 3 >"$T/out" 2>&1
check "an idle screen quoting the marker in a fence, with no session log, is not released" '1:0' "$?:$(grep -c '^marker=' "$JREC")"
srun collect plan-judge-claude pu --marker PLAN-DONE >"$T/out" 2>&1
check "and collect, even given the marker, keeps the pane open" '3:0' "$?:$(grep -c 'closed seat' "$T/out")"
# A screen is a viewport: one that opens inside the fence, its opening line scrolled away, still quotes the marker.
printf 'PLAN-DONE\n```\nPlease clarify the scope.\n' > "$T/screen"
srun wait plan-judge-claude pu --marker PLAN-DONE --timeout-s 3 >"$T/out" 2>&1
check "a screen opening inside a fence that quotes the marker is not released" '1:0' "$?:$(grep -c '^marker=' "$JREC")"
# Sol r5: a real bare opening fence still streaming is the same text as a cropped closing one; ambiguity never releases.
printf 'Still judging.\n```\nPLAN-DONE\n' > "$T/screen"
srun wait plan-judge-claude pu --marker PLAN-DONE --timeout-s 3 >"$T/out" 2>&1
check "a screen ending inside a bare fence that quotes the marker is not released" '1:0' "$?:$(grep -c '^marker=' "$JREC")"
srun collect plan-judge-claude pu --marker PLAN-DONE >"$T/out" 2>&1
check "and collect, even given the marker, keeps the pane open" '3:0' "$?:$(grep -c 'closed seat' "$T/out")"
# The session log outranks the screen (Sol r2): a finished turn whose reply ends on a question, not the marker, is no
# marker, though the idle screen still shows the reply's fenced sample of it.
printf 'Plan it again.\nEnd on a line of its own.\n' > "$T/plan-spec2.md"
rm -f "$T/pane-up"; srun launch plan-author pu "$T/plan-spec2.md" >"$T/out" 2>&1; check "the planner launches again" 0 $?
# Without the record, the judge's below would be written into the working folder.
AREC=$(ls "$HOME/.commandeck/scratch/"*/seat-pu-plan-author.txt) || { echo "FAIL no planner record"; exit 1; }; NOWZ=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PS=$HOME/.claude/projects/$(printf '%s' "$PWT" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$PS"
jq -cn --arg t "$NOWZ" --arg tag "$(sed -n 's/^tag=//p' "$AREC")" '
  {type: "user", timestamp: $t, message: {role: "user", content: "Your task spec. Seat tag \($tag)."}},
  {type: "assistant", timestamp: $t, message: {content: [{type: "tool_use", id: "u1", name: "Read", input: {}}]}},
  {type: "assistant", timestamp: $t, message: {content: [{type: "text", text: "It ends on:\n```\nPLAN-DONE\n```\nPlease clarify the scope."}]}},
  {type: "system", subtype: "turn_duration", timestamp: $t}' > "$PS/s-ask.jsonl"
printf 'It ends on:\n```\nPLAN-DONE\n```\nPlease clarify the scope.\n' > "$T/screen"
srun wait plan-author pu --marker PLAN-DONE --timeout-s 5 >"$T/out" 2>&1
check "an idle reply that quotes the marker and ends on a question is not released" '1:0' "$?:$(grep -c '^marker=' "$AREC")"
check "a Claude seat with no session at launch binds its log's session id, not its path" 'session=s-ask' "$(grep '^session=' "$AREC" 2>&1)"
# Every stand-in pane is h1, and the reader takes the first record naming it: the judge's collect below must not
# read the planner's session.
sed -i '/^session=/d' "$AREC"
srun collect plan-author pu >"$T/out" 2>&1
check "so collect with no --marker leaves the planner open" '3:0' "$?:$(grep -c 'closed seat' "$T/out")"
# A role routed to its own Codex home (routing's codexHome) writes its sessions there, which no default home holds:
# collect finds its log from the record's command, so its ledger row names it. (The Orca stand-in's pane is a
# Claude one elsewhere, so the verdict is the screen's marker; the ledger's lookup is the seat's own, by its role.)
echo PLAN-DONE > "$T/screen"; L=$(($(date +%s) - 5))
JH=$T/judge-home; mkdir -p "$JH/sessions/2026/10/17"; JL=$JH/sessions/2026/10/17/rollout-sol.jsonl
printf 'handle=h1\ntask=task_1\nrole=plan-judge-sol\nunit=pu\nworktree=pu\nlaunched=%s\nfirst=%s\ntag=seat-sol-1\ncmd=export COMMANDECK_SEAT=plan-judge-sol; CODEX_HOME=%s codex --model gpt-6.1-sol\n' \
  "$L" "$L" "$JH" > "$(dirname "$AREC")/seat-pu-plan-judge-sol.txt"
jq -cn --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg w "$PWT" '
  {type: "session_meta", timestamp: $t, payload: {cwd: $w}},
  {type: "response_item", timestamp: $t, payload: {type: "message", role: "user", content: [{type: "input_text", text: "Judge it. Seat tag seat-sol-1."}]}},
  {type: "event_msg", timestamp: $t, payload: {type: "task_started"}},
  {type: "event_msg", timestamp: $t, payload: {type: "task_complete", last_agent_message: "No findings.\nVERDICT: GO"}}' > "$JL"
# A project that allows the judge its Codex model, so the seat stays a Codex one.
jq --arg m "$(jq -r '.roles["plan-judge-sol"].model' "$REAL/config/routing.json")" '.planModels = [$m]' "$CFG" > "$T/cfg" && mv "$T/cfg" "$CFG"
# A Codex seat's log is not found at launch (no Claude process to ask), so the wait binds it into the record: a
# running judge's spend is then its own, not "Not tied to a seat". A sibling's newer log in the same home and
# worktree, under another seat's tag, is not the one bound.
JREC2=$(dirname "$AREC")/seat-pu-plan-judge-sol.txt; echo "spec=$T/judge-spec.md" >> "$JREC2"
jq -cn --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg w "$PWT" '
  {type: "session_meta", timestamp: $t, payload: {cwd: $w}},
  {type: "response_item", timestamp: $t, payload: {type: "message", role: "user", content: [{type: "input_text", text: "Judge it. Seat tag seat-astra-2."}]}},
  {type: "event_msg", timestamp: $t, payload: {type: "task_started"}}' > "$JH/sessions/2026/10/17/rollout-astra.jsonl"
touch "$T/pane-up"; srun wait plan-judge-sol pu --marker PLAN-DONE --timeout-s 5 >"$T/out" 2>&1
check "a Codex seat's wait binds its own log into the record, not a sibling's" "session=$JL" "$(grep '^session=' "$JREC2" 2>&1)"
touch "$T/pane-up"; COMMANDECK_SEAT_EVENTS=$T/events.jsonl srun collect plan-judge-sol pu --marker PLAN-DONE >"$T/out" 2>&1
check "a judge in its own Codex home is collected, and its ledger row names its log" "0:$JL" "$?:$(jq -r '.session' "$T/events.jsonl" 2>&1 | tail -1)"

# A seat Orca would not dispatch gets its pointer typed, and no preamble then names its task: the typed text
# carries the task id, so the seat's session can be tied to its task (read-verdict.sh --task).
rm -f "$T/pane-up" "$T/sent"; touch "$T/no-dispatch"; jq 'del(.planModels)' "$CFG" > "$T/cfg" && mv "$T/cfg" "$CFG"
COMMANDECK_SEAT_FORCE=1 srun launch plan-judge-claude pu "$T/judge-spec.md" >"$T/out" 2>&1
check "a typed pointer ends with its task id" 'Task id task_1.' "$(grep -m1 'Your task spec' "$T/sent" 2>&1 | grep -o 'Task id task_1\.$')"
rm -f "$T/no-dispatch"

# Issue 233: launch wrote its record only after the tui-idle wait (up to 120 s) and the dispatch retries (60 s); a
# caller that timed out first left a live pane with no record, and its retry opened a second pane.
JREC=$(ls "$HOME/.commandeck/scratch/"*/seat-pu-plan-judge-claude.txt); touch "$T/slow-idle"; rm -f "$T/pane-up"; : > "$T/creates"
# The pane's tui-idle wait lasts until the test removes slow-idle: a launch that waited on it would hit its timeout.
COMMANDECK_SEAT_FORCE=1 COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 seat_sh launch plan-judge-claude pu "$T/judge-spec.md" >"$T/out" 2>&1; RC=$?
check "launch returns while the pane's tui-idle wait still holds, naming the task and phase" "0:1" \
  "$RC:$(grep -c 'handle=h1 task=task_1 phase=launching' "$T/out")"
check "status shows launching meanwhile" "phase=launching handle=h1 task=task_1" "$(seat_sh status plan-judge-claude pu | cut -d' ' -f1-3)"
COMMANDECK_SEAT_FORCE=1 seat_sh launch plan-judge-claude pu "$T/judge-spec.md" >"$T/out" 2>&1
check "a second launch while the first is still launching is refused with its status, and opens no pane" "2:1:1" \
  "$?:$(grep -c 'REFUSED: plan-judge-claude for pu is still launching: phase=launching handle=h1' "$T/out"):$(grep -c . "$T/creates")"
rm -f "$T/slow-idle"; settle pu plan-judge-claude
check "then status shows dispatched" "phase=dispatched" "$(seat_sh status plan-judge-claude pu | cut -d' ' -f1)"
rm -f "$T/pane-up"; touch "$T/no-dispatch" "$T/send-fails"
COMMANDECK_SEAT_FORCE=1 srun launch plan-judge-claude pu "$T/judge-spec.md" >"$T/out" 2>&1
check "a launch whose pointer cannot be sent ends phase=failed, and its log names the cause" "phase=failed:1" \
  "$(seat_sh status plan-judge-claude pu | cut -d' ' -f1):$(grep -c 'send failed to h1' "$JREC.log")"
rm -f "$T/no-dispatch" "$T/send-fails"

# dispatch-task.sh types its own pointer to a Codex pane Orca will not bind. The seat's log is found by the tag in the
# spec, and read-verdict.sh searches typed prompts only, so the typed pointer carries the spec's own tag sentence.
B2=$T/bin2 WTP=$T/codex-wt; mkdir -p "$B2" "$WTP" "$HOME/.codex/sessions"
cat > "$B2/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "terminal list"*) echo '{"result":{"terminals":[{"handle":"h1","agentIdentity":"codex","worktreeId":"w1","worktreePath":"$WTP"}]}}' ;;
  "worktree ps"*) echo '{"result":{"worktrees":[]}}' ;;
  "orchestration task-list"*) jq -n '{result: {tasks: [{id: "task_1", spec: "Read it. Seat tag seat-judge-7-8: it names this session, nothing to do with it."}]}}' ;;
  "orchestration worker-start"*) echo '{"ok":false,"error":{"message":"refused for the test"}}' ;;
  "terminal send"*) while [ \$# -gt 0 ]; do [ "\$1" != --text ] || printf '%s\n' "\$2" > "$T/typed"; shift; done
    echo "{\"cwd\":\"$WTP\"} $T/scratch/dispatch-specs/task_1.md" > "$HOME/.codex/sessions/rollout-x.jsonl"; echo '{"ok":true}' ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
EOF
chmod +x "$B2/orca-ide"
(cd "$PROJ" && COMMANDECK_SCRATCH=$T/scratch PATH="$B2:$PATH" bash "$REAL/scripts/dispatch-task.sh" task_1 terminal:h1 --keep-task </dev/null >"$T/out" 2>&1)
check "a pointer dispatch-task.sh types to a Codex pane carries the spec's seat tag" 'Seat tag seat-judge-7-8' "$(grep -o 'Seat tag seat-judge-7-8' "$T/typed" 2>&1)"

# A unit planned before 0.18.0 plans in its marked <unit>-plan, its plan not yet committed: a seat launched in a new
# <unit> cut from main read no plan.
LWT=$HOME/orca/workspaces/proj/pl-plan; git -C "$PROJ" worktree add -q "$LWT" && echo pl > "$(git -C "$LWT" rev-parse --absolute-git-dir)/commandeck-plan-of"
mkdir -p "$LWT/.claude/plans" && echo draft > "$LWT/.claude/plans/pl.md"; : > "$T/creates"
srun launch plan-judge-claude pl "$T/judge-spec.md" >"$T/out" 2>&1
check "a plan seat of a unit planned in <unit>-plan opens there, its record names it, and no <unit> is made" '0:1:1:no' \
  "$?:$(grep -c -- "path:$LWT " "$T/creates"):$(grep -cx 'worktree=pl-plan' "$HOME/.commandeck/scratch/"*/seat-pl-plan-judge-claude.txt):$([ -e "$HOME/orca/workspaces/proj/pl" ] && echo yes || echo no)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
