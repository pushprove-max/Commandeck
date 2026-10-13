#!/usr/bin/env bash
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
git() { printf '.git\n'; }
export -f git
payload=$(jq -cn --arg cmd $'cat <<\'END\'-NOTES\nEND\nwhile true\ndo\n bash scripts/orca-wait.sh\ndone\nEND-NOTES' '{tool_name:"Bash",tool_input:{command:$cmd,run_in_background:true}}')
rc=0
printf '%s\n' "$payload" | bash "$ROOT/hooks/no-poll-loops.sh" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: literal heredoc refused ($rc)"; exit 1; }
echo '1 passed, 0 failed'
