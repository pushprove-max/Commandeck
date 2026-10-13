#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
set -eu
HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh"
BOX=$(mktemp -d)
trap 'rm -rf "$BOX"' EXIT
git -C "$BOX" init -q

CMD="cd $BOX/missing; rg needle ."
PAYLOAD=$(jq -cn --arg cmd "$CMD" '{tool_input:{command:$cmd}}')
rc=0
(cd "$BOX" && printf '%s\n' "$PAYLOAD" | COMMANDECK_REVIEWER=0 "$HOOK" >/dev/null 2>&1) || rc=$?
[ "$rc" -eq 2 ] || { echo "root-wide search passed after failed cd: rc=$rc"; exit 1; }
