#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1
# Self-test for read-tracker.sh's shell-search nudge: a worker that searches
# source with the shell and never asks serena is nudged, and main told, once.
# Run: bash hooks/__tests__/read-tracker-bash.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TRACKER_HOOK="$ROOT/hooks/read-tracker.sh"
PASS=0; FAIL=0
SID="rtbash-$$"
LOG="/tmp/claude-read-tracker-${SID}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP" "$LOG"' EXIT

# A worker that searches the code with the shell and never once asks serena or
# codebase-memory is flying blind (cut 1, 2026-09-18: 245 rg, 0 MCP calls).
# At the threshold the worker is nudged and main told, once; any MCP call
# first means no nudge; the main checkout is exempt.
N=$(sed -n 's/^MCP_UNUSED_AFTER=\([0-9]*\).*/\1/p' "$TRACKER_HOOK")
check_eq() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 (expected $2, got $3)"; fi; }
check_eq "the threshold is one named value of 25" 25 "$N"
N=${N:-25}
git init -q "$TMP/m" && git -C "$TMP/m" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && git -C "$TMP/m" worktree add -q "$TMP/unit-x" >/dev/null 2>&1
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$ORCA_LOG"\n' > "$TMP/bin/orca-ide"; chmod +x "$TMP/bin/orca-ide"
export ORCA_LOG="$TMP/orca.log"
# The escalation needs the dispatch capability from the pane's preamble, which
# lives in the session transcript as JSON-escaped text.
TRANSCRIPT="$TMP/transcript.jsonl"
jq -cn '{type:"user", message:{content:"  orca orchestration send --from term_T1 --dispatch-capability dcap_T-1_x --type escalation --subject \"Blocked: <reason>\" --body \"<details>\" --task-id task_T1 --dispatch-id ctx_T1"}}' > "$TRANSCRIPT"
search() { # sid dir [command] [transcript] -> rc
  jq -cn --arg sid "$1" --arg cwd "$2" --arg c "${3:-rg -n foo src/services}" --arg tp "${4-$TRANSCRIPT}" \
    '{session_id:$sid, tool_name:"Bash", cwd:$cwd, transcript_path:$tp, tool_input:{command:$c}}' \
    | CLAUDE_PROJECT_DIR="$2" PATH="$TMP/bin:$PATH" bash "$TRACKER_HOOK" >/dev/null 2>&1; echo $?
}
mcp() { jq -cn --arg sid "$1" '{session_id:$sid, tool_name:"mcp__codebase-memory__search_graph", tool_input:{name_pattern:"x"}}' \
    | CLAUDE_PROJECT_DIR="$2" PATH="$TMP/bin:$PATH" bash "$TRACKER_HOOK" >/dev/null 2>&1; }
MS="mcpuse-$$"; rm -f /tmp/claude-mcp-*"$MS"*; : > "$ORCA_LOG"
for i in $(seq 1 $((N - 1))); do R=$(search "${MS}a" "$TMP/unit-x"); [ "$R" = 0 ] || break; done
check_eq "searches under the threshold pass silently" 0 "$R"
check_eq "the threshold search nudges the worker" 2 "$(search "${MS}a" "$TMP/unit-x")"
check_eq "and tells main once" 1 "$(grep -c -- '--type escalation' "$ORCA_LOG")"
check_eq "with the preamble's capability, task and dispatch" 1 \
  "$(grep -c -- '^orchestration send --from term_T1 --dispatch-capability dcap_T-1_x .*--task-id task_T1 --dispatch-id ctx_T1' "$ORCA_LOG")"
check_eq "the next search passes" 0 "$(search "${MS}a" "$TMP/unit-x")"
check_eq "and main is not told twice" 1 "$(wc -l < "$ORCA_LOG")"
: > "$ORCA_LOG"; mcp "${MS}b" "$TMP/unit-x"
for i in $(seq 1 $N); do R=$(search "${MS}b" "$TMP/unit-x"); [ "$R" = 0 ] || break; done
check_eq "one MCP call first means no nudge" 0 "$R"
check_eq "and no message" 0 "$(wc -l < "$ORCA_LOG")"
# Only source searches count: a builder editing shell hooks has nothing for
# serena to answer, and the nudge fired on one on 2026-09-18.
: > "$ORCA_LOG"
for i in $(seq 1 $N); do R=$(search "${MS}d" "$TMP/unit-x" "rg -n foo .claude/hooks"); [ "$R" = 0 ] || break; done
check_eq "25 searches over .claude/hooks do not trip" 0 "$R"
for i in $(seq 1 $N); do R=$(search "${MS}e" "$TMP/unit-x" "grep -n x .claude/scripts/seat.sh"); [ "$R" = 0 ] || break; done
check_eq "nor over .claude/scripts" 0 "$R"
for i in $(seq 1 $N); do R=$(search "${MS}h" "$TMP/unit-x" "rg -n 'src/|shared/' .claude/hooks"); [ "$R" = 0 ] || break; done
check_eq "a search PATTERN that names src/ is not a source path" 0 "$R"
for i in $(seq 1 $N); do R=$(search "${MS}i" "$TMP/unit-x" "grep -rn -e foo.ts .claude/hooks"); [ "$R" = 0 ] || break; done
check_eq "nor is an -e pattern naming a .ts file" 0 "$R"
for i in $(seq 1 $N); do R=$(search "${MS}j" "$TMP/unit-x" "rg --max-count 1 'src/|shared/' .claude/hooks"); [ "$R" = 0 ] || break; done
check_eq "a valued long option does not shift the pattern onto a path" 0 "$R"
for i in $(seq 1 $((N - 1))); do search "${MS}k" "$TMP/unit-x" "rg --files src" >/dev/null; done
check_eq "rg --files takes no pattern, so its path counts" 2 "$(search "${MS}k" "$TMP/unit-x" "rg --files src")"
for i in $(seq 1 $((N - 1))); do search "${MS}f" "$TMP/unit-x" "grep -n x web/src/app.tsx" >/dev/null; done
check_eq "a .tsx path counts" 2 "$(search "${MS}f" "$TMP/unit-x" "grep -n x web/src/app.tsx")"
: > "$ORCA_LOG"
for i in $(seq 1 $((N - 1))); do search "${MS}g" "$TMP/unit-x" "rg -n foo src/services" "" >/dev/null; done
check_eq "with no capability known the worker is still nudged" 2 "$(search "${MS}g" "$TMP/unit-x" "rg -n foo src/services" "")"
check_eq "and no send is attempted" 0 "$(wc -l < "$ORCA_LOG")"
for i in $(seq 1 $N); do R=$(search "${MS}c" "$TMP/m"); [ "$R" = 0 ] || break; done
check_eq "the main checkout is exempt" 0 "$R"
check_eq "and tells main nothing" 0 "$(wc -l < "$ORCA_LOG")"
check_eq "settings route codebase-memory calls to the tracker" 0 "$(jq -e '[.hooks.PostToolUse[] | select(any(.hooks[]; .command | test("read-tracker")))] | any(.matcher as $m | "mcp__codebase-memory__search_graph" | test("^(" + $m + ")$"))' "$ROOT/hooks/hooks.json" >/dev/null && echo 0 || echo 1)"
rm -f /tmp/claude-mcp-*"$MS"*

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
