#!/usr/bin/env bash
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
git() { printf '.git\n'; }
export -f git
payload=$(jq -cn --arg cmd $'while true # wait for updates\ndo\n bash scripts/orca-wait.sh\ndone' '{tool_name:"Bash",tool_input:{command:$cmd,run_in_background:true}}')
rc=0
printf '%s\n' "$payload" | bash "$ROOT/hooks/no-poll-loops.sh" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: expected 2, got $rc"; exit 1; }
echo '1 passed, 0 failed'
