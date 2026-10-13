#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1
set -u
ROOT=$(git rev-parse --show-toplevel)
BOX=$(mktemp -d)
SID="created-cd-refute-$(basename "$BOX")"
# The hook keys /tmp trackers on the session id and clears them on its first block.
trap 'rm -rf "$BOX" /tmp/claude-serena-tracker-"$SID" /tmp/claude-serena-down-"$SID"' EXIT
git -C "$BOX" init -q
mkdir -p "$BOX/src/routes" "$BOX/home"
touch "$BOX/src/routes/thing.ts"
printf '{"mcpServers":{"serena":{}}}\n' > "$BOX/home/.claude.json"
payload=$(jq -cn --arg cwd "$BOX" --arg sid "$SID" \
  '{session_id:$sid,cwd:$cwd,tool_name:"Bash",
    tool_input:{command:"mkdir newdir && cd newdir && cat ../src/routes/thing.ts"}}')
rc=0
printf '%s\n' "$payload" | HOME="$BOX/home" \
  bash "$ROOT/hooks/bash-symbols-before-read.sh" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "expected refusal, got $rc"; exit 1; }
