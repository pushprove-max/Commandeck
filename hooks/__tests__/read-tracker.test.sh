#!/usr/bin/env bash
# read-tracker.sh's MCP-unused tripwire. A worker that searches source by shell 25 times and never asks serena
# or codebase-memory is told, and main is told by an escalation built from the worker's own dispatch preamble.
# Orca's newer preambles carry no dispatch capability: a send line without one must still reach main, or main
# is never told.
set -u
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

git init -q -b main "$T/main" && git -C "$T/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$T/main" worktree add -q "$T/wt" -b work 2>/dev/null
mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/orca.calls"\n' "$T" > "$T/bin/orca-ide"; chmod +x "$T/bin/orca-ide"
# trip <session> <preamble send line> -- the 25th source search of a session; prints the hook's exit code.
trip() {
  printf '%s\n' "$2 --subject x" "  --task-id task_1 --dispatch-id ctx_1 --outcome succeeded" > "$T/$1.jsonl"
  rm -f "/tmp/claude-mcp-unused-told-$1"; yes '' | head -24 > "/tmp/claude-mcp-shell-searches-$1"
  jq -cn --arg s "$1" --arg t "$T/$1.jsonl" '{session_id: $s, transcript_path: $t, tool_name: "Bash", tool_input: {command: "rg foo src/"}}' \
    | (cd "$T/wt" && CLAUDE_PROJECT_DIR=$T/wt COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1 PATH="$T/bin:$PATH" bash "$SOURCE/hooks/read-tracker.sh" >/dev/null 2>&1); echo $?
  rm -f "/tmp/claude-mcp-unused-told-$1" "/tmp/claude-mcp-shell-searches-$1"
}
S=rt-$$
check "the 25th shell search with no MCP call is refused" 2 "$(trip "$S-a" "orca orchestration send --from term_w1 --type escalation")"
check "and main is told, from a preamble with no dispatch capability" "orchestration send --from term_w1 --type escalation" \
  "$(grep -o 'orchestration send --from term_w1 --type escalation' "$T/orca.calls" 2>/dev/null)"
check "with the dispatch's ids" 1 "$(grep -c -- '--task-id task_1 --dispatch-id ctx_1' "$T/orca.calls" 2>/dev/null)"
rm -f "$T/orca.calls"
trip "$S-b" "orca orchestration send --from term_w2 --dispatch-capability dcap_9 --type escalation" >/dev/null
check "an older preamble's capability is kept" 1 "$(grep -c 'send --from term_w2 --dispatch-capability dcap_9 --type escalation' "$T/orca.calls" 2>/dev/null)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
