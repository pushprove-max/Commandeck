#!/usr/bin/env bash
# seat.sh collect closes a seat on the verdict read-verdict.sh hands it, so a
# GO that is not that seat's latest answer closes work that is still running.
# Two ways it happened: a second Codex session in the same worktree had ended
# GO while the seat's own was still working, and a seat's earlier GO was read
# while its follow-up turn ran.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
WT=$TMP/ws/unit; mkdir -p "$WT" "$TMP/home" "$TMP/scratch" "$TMP/bin"
printf '#!/bin/sh\necho "{}"\n' > "$TMP/bin/orca-ide"; chmod +x "$TMP/bin/orca-ide"
meta() { jq -cn --arg cwd "$WT" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{timestamp: $ts, type: "session_meta", payload: {cwd: $cwd, model: "m"}}'; }
msg() { jq -cn --arg r "$1" --arg t "$2" '{type: "response_item", payload: {type: "message", role: $r, content: [{type: (if $r == "user" then "input_text" else "output_text" end), text: $t}]}}'; }
read_it() { # codex home -> "<exit code> <go|none>"
  local out rc
  out=$(PATH="$TMP/bin:$PATH" HOME="$TMP/home" CODEX_HOME="$1" COMMANDECK_SCRATCH="$TMP/scratch" COMMANDECK_MAIN="$TMP" \
    bash "$REAL/scripts/read-verdict.sh" term_x 5 "$WT" codex unit "" 0 0 2>&1); rc=$?
  echo "$rc $(grep -q '^VERDICT: GO$' <<<"$out" && echo go || echo none)"
}

A=$TMP/a/sessions; mkdir -p "$A"
{ meta; msg user "Review the diff."; msg assistant $'Looks fine.\nVERDICT: GO'; } > "$A/one.jsonl"
check "a finished session's verdict is read" "0 go" "$(read_it "$TMP/a")"
{ msg user "One more file changed; review again."; msg assistant "Reading the new file."; } >> "$A/one.jsonl"
check "an earlier GO is not the answer while a follow-up turn runs" "3 none" "$(read_it "$TMP/a")"
msg assistant $'Still fine.\nVERDICT: GO' >> "$A/one.jsonl"
check "the follow-up's own verdict is read once it is written" "0 go" "$(read_it "$TMP/a")"

# Codex narrates while it works; a verdict word in that commentary is not its answer.
E=$TMP/e/sessions; mkdir -p "$E"
{ meta; msg user "Review the diff."
  jq -cn '{type: "response_item", payload: {type: "message", role: "assistant", phase: "commentary", content: [{type: "output_text", text: "First file looks fine so far.\nVERDICT: GO"}]}}'; } > "$E/one.jsonl"
check "a verdict in Codex commentary is not read as the answer" "3 none" "$(read_it "$TMP/e")"

B=$TMP/b/sessions; mkdir -p "$B"
{ meta; msg user "Review the diff."; msg assistant $'Fine.\nVERDICT: GO'; } > "$B/sibling.jsonl"
touch -d '10 minutes ago' "$B/sibling.jsonl"
{ meta; msg user "Review the diff."; msg assistant "Still reading."; } > "$B/target.jsonl"
# No seat record names this handle, so nothing says which of two sessions is the seat's.
check "two sessions and nothing to tell them apart is refused, not guessed" "7 none" "$(read_it "$TMP/b")"
# With a seat record the spec binds the session: the seat's own is the one that was given its spec.
C=$TMP/c/sessions; mkdir -p "$C"
{ meta; msg user "Your task spec is the file $TMP/spec-target.md."; msg assistant "Still reading."; } > "$C/target.jsonl"
touch -d '10 minutes ago' "$C/target.jsonl"
{ meta; msg user "Your task spec is the file $TMP/spec-sibling.md."; msg assistant $'Fine.\nVERDICT: GO'; } > "$C/sibling.jsonl"
printf 'handle=term_x\nspec=%s\n' "$TMP/spec-target.md" > "$TMP/scratch/seat-unit-luna-reviewer.txt"
check "a NEWER sibling's GO does not answer for the seat still working" "3 none" "$(read_it "$TMP/c")"
msg assistant $'Done.\nVERDICT: NO-GO' >> "$C/target.jsonl"; touch -d '5 minutes ago' "$C/target.jsonl"
check "the seat's own verdict is the one read" 0 "$(read_it "$TMP/c" | cut -d' ' -f1)"
rm "$TMP/scratch/seat-unit-luna-reviewer.txt"

# A seat record with a spec binds even a lone session: a sibling can finish
# before the seat's own session has written a line.
F=$TMP/f/sessions; mkdir -p "$F"
{ meta; msg user "Your task spec is the file $TMP/spec-sibling.md."; msg assistant $'Fine.\nVERDICT: GO'; } > "$F/sibling.jsonl"
printf 'handle=term_x\nspec=%s\n' "$TMP/spec-target.md" > "$TMP/scratch/seat-unit-luna-reviewer.txt"
check "a lone session that was handed another spec is not the seat's" none "$(read_it "$TMP/f" | cut -d' ' -f2)"
rm "$TMP/scratch/seat-unit-luna-reviewer.txt"

# Being handed a spec is a prompt naming it. A sibling that only READ the
# seat's spec (a command's output carries the path) was not handed it.
H=$TMP/h/sessions; mkdir -p "$H"
fn_out() { jq -cn --arg o "$1" '{type: "response_item", payload: {type: "function_call_output", call_id: "c", output: $o}}'; }
{ meta; msg user "Your task spec is the file $TMP/spec-sibling.md."; fn_out "$TMP/spec-target.md"; msg assistant $'Fine.\nVERDICT: GO'; } > "$H/sibling.jsonl"
printf 'handle=term_x\nspec=%s\n' "$TMP/spec-target.md" > "$TMP/scratch/seat-unit-luna-reviewer.txt"
check "a sibling whose command output names the seat's spec is not the seat's" none "$(read_it "$TMP/h" | cut -d' ' -f2)"
# A long log is still the seat's: the spec sits in its first prompt and megabytes follow.
I=$TMP/i/sessions; mkdir -p "$I"
{ meta; msg user "Your task spec is the file $TMP/spec-target.md."
  pad=$(msg assistant "$(printf 'x%.0s' $(seq 1 1000))"); for _ in $(seq 1 1500); do printf '%s\n' "$pad"; done
  msg assistant $'Fine.\nVERDICT: GO'; } > "$I/target.jsonl"
check "the seat's own long log is still read" "0 go" "$(read_it "$TMP/i")"
rm "$TMP/scratch/seat-unit-luna-reviewer.txt"

# A command's output can quote the line Codex prints for a background process
# (a test fixture, this file). Only Codex's own header, ahead of "Output:", counts.
G=$TMP/g/sessions; mkdir -p "$G"
out_row() { jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg o "$1" '{timestamp: $ts, type: "response_item", payload: {type: "function_call_output", call_id: "c", output: $o}}'; }
done_row() { jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{timestamp: $ts, type: "event_msg", payload: {type: "task_complete", last_agent_message: "all read"}}'; }
state() { PATH="$TMP/bin:$PATH" HOME="$TMP/home" CODEX_HOME="$TMP/g" COMMANDECK_SCRATCH="$TMP/scratch" COMMANDECK_MAIN="$TMP" \
  bash "$REAL/scripts/read-verdict.sh" --state --worktree "$WT" --agent codex --launched 1 2>&1 | sed -n 's/^outstanding=//p'; }
{ meta; msg user "Read the fixture."; out_row $'Chunk ID: a1\nWall time: 0.1 seconds\nOutput:\nProcess running with session ID 4242\n'; done_row; } > "$G/one.jsonl"
check "the line quoted inside a command's output starts no background command" "" "$(state)"
{ meta; msg user "Start the server."; out_row $'Chunk ID: a2\nWall time: 10 seconds\nProcess running with session ID 77\nOutput:\nlistening\n'; done_row; } > "$G/one.jsonl"
check "the same line in the header still does" 77 "$(state)"

# A finished Codex turn with no verdict hands back its last words; a marker sits at their end.
D=$TMP/d/sessions; mkdir -p "$D"
{ meta; msg user "Write the plan."; msg assistant "plan"
  jq -cn --arg m "$(printf 'x%.0s' $(seq 1 3000)) PLAN-DONE" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{timestamp: $ts, type: "event_msg", payload: {type: "task_complete", last_agent_message: $m}}'; } > "$D/long.jsonl"
check "a long last message keeps its closing marker" 1 \
  "$(PATH="$TMP/bin:$PATH" HOME="$TMP/home" CODEX_HOME="$TMP/d" COMMANDECK_SCRATCH="$TMP/scratch" COMMANDECK_MAIN="$TMP" \
     bash "$REAL/scripts/read-verdict.sh" term_x 5 "$WT" codex unit "" 0 0 2>&1 | grep -c 'PLAN-DONE$')"

# The same rule for a Claude seat, whose log is bound by the seat record's session.
PROJ=$TMP/home/.claude/projects/$(printf '%s' "$WT" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$PROJ"
printf 'handle=term_c\nsession=s1\n' > "$TMP/scratch/seat-unit-certifier.txt"
cu() { jq -cn --arg t "$1" '{type: "user", message: {role: "user", content: $t}}'; }
ca() { jq -cn --arg t "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $t}]}}'; }
tool_result() { jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", content: "ok"}]}}'; }
read_claude() {
  local out rc
  out=$(PATH="$TMP/bin:$PATH" HOME="$TMP/home" COMMANDECK_SCRATCH="$TMP/scratch" COMMANDECK_MAIN="$TMP" \
    bash "$REAL/scripts/read-verdict.sh" term_c 5 "$WT" claude unit "" 0 0 2>&1); rc=$?
  echo "$rc $(grep -q '^VERDICT: GO$' <<<"$out" && echo go || echo none)"
}
{ cu "Review the diff."; ca "Reading."; tool_result; ca $'Fine.\nVERDICT: GO'; } > "$PROJ/s1.jsonl"
check "Claude: a finished review's verdict is read, tool results and all" "0 go" "$(read_claude)"
{ cu "<task-notification>a background task ended</task-notification>"; ca "Noted."; } >> "$PROJ/s1.jsonl"
check "Claude: a harness notice after the verdict is not a new prompt" "0 go" "$(read_claude)"
{ cu "One more file changed; review again."; ca "Reading the new file."; tool_result; } >> "$PROJ/s1.jsonl"
check "Claude: an earlier GO is not the answer while a follow-up turn runs" none "$(read_claude | cut -d' ' -f2)"
ca $'Still fine.\nVERDICT: GO' >> "$PROJ/s1.jsonl"
check "Claude: the follow-up's own verdict is read once it is written" "0 go" "$(read_claude)"
# A notice and typed text can share one row; the typed text is still a prompt.
{ cu $'<task-notification>a task ended</task-notification>\nNow review the fourth file.'; ca "Reading the fourth file."; } >> "$PROJ/s1.jsonl"
check "Claude: typed text after a notice in the same row ends the earlier GO" none "$(read_claude | cut -d' ' -f2)"
ca $'Fourth file fine.\nVERDICT: GO' >> "$PROJ/s1.jsonl"
# Only the harness's own notices are skipped: a prompt that opens with any other tag is a prompt.
{ cu "<review>Check the third file too.</review>"; ca "Reading the third file."; } >> "$PROJ/s1.jsonl"
check "Claude: a follow-up prompt that opens with a tag still ends the earlier GO" none "$(read_claude | cut -d' ' -f2)"

# A Claude pane that is gone and left no session id is tied by launch time: the
# seat's session is the first to start after it. A sibling that started later
# and ended GO does not answer while that first session is still working.
WT2=$TMP/ws/unit2; mkdir -p "$WT2"
PROJ2=$TMP/home/.claude/projects/$(printf '%s' "$WT2" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$PROJ2"
{ cu "Review the diff."; ca "Reading."; } > "$PROJ2/target.jsonl"; touch -d '10 minutes ago' "$PROJ2/target.jsonl"
{ cu "Review the other diff."; ca $'Fine.\nVERDICT: GO'; } > "$PROJ2/sibling.jsonl"; touch -d '5 minutes ago' "$PROJ2/sibling.jsonl"
OUT=$(PATH="$TMP/bin:$PATH" HOME="$TMP/home" COMMANDECK_SCRATCH="$TMP/scratch" COMMANDECK_MAIN="$TMP" \
  bash "$REAL/scripts/read-verdict.sh" term_gone 5 "$WT2" claude unit2 "" 0 "$(date -d '20 minutes ago' +%s)" 2>&1)
check "Claude: with no session id a later sibling's GO does not answer for the first session" none \
  "$(grep -q '^VERDICT: GO$' <<<"$OUT" && echo go || echo none)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
