#!/usr/bin/env bash
# seat-fence.test.sh -- seat.sh's waits and collects on a plan seat, on the hand-written commandeck.json of
# fixtures/seat-setup.sh. What this pins: a pane quoting a verdict in a fence is still working, whatever the screen
# shows of the fence; the session log outranks the screen; and a Codex seat's wait binds its own log.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"
# The judge these cases read, launched in pu's planning worktree by the setup lines of seat-plan-marker.test.sh.
PWT=$HOME/orca/workspaces/proj/pu; git -C "$PROJ" worktree add -q "$PWT" && echo pu > "$(git -C "$PWT" rev-parse --absolute-git-dir)/commandeck-plan-of"
printf 'Judge the plan.\nEnd on a line of its own.\n' > "$T/judge-spec.md"
srun launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1
JREC=$(ls "$HOME/.commandeck/scratch/"*/seat-pu-plan-judge-sol.txt)

# Sol r4: with no session log to read, the idle screen decides, and a marker it shows inside a fence is a quoted
# sample, never the pane's own: three idle polls of it saved the marker and flagless collect closed the seat.
printf 'Still judging.\n```\nPLAN-DONE\n```\nPlease clarify the scope.\n' > "$T/screen"
srun wait plan-judge-sol pu --marker PLAN-DONE --timeout-s 3 >"$T/out" 2>&1
check "an idle screen quoting the marker in a fence, with no session log, is not released" '1:0' "$?:$(grep -c '^marker=' "$JREC")"
srun collect plan-judge-sol pu --marker PLAN-DONE >"$T/out" 2>&1
check "and collect, even given the marker, keeps the pane open" '3:0' "$?:$(grep -c 'closed seat' "$T/out")"
# A screen is a viewport: one that opens inside the fence, its opening line scrolled away, still quotes the marker.
printf 'PLAN-DONE\n```\nPlease clarify the scope.\n' > "$T/screen"
srun wait plan-judge-sol pu --marker PLAN-DONE --timeout-s 3 >"$T/out" 2>&1
check "a screen opening inside a fence that quotes the marker is not released" '1:0' "$?:$(grep -c '^marker=' "$JREC")"
# Sol r5: a real bare opening fence still streaming is the same text as a cropped closing one; ambiguity never releases.
printf 'Still judging.\n```\nPLAN-DONE\n' > "$T/screen"
srun wait plan-judge-sol pu --marker PLAN-DONE --timeout-s 3 >"$T/out" 2>&1
check "a screen ending inside a bare fence that quotes the marker is not released" '1:0' "$?:$(grep -c '^marker=' "$JREC")"
srun collect plan-judge-sol pu --marker PLAN-DONE >"$T/out" 2>&1
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
# The judge's agent key on codex, so the seat is a Codex one.
jq '.pluginConfigs["commandeck@commandeck"].options.planJudgeSolAgent = "codex"' "$HOME/.claude/settings.json" > "$T/s" && mv "$T/s" "$HOME/.claude/settings.json"
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

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
