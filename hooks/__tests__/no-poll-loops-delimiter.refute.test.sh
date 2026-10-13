#!/usr/bin/env bash
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BOX=$(mktemp -d)
trap 'rm -rf -- "$BOX"' EXIT
git -C "$BOX" init -q
cmd=$(printf "cat <<'END-NOTES'\nwhile true\ndo\n bash scripts/orca-wait.sh\ndone\nEND-NOTES")
payload=$(jq -cn --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd,run_in_background:true}}')
rc=0
(cd "$BOX" && printf '%s\n' "$payload" | bash "$ROOT/hooks/no-poll-loops.sh") || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: literal heredoc refused ($rc)"; exit 1; }
echo '1 passed, 0 failed'
