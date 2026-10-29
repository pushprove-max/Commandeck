#!/usr/bin/env bash
# read-tracker.sh's MCP-unused tripwire. A worker that searches source by shell 25 times and never asks serena
# is told to record it as a main-only deferred item; main is sent nothing (message cuts).
set -u
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

git init -q -b main "$T/main" && git -C "$T/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$T/main" worktree add -q "$T/wt" -b work 2>/dev/null
mkdir -p "$T/bin"
# Any call to orca-ide is logged: the tripwire must make none.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/orca.calls"\n[ ! -e "%s/refuse" ] || exit 1\n' "$T" "$T" > "$T/bin/orca-ide"; chmod +x "$T/bin/orca-ide"
# trip <session> <preamble send line> -- the 25th source search of a session; prints the hook's exit code.
trip() {
  printf '%s\n' "$2 --subject x" "  --task-id task_1 --dispatch-id ctx_1 --outcome succeeded" > "$T/$1.jsonl"
  rm -f "/tmp/claude-mcp-unused-told-$1"; yes '' | head -24 > "/tmp/claude-mcp-shell-searches-$1"
  jq -cn --arg s "$1" --arg t "$T/$1.jsonl" '{session_id: $s, transcript_path: $t, tool_name: "Bash", tool_input: {command: "rg foo src/"}}' \
    | (cd "$T/wt" && CLAUDE_PROJECT_DIR=$T/wt COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1 COMMANDECK_SCRATCH="$T/sc" PATH="$T/bin:$PATH" bash "$SOURCE/hooks/read-tracker.sh" >/dev/null 2>&1); echo $?
  rm -f "/tmp/claude-mcp-unused-told-$1" "/tmp/claude-mcp-shell-searches-$1"
}
S=rt-$$
OUT=$(printf '%s\n' "orca orchestration send --from term_w1 --type escalation --subject x" "  --task-id task_1 --dispatch-id ctx_1 --outcome succeeded" > "$T/$S-a.jsonl"
  yes '' | head -24 > "/tmp/claude-mcp-shell-searches-$S-a"
  jq -cn --arg s "$S-a" --arg t "$T/$S-a.jsonl" '{session_id: $s, transcript_path: $t, tool_name: "Bash", tool_input: {command: "rg foo src/"}}' \
    | (cd "$T/wt" && CLAUDE_PROJECT_DIR=$T/wt COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1 COMMANDECK_SCRATCH="$T/sc" PATH="$T/bin:$PATH" bash "$SOURCE/hooks/read-tracker.sh" 2>&1 >/dev/null; echo "rc=$?"))
rm -f "/tmp/claude-mcp-unused-told-$S-a" "/tmp/claude-mcp-shell-searches-$S-a"
# Message cuts: the nudge is for the worker alone; main is sent nothing and no wake line is written.
check "the 25th shell search with no MCP call is refused" 1 "$(grep -c '^rc=2$' <<<"$OUT")"
check "MCP unused warns the worker once, to record it as a main-only deferred item" 1 "$(grep -c 'Record it under `## Main-only (deferred)`' <<<"$OUT")"
check "and sends nothing to main, nor writes a wake line" "0:0" "$(cat "$T/orca.calls" 2>/dev/null | wc -l | tr -d ' '):$(cat "$T/sc/wake-log.jsonl" 2>/dev/null | wc -l | tr -d ' ')"
# Host issue 3147: a session whose gate found the server missing was told so with a note; the tripwire adds nothing.
touch "/tmp/claude-mcp-down-$S-b"
check "no MCP-unused warning in a session whose gate saw the server missing" 0 "$(trip "$S-b" "orca orchestration send --from term_w1 --type escalation")"
rm -f "/tmp/claude-mcp-down-$S-b"
check "the same session without that flag is refused at the 25th search" 2 "$(trip "$S-b" "orca orchestration send --from term_w1 --type escalation")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
