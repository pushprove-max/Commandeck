#!/usr/bin/env bash
# seat.test.sh -- seat.sh launches and reads the panes main works through, on a hand-written commandeck.json (no
# setup run). What this pins: a headless role is never opened as a pane; a read-only seat is refused a spec
# that asks it to write a file, but not prose that ends on the verb; a live Builder pane is reused only while the
# project's Builder settings are the ones it opened with; a pane quoting a verdict in a fence is still working; and
# a pointer dispatch-task.sh types to a Codex pane carries the spec's seat tag. The setup is fixtures/seat-setup.sh.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"

# The reviewer on its Claude agent (codexReviewerAgent=claude, the fixture's) is headless through its overlay.
run launch codex-reviewer seat-unit "$T/spec.md" >"$T/out" 2>&1
check "a headless role is refused as a pane seat" "2:1" "$?:$(grep -c 'is not a pane seat' "$T/out")"
printf 'Write the findings to out.md.\n' > "$T/spec-w.md"; printf 'Read the fenced write). Map: x.md\n' > "$T/spec-p.md"
# On codex the reviewer is a read-only Codex pane seat.
jq '.pluginConfigs["commandeck@commandeck"].options.codexReviewerAgent = "codex"' "$HOME/.claude/settings.json" > "$T/s" && mv "$T/s" "$HOME/.claude/settings.json"
check "a read-only seat asked to write a file is refused; a clause ending on the verb is not an ask" '1:0' \
  "$(run launch codex-reviewer seat-unit "$T/spec-w.md" 2>&1 | grep -c 'spec asks it to write'):$(run launch codex-reviewer seat-unit "$T/spec-p.md" 2>&1 | grep -c 'spec asks it to write')"

seat() { COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch builder seat-builder "$T/spec.md"; }
# A model other than routing's default (opus), so that dropping the key changes what the seat is launched with.
jq '.pluginConfigs["commandeck@commandeck"].options.builderModel = "sonnet"' "$HOME/.claude/settings.json" > "$T/s" && mv "$T/s" "$HOME/.claude/settings.json"
seat >"$T/out" 2>&1; check "the first Builder launch opens a pane" 0 $?
seat >"$T/out" 2>&1; check "a second launch on the same settings reuses it" '0:1' "$?:$(grep -c 'state=reused' "$T/out")"
jq 'del(.pluginConfigs["commandeck@commandeck"].options.builderModel)' "$HOME/.claude/settings.json" > "$T/s" && mv "$T/s" "$HOME/.claude/settings.json"
seat >"$T/out" 2>&1
check "once the Builder's model key changed, the live pane is refused, and the refusal says why" '2:0:1' \
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
# A seat launched by hand is held to the launcher's floor: medium under a Builder default of high would lower it.
jq '.pluginConfigs["commandeck@commandeck"].options.builderEffort = "high"' "$HOME/.claude/settings.json" > "$T/s" && mv "$T/s" "$HOME/.claude/settings.json"
run launch builder seat-builder "$T/spec.md" --effort medium >"$T/out" 2>&1
check "--effort medium under a Builder default of high is refused before any pane opens" '2:1' \
  "$?:$(grep -c "REFUSED: --effort medium is below this project's Builder default high" "$T/out")"
# Issue 293: the /config effort reaches the launch command itself, not only the resolver; the project's builder.effort,
# an older setup's, is not read (issue 312).
unset CLAUDE_CONFIG_DIR; mkdir -p "$HOME/.claude"
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"builderEffort": "high"}}}}' > "$HOME/.claude/settings.json"
jq '.builder = {effort: "medium"}' "$CFG" > "$T/cfg" && mv "$T/cfg" "$CFG"; rm -f "$T/pane-up"
COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch builder seat-builder "$T/spec.md" >"$T/out" 2>&1
check "a Builder launched with /config's effort high, the project's file saying medium, opens with --effort high" '0:1' \
  "$?:$(grep '^cmd=' "$HOME/.commandeck/scratch/"*/seat-seat-builder-builder.txt | tail -1 | grep -cE -- ' --effort high( |$)')"
# Green pins (issue 293): high is routing's own default, so the case above would pass with the /config key ignored.
cfg_effort() { echo "{\"pluginConfigs\": {\"commandeck@commandeck\": {\"options\": {\"builderEffort\": \"$1\"}}}}" > "$HOME/.claude/settings.json"
  jq --arg e "$2" '.builder = {effort: $e}' "$CFG" > "$T/cfg" && mv "$T/cfg" "$CFG"; rm -f "$T/pane-up"; }
cmd_effort() { grep '^cmd=' "$HOME/.commandeck/scratch/"*/seat-seat-builder-builder.txt | tail -1 | grep -oE -- '--effort [a-z]+'; }
cfg_effort max medium
COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch builder seat-builder "$T/spec.md" >"$T/out" 2>&1
check "a Builder launched with /config's effort max, the project's file saying medium, opens with --effort max" '0:--effort max' "$?:$(cmd_effort)"
cfg_effort medium low
COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch builder seat-builder "$T/spec.md" --effort high >"$T/out" 2>&1
check "/config effort medium, the project's file saying low and a launch pin --effort high: the cmd= line has --effort high" '0:--effort high' "$?:$(cmd_effort)"
rm "$HOME/.claude/settings.json"

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

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
