#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
set -eu
HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh"
BOX=$(mktemp -d)
trap 'rm -rf "$BOX"' EXIT
git -C "$BOX" init -q

CMD='WT=/tmp/orca/workspaces/demo-project/unit-$U; env DEBUG=1 orca-ide worktree create --path "$WT"'
PAYLOAD=$(jq -cn --arg cmd "$CMD" '{tool_input:{command:$cmd}}')
rc=0
(cd "$BOX" && printf '%s\n' "$PAYLOAD" | COMMANDECK_REVIEWER=0 "$HOOK" >/dev/null 2>&1) || rc=$?
[ "$rc" -eq 0 ] || { echo "sanctioned alias use blocked: rc=$rc"; exit 1; }
