#!/usr/bin/env bash
# The owner sits in the Chief-of-Staff pane, so its picker is how a decision is
# put to them. Main acts on the relayed answer only after it finds the answer
# in the project's rulings log, so an answer picked in the relay pane must land
# there -- in the primary checkout's log, not one named for the worktree -- or
# main can never verify what the relay tells it.
set -u
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$TMP"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }

git init -q "$TMP/proj" && git -C "$TMP/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$TMP/proj" worktree add -q "$TMP/Chief-of-Staff" -b cos 2>/dev/null
mkdir -p "$TMP/home"
COS=$TMP/Chief-of-Staff
in_cos() { (cd "$COS" && env -u COMMANDECK_RULING_LOG -u COMMANDECK_HOOK_FIRE_LOG -u COMMANDECK_REVIEWER \
  HOME="$TMP/home" CLAUDE_PROJECT_DIR="$COS" bash "$HOOKS/$1" 2>/dev/null); }

# It asks under main's rules: the decoy leads, so a stray Enter picks nothing.
. "$HOOKS/lib/ask-decoy.sh"
ask() { jq -cn --args '{tool_name:"AskUserQuestion", session_id:"s-cos", tool_input:{questions:[{question:"Push now?", header:"Push", options:[$ARGS.positional[] | {label:.}]}]}}' "$@"; }
ASK=$(ask "$ASK_DECOY" Yes No)
in_cos worker-ask-guard.sh <<<"$ASK" >/dev/null
check "the relay pane's picker is let through" 0 "$?"
in_cos worker-ask-guard.sh <<<"$(ask Yes No)" >/dev/null
check "but not without the decoy first" 2 "$?"

OUT=$(jq -c '. + {hook_event_name:"PostToolUse", cwd:"'"$COS"'", tool_response:{answers:{"Push now?":"Yes"}}}' <<<"$ASK" | in_cos ruling-log.sh)
L=$TMP/home/.claude/rulings/proj.jsonl
check "the answer is one row in the primary checkout's rulings log" 1 "$(wc -l < "$L" 2>/dev/null | tr -d ' ')"
check "with the question and the answer the owner picked" "Push now?|Yes" "$(jq -r '"\(.question)|\(.answer)"' "$L" 2>/dev/null)"
ID=$(jq -r '.id' "$L" 2>/dev/null)
check "and the pane is handed the ruling id to relay" yes "$(case $OUT in *"$ID"*) echo yes;; *) echo no;; esac)"
check "no log is named for the worktree" "" "$(ls "$TMP/home/.claude/rulings" | grep -i chief)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
