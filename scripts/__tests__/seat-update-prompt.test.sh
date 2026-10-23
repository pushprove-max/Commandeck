#!/usr/bin/env bash
# seat-update-prompt.test.sh -- issue 314: seat.sh launch and a Codex pane that opens on Codex's own update prompt, on
# the hand-written commandeck.json of fixtures/seat-setup.sh. Its own file, not in seat-launch.test.sh: with these cases
# that file ran 106 s of the runner's 120 s per-file cap under load.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"
# The judge's planning worktree and spec, by seat-launch.test.sh's setup lines; the judge runs on Codex.
PWT=$HOME/orca/workspaces/proj/pu; git -C "$PROJ" worktree add -q "$PWT" && echo pu > "$(git -C "$PWT" rev-parse --absolute-git-dir)/commandeck-plan-of"
mkdir -p "$PWT/.claude/plans"; echo 'the plan' > "$PWT/.claude/plans/pu.md"
printf 'Judge the plan.\nEnd on a line of its own.\n' > "$T/judge-spec.md"
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"planJudgeSolAgent": "codex"}}}}' > "$HOME/.claude/settings.json"

# Issue 314: a Codex pane that opens on Codex's own "Update available" prompt sits there and never takes the task. The
# launch answers Skip (key 2, never Update now: that runs the installer and exits Codex, the task untaken) after the
# tui-idle wait, logs it, and checks again; a pane still on the prompt ends the launch phase=failed, naming it. The screen
# is the prompt as Codex 0.162.1 renders it (codex-rs/tui/src/update_prompt.rs, snapshot update_prompt_modal): the heading
# and the choices indented two spaces, the selected choice marked with a bullet, no "!" after "available".
printf '\n  Update available · 0.40.0 → 0.41.0\n  Release notes: https://github.com/openai/codex/releases/latest\n\n› 1. Update now (runs `npm install -g @openai/codex`)\n  2. Skip\n  3. Skip until next version\n\n  enter continue · esc skip\n' > "$T/prompt-screen"
cp "$T/prompt-screen" "$T/screen"; echo 'Codex ready' > "$T/after-skip"; rm -f "$T/pane-up" "$T/sent" "$T/waits"
COMMANDECK_SEAT_FORCE=1 srun launch plan-judge-sol pu "$T/judge-spec.md" --model gpt-9.1-astra >"$T/out" 2>&1
JREC=$(ls "$HOME/.commandeck/scratch/"*/seat-pu-plan-judge-sol.txt)
check "a Codex pane on the update prompt: the launch answers Skip, logs it, and dispatches" "1:1:phase=dispatched" \
  "$(grep -cx 2 "$T/sent"):$(grep -c 'codex update prompt: answered Skip (0.40.0 → 0.41.0); Codex is updated outside panes: bash .*update.sh' "$JREC.log"):$(seat_sh status plan-judge-sol pu | cut -d' ' -f1)"
# --timeout-ms 15000 as a whole word: a plain substring check also passes on 150000.
check "and the answer is waited on once, within 15000 ms" 1 "$(grep -cE -- '--for tui-idle --timeout-ms 15000( |$)' "$T/waits")"
cp "$T/prompt-screen" "$T/screen"; rm -f "$T/after-skip" "$T/pane-up" "$T/sent" "$T/waits"
COMMANDECK_SEAT_FORCE=1 srun launch plan-judge-sol pu "$T/judge-spec.md" --model gpt-9.1-astra >"$T/out" 2>&1
check "a pane still on the update prompt after Skip ends the launch phase=failed, naming it, one 15000 ms wait" "phase=failed:1:1" \
  "$(seat_sh status plan-judge-sol pu | cut -d' ' -f1):$(grep -c 'Codex pane held by its update prompt after answering Skip; run: bash .*update.sh' "$JREC.log"):$(grep -cE -- '--for tui-idle --timeout-ms 15000( |$)' "$T/waits")"
# Pass 1: a refused Skip send, or screen reads that fail after it, were taken as proof the prompt was gone ("answered
# Skip", then dispatch). Only a screen read without the prompt clears it; anything else ends the launch phase=failed.
upd_fail=
for v in 'send-fails:Skip could not be sent' 'skip-breaks-read:screen could not be read after answering Skip'; do
  cp "$T/prompt-screen" "$T/screen"; echo 'Codex ready' > "$T/after-skip"; rm -f "$T/pane-up" "$T/read-fails"; touch "$T/${v%%:*}"
  COMMANDECK_SEAT_FORCE=1 srun launch plan-judge-sol pu "$T/judge-spec.md" --model gpt-9.1-astra >"$T/out" 2>&1
  upd_fail+="${v%%:*}=$(seat_sh status plan-judge-sol pu | cut -d' ' -f1):$(grep -c 'answered Skip' "$JREC.log"):$(grep -c "${v#*:}" "$JREC.log") "
  rm -f "$T/${v%%:*}" "$T/read-fails"
done
check "a failed Skip send, or failed screen reads after it, end the launch phase=failed naming it, never 'answered Skip'" \
  "send-fails=phase=failed:0:1 skip-breaks-read=phase=failed:0:1 " "$upd_fail"
# Every Orca call of the prompt check is bounded: a screen read that never returns ends the launch phase=failed, here
# within 40 s of this test's own wait (8 s a call), not when Orca gives up. The stalled read ignores TERM (pass 2):
# only the KILL after it ends the call.
cp "$T/prompt-screen" "$T/screen"; rm -f "$T/pane-up"; touch "$T/slow-read"
(export COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 COMMANDECK_SEAT_FORCE=1; seat_sh launch plan-judge-sol pu "$T/judge-spec.md" --model gpt-9.1-astra) >"$T/out" 2>&1
p=$(sed -n 's/^pid=//p' "$JREC" | tail -1); for _ in $(seq 200); do kill -0 "$p" 2>/dev/null || break; sleep 0.2; done
check "a screen read that never returns ends the launch phase=failed within the bound" "done:phase=failed" \
  "$(kill -0 "$p" 2>/dev/null && echo running || echo done):$(seat_sh status plan-judge-sol pu | cut -d' ' -f1)"
rm -f "$T/slow-read"; settle pu plan-judge-sol

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
