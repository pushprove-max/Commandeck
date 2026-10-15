#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1
# Self-test for symbols-before-read.sh and the references recording in
# read-tracker.sh. Run: bash hooks/__tests__/symbols-before-read.test.sh
#
# Pinned: reads are never gated (owner ruling 2026-10-14: agents worked around
# nearly every read block); in a worker pane the first edit to an existing
# runtime file is refused once, and a references lookup for it lets it through.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/symbols-before-read.sh"
TRACKER="$ROOT/hooks/read-tracker.sh"
PASS=0; FAIL=0
SID="symtest-$$"
SERENA_TRACKER="/tmp/claude-serena-tracker-${SID}"
SERENA_DOWN="/tmp/claude-serena-down-${SID}"
# Physical path: macOS mktemp answers /var/..., git rev-parse /private/var/...
TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMP" "$SERENA_TRACKER" "$SERENA_DOWN" "/tmp/claude-mcp-used-$SID"' EXIT

git -C "$TMP" init -q -b main
mkdir -p "$TMP/src/routes" "$TMP/src/queue"
printf 'export function alphaThing() {}\n' > "$TMP/src/routes/thing.ts"
printf 'export const queue = 1;\n' > "$TMP/src/queue/index.ts"
git -C "$TMP" add -A && git -C "$TMP" -c user.name=t -c user.email=t@example.invalid commit -qm base
git -C "$TMP" worktree add -q "$TMP/wt" -b unit
WT="$TMP/wt"
# The gate reads ~/.claude.json to learn whether serena is on for this checkout.
export HOME="$TMP/home"; mkdir -p "$HOME"
printf '{"mcpServers":{"serena":{}}}\n' > "$HOME/.claude.json"

payload() { printf '{"session_id":"%s","cwd":"%s","tool_name":"%s","tool_input":%s}' "$SID" "$WT" "$1" "$2"; }

check() { # name expected_exit actual_exit
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"
  else FAIL=$((FAIL+1)); echo "  FAIL $1 (expected exit $2, got $3)"; fi
}

run_gate() { payload "$1" "{\"file_path\":\"$2\"}" | (cd "$WT" && bash "$GATE" >/dev/null 2>&1); echo $?; }

echo "symbols-before-read.sh"
check "a Read of runtime code with no serena lookup passes"   0 "$(run_gate Read "$WT/src/routes/thing.ts")"
check "the first edit to an existing runtime file is refused" 2 "$(run_gate Edit "$WT/src/routes/thing.ts")"
check "the retry of that edit passes"                         0 "$(run_gate Edit "$WT/src/routes/thing.ts")"
payload mcp__serena__find_referencing_symbols '{"relative_path":"src/queue/index.ts","name_path":"queue"}' \
  | (cd "$WT" && bash "$TRACKER" >/dev/null 2>&1)
check "an edit after a references lookup for the file passes" 0 "$(run_gate Edit "$WT/src/queue/index.ts")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
