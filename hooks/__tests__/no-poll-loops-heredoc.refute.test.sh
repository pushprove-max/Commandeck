#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BOX=$(mktemp -d)
trap 'rm -rf -- "$BOX"' EXIT
git -C "$BOX" init -q
payload=$(jq -cn --arg cmd $'cat <<\'EOF\'\nwhile true\ndo\n bash scripts/orca-wait.sh\ndone\nEOF' '{tool_name:"Bash",tool_input:{command:$cmd,run_in_background:true}}')
(cd "$BOX" && printf '%s\n' "$payload" | bash "$ROOT/hooks/no-poll-loops.sh")
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: literal heredoc should pass; got $rc"
  exit 1
fi
echo '1 passed, 0 failed'
