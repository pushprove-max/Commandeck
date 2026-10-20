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

# A prompt closes a plain-chat ask only when it names it: an unrelated line, or one typed in another session,
# closed every open ask. Named is the id, or the id without its day, as whole words in any case or spacing.
# A Builder's question waiting on main is never the owner's to close in chat: main answers it with answer-worker.sh.
git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
dec() { (cd "$T/p" && bash "${HOOK%/hooks/*}/scripts/decision.sh" "$@" >/dev/null 2>&1); }
open() { (cd "$T/p" && bash "${HOOK%/hooks/*}/scripts/decision.sh" list 2>/dev/null) | jq -r '[.[] | select(.answeredAt == null) | .id] | join(" ")'; }
dec add export-batch-2026-10-15 "Ship the export batch now?" yes main
dec add retry-cap "Raise the retry cap?" no main
dec add u1-msg_1 "Which fixture?: the old one or the new one" none "u1 asks" --waits-on main
prompt "the export looks slow today"
check "a prompt that names no open ask closes none" "export-batch-2026-10-15 retry-cap u1-msg_1" "$(open)"
prompt "Export Batch: yes, ship it"
check "a prompt naming an ask by its id without the day closes that one only" "retry-cap u1-msg_1" "$(open)"
prompt "retry-cap no, and u1-msg_1 the new one"
check "a Builder's question waiting on main stays open whatever the owner types" "u1-msg_1" "$(open)"

# Issue 232: a picker answer that came back empty read as a ruling of nothing, and main went on. The hook says to
# ask once more as a single question, logs no ruling, and leaves the decision open; so does the decoy's label.
DAY=$(date +%Y-%m-%d)
dec add "pick-fixture-$DAY" "Which seed file?" new AskUserQuestion
ask() { (cd "$T/p" && jq -n --arg a "$1" '{hook_event_name: "PostToolUse", session_id: "s2", cwd: ".",
  tool_input: {questions: [{header: "Pick fixture", question: "Which seed file?", options: [{label: "old"}, {label: "new"}]}]},
  tool_response: {answers: {"Which seed file?": $a}}}' | bash "$HOOK" 2>&1); }
OUT=$(ask "")
check "an empty answer prints the retry text, is no ruling, and leaves the decision open" "1 true pick-fixture-$DAY" \
  "$(grep -ci 'the answer came back empty; ask it once more as a single question' <<<"$OUT") $(tail -1 "$COMMANDECK_RULING_LOG" | jq .void) $(open | tr ' ' '\n' | grep -x "pick-fixture-$DAY")"
. "${HOOK%/*}/lib/ask-decoy.sh"
check "the decoy's label prints it too" 1 "$(ask "$ASK_DECOY" | grep -c 'ask it once more as a single question')"

# A row can be hundreds of KB, and an append that size is not one write: two hooks at once interleaved into one
# damaged line. The append holds a lock on the log, so a writer that holds it makes the hook wait.
export COMMANDECK_RULING_LOG=$T/lock/log.jsonl; mkdir -p "$T/lock"; : > "$COMMANDECK_RULING_LOG"
( exec 9>>"$COMMANDECK_RULING_LOG"; flock -x 9; : > "$T/held"; until [ -e "$T/release" ]; do sleep 0.05; done ) &
HOLDER=$!
until [ -e "$T/held" ]; do sleep 0.05; done
prompt "locked out for now" & WRITER=$!
sleep 1
check "the hook does not append while another writer holds the log's lock" 0 "$(rows)"
: > "$T/release"; wait "$HOLDER"; wait "$WRITER"
check "and appends once the lock is free" 1 "$(rows)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
