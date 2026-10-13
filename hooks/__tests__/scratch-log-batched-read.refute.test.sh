#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/logs"
printf 'verification evidence\n' > "$TMP/evidence.md"
printf 'tests passed\n' > "$TMP/logs/run.log"

command="cat '$TMP/evidence.md'; tail -n 20 '$TMP/logs/run.log'"
payload="$(jq -cn --arg cwd "$TMP" --arg command "$command" \
  '{cwd:$cwd,session_id:"w7-batched-read-refute",
    tool_input:{command:$command}}')"
rc=0
printf '%s\n' "$payload" |
  COMMANDECK_SCRATCH="$TMP/logs" bash "$ROOT/hooks/bash-symbols-before-read.sh" \
  >"$TMP/output" 2>&1 || rc=$?

if [ "$rc" -ne 0 ]; then
  printf 'FAIL: evidence read plus bounded log tail must pass; got %s\n' "$rc"
  exit 1
fi
echo "scratch-log-batched-read: 1 passed, 0 failed"
