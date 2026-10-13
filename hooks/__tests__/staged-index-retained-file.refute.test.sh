#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

git init -q "$FIXTURE/repo"
printf 'export const retained = true;\n' > "$FIXTURE/repo/retained.ts"
git -C "$FIXTURE/repo" add retained.ts
git -C "$FIXTURE/repo" -c core.hooksPath=/dev/null \
  -c user.name=review -c user.email=review@example.invalid commit -qm initial
git -C "$FIXTURE/repo" rm --cached -q retained.ts
mkdir "$FIXTURE/state"

payload=$(jq -cn --arg cwd "$FIXTURE/repo" \
  '{tool_name:"Bash",cwd:$cwd,tool_input:{command:"npm run test:guards"}}')
output=$(TMPDIR="$FIXTURE/state" \
  bash "$ROOT/hooks/staged-index-warn.sh" <<<"$payload" 2>/dev/null)
jq -e '.systemMessage | contains("retained.ts")' <<<"$output" >/dev/null
