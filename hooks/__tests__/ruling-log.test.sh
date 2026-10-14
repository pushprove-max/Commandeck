#!/usr/bin/env bash
# ruling-log.sh reads the prompt. Since Claude Code 2.1.299 a UserPromptSubmit
# hook sees a slash command as typed ("/handoff now"), before the skill expands.
# A command is not the owner answering anything: logged, it would stand as a
# ruling a memory line could cite, and close the open asks a real answer closes.
set -uo pipefail
HOOK=$(cd "$(dirname "$0")/.." && pwd)/ruling-log.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
git init -q "$T/p"
export COMMANDECK_RULING_LOG=$T/rulings.jsonl
prompt() { (cd "$T/p" && jq -n --arg p "$1" '{hook_event_name: "UserPromptSubmit", session_id: "s1", prompt: $p}' | bash "$HOOK" >/dev/null 2>&1); }
rows() { [ -f "$COMMANDECK_RULING_LOG" ] && wc -l < "$COMMANDECK_RULING_LOG" | tr -d ' ' || echo 0; }

prompt "/handoff now"
prompt "/commandeck:setup"
prompt "/effort high"
check "a slash command, as typed, is no ruling" 0 "$(rows)"
prompt "/Users/x/notes.md is the file I meant"
check "a prompt that starts with a path is still the owner's words" 1 "$(rows)"
prompt "yes, ship it"
check "a plain answer is logged as one" 2 "$(rows)"

prompt "/tmp is the directory I meant"
check "a prompt whose first word is a root folder is the owner's words too" 3 "$(rows)"
prompt "/artifacts is the output directory to create"
check "a path that does not exist yet is the owner's words too" 4 "$(rows)"
# The handoff's resume prompt is typed by a script: logged void, it answers no open ask.
prompt "resume from the checkpoint /x/cp.md (its text, board.sh and the run-use binding are already in your SessionStart context; do not fetch them again, except a part its RESUMED line names as cut); rebuild its Todo list with TaskCreate and keep it current on every step; arm nothing (main-watch.sh wakes you); then service whichever marker has landed. Your first line to the owner is: Handoff done: this is the new main session, resumed from /x/cp.md; the old pane term_a closes now."
check "the handoff's resume prompt, with its first-line instruction, is void" true "$(tail -1 "$COMMANDECK_RULING_LOG" | jq .void)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
