#!/usr/bin/env bash
# Self-test: the clear line is 200K for the main checkout only. Run directly.
#
# The owner's condition: lowering main's line must never touch a pane in a linked
# worktree -- the Chief-of-Staff pane runs in one. Both hooks exit when
# git-dir != git-common-dir; this pins that a worktree far past the line gets
# no nag, no block and no checkpoint. COMMANDECK_CLEAR_LINE is deliberately
# unset so the shipped default is what is tested.
set -u

ROOT=$(git rev-parse --show-toplevel)
LINE_HOOK="$ROOT/hooks/context-line.sh"
STOP_HOOK="$ROOT/hooks/context-clear-stop.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
CPD="$BOX/home/.claude/checkpoints"
mkdir -p "$CPD"
git -C "$BOX" init -q repo
git -C "$BOX/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$BOX/repo" worktree add -q "$BOX/wt" 2>/dev/null

run() { # <hook> <dir> <context tokens> -> hook stdout+stderr
  printf '{"message":{"usage":{"cache_read_input_tokens":%s,"input_tokens":0}}}\n' "$3" > "$BOX/t.jsonl"
  (cd "$2" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/t.jsonl" \
    | env -u COMMANDECK_CLEAR_LINE -u COMMANDECK_REVIEWER -u ORCA_TERMINAL_HANDLE ${CLEAR:+COMMANDECK_CLEAR_LINE=$CLEAR} HOME="$BOX/home" bash "$1" 2>&1)
}

# The standard-context option: setup sets the line to 150000, because a 200K
# model is full before a 200K line can fire.
OUT=$(CLEAR=150000 run "$LINE_HOOK" "$BOX/repo" 160000)
check "standard context: 160K is over the 150K line" yes "$(case $OUT in *"over the 150K line"*) echo yes;; *) echo no;; esac)"
check "standard context: 140K is under it" "" "$(CLEAR=150000 run "$LINE_HOOK" "$BOX/repo" 140000)"
check "standard context: the Stop hook demands the checkpoint at 160K" block \
  "$(CLEAR=150000 run "$STOP_HOOK" "$BOX/repo" 160000 | jq -r '.decision' 2>/dev/null)"
# What setup really writes is the project's answer, not an environment variable:
# the hooks read "standardContext" from the project's config themselves.
mkdir -p "$BOX/repo/.claude"; echo '{"version": 1, "standardContext": true}' > "$BOX/repo/.claude/commandeck.json"
check "a standard-context project: 160K is over its line with nothing set in the environment" yes \
  "$(case $(run "$LINE_HOOK" "$BOX/repo" 160000) in *"over the 150K line"*) echo yes;; *) echo no;; esac)"
check "a standard-context project: the Stop hook demands the checkpoint at 160K" block "$(run "$STOP_HOOK" "$BOX/repo" 160000 | jq -r '.decision' 2>/dev/null)"
check "a standard-context project: the environment still overrides" "" "$(CLEAR=170000 run "$LINE_HOOK" "$BOX/repo" 160000)"
rm -r "$BOX/repo/.claude"
check "any other project: 160K is under the 200K line" "" "$(run "$LINE_HOOK" "$BOX/repo" 160000)"
# Main runs in the project; the template it is told to write from is the plugin's.
check "the line names the checkpoint template by its full path" yes "$(case $OUT in *"$ROOT/templates/checkpoint.md"*) echo yes;; *) echo no;; esac)"

OUT=$(run "$LINE_HOOK" "$BOX/repo" 210000)
check "main checkout at 210K prints the line" yes "$(case $OUT in *"over the 200K line"*) echo yes;; *) echo no;; esac)"
check "main checkout at 190K is under the line" "" "$(run "$LINE_HOOK" "$BOX/repo" 190000)"
check "main checkout at 210K: the Stop hook demands the checkpoint" block \
  "$(run "$STOP_HOOK" "$BOX/repo" 210000 | jq -r '.decision' 2>/dev/null)"

check "linked worktree at 400K: the line hook prints nothing" "" "$(run "$LINE_HOOK" "$BOX/wt" 400000)"
touch "$CPD/sid.handoff"
check "linked worktree at 400K with /handoff: the Stop hook prints nothing" "" "$(run "$STOP_HOOK" "$BOX/wt" 400000)"
check "and writes no checkpoint, resume prompt or restart marker" "" \
  "$(ls "$CPD" | grep -v -e '^clear-hook.log$' -e '^sid.handoff$')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
