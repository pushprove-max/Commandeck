#!/usr/bin/env bash
# Main follows a build through the papers in the worktree's .claude/briefs/;
# reading the Builder's code itself fills main's context with work that is not
# its own. The owner retired symbols-before-read.sh (agents worked around nearly
# all of its blocks) but kept this one rule, so both halves are pinned: the
# boundary holds in its new hook, and no symbols-before-read hook is wired.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
HOOK=$REAL/hooks/main-worktree-read-guard.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP/main" && git -C "$TMP/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
WT=$TMP/orca/workspaces/proj/unit-a; mkdir -p "${WT%/*}"
git -C "$TMP/main" worktree add -q "$WT" 2>/dev/null
# hook <cwd> <tool> <input json> -> the hook's exit code
hook() { jq -cn --arg cwd "$1" --arg t "$2" --argjson i "$3" '{cwd: $cwd, tool_name: $t, tool_input: $i}' \
  | env -u COMMANDECK_REVIEWER COMMANDECK_HOOK_FIRE_LOG="$TMP/fire.jsonl" bash "$HOOK" 2>"$TMP/err"; echo $?; }
check "main reading a worktree's code is refused" 2 "$(hook "$TMP/main" Read "{\"file_path\": \"$WT/src/a.sh\"}")"
check "the refusal points at the briefs folder" 1 "$(grep -c 'under that worktree.s .claude/briefs/' "$TMP/err")"
check "main searching a worktree is refused" 2 "$(hook "$TMP/main" Grep "{\"pattern\": \"x\", \"path\": \"$WT/src\"}")"
check "main globbing into a worktree is refused" 2 "$(hook "$TMP/main" Glob "{\"pattern\": \"$WT/**/*.sh\"}")"
check "main reading a worktree's evidence file passes" 0 "$(hook "$TMP/main" Read "{\"file_path\": \"$WT/.claude/briefs/unit-a-evidence.md\"}")"
check "main reading its own checkout passes" 0 "$(hook "$TMP/main" Read "{\"file_path\": \"$TMP/main/README.md\"}")"
check "a worker reading its own worktree passes" 0 "$(hook "$WT" Read "{\"file_path\": \"$WT/src/a.sh\"}")"
# The briefs exception holds only for a path that stays there once resolved: each way of writing a path that
# names the worker's code is refused.
mkdir -p "$WT/src" "$WT/.claude/briefs"; ln -s "$WT/src" "$WT/.claude/briefs/code"
check "a briefs path climbing out with .. is refused" 2 "$(hook "$TMP/main" Read "{\"file_path\": \"$WT/.claude/briefs/../../src/a.sh\"}")"
check "a link in the briefs folder to the code is refused" 2 "$(hook "$TMP/main" Read "{\"file_path\": \"$WT/.claude/briefs/code/a.sh\"}")"
check "a Glob in the briefs folder passes" 0 "$(hook "$TMP/main" Glob "{\"pattern\": \"*-r*-reports.md\", \"path\": \"$WT/.claude/briefs\"}")"
check "a Glob from the briefs folder whose pattern climbs out is refused" 2 "$(hook "$TMP/main" Glob "{\"pattern\": \"../../src/*.sh\", \"path\": \"$WT/.claude/briefs\"}")"
check "a path that climbs into a workspaces folder is refused" 2 "$(hook "$TMP/main" Read "{\"file_path\": \"$TMP/orca/workspace/../workspaces/proj/unit-a/src/a.sh\"}")"
check "a path in other letter case is refused, as a Mac's disk takes it" 2 "$(hook "$TMP/main" Read "{\"file_path\": \"$TMP/Orca/Workspaces/proj/unit-a/src/a.sh\"}")"
check "a Grep whose regex reads like a worktree path searches main's own code" 0 "$(hook "$TMP/main" Grep "{\"pattern\": \"orca/workspaces/x\", \"path\": \"$TMP/main\"}")"
check "a reviewer pane passes" 0 "$(jq -cn --arg cwd "$TMP/main" --arg f "$WT/src/a.sh" '{cwd: $cwd, tool_name: "Read", tool_input: {file_path: $f}}' \
  | COMMANDECK_REVIEWER=1 bash "$HOOK" 2>/dev/null; echo $?)"

J=$REAL/hooks/hooks.json
check "the guard is wired on Read, Grep and Glob" 1 "$(jq '[.hooks.PreToolUse[] | select(.matcher == "Read|Grep|Glob") | .hooks[].command | select(contains("main-worktree-read-guard.sh"))] | length' "$J")"
check "no symbols-before-read hook is wired" 0 "$(jq '[.. | strings | select(contains("symbols-before-read"))] | length' "$J")"
check "and none ships" 0 "$(ls "$REAL"/hooks/*symbols-before-read* 2>/dev/null | wc -l | tr -d ' ')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
