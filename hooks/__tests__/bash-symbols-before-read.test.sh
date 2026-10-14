#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1
# Self-test for bash-symbols-before-read.sh, the shell twin of the Read gate.
# Run: bash hooks/__tests__/bash-symbols-before-read.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/bash-symbols-before-read.sh"
PASS=0; FAIL=0
SID="bashsymtest-$$"
SERENA_TRACKER="/tmp/claude-serena-tracker-${SID}"
SERENA_DOWN="/tmp/claude-serena-down-${SID}"
# Physical path: macOS mktemp answers /var/..., git rev-parse /private/var/...
TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMP" "$SERENA_TRACKER" "$SERENA_DOWN"' EXIT

git -C "$TMP" init -q
mkdir -p "$TMP/infra/lib" "$TMP/home" "$TMP/src/routes" "$TMP/src/__tests__" "$TMP/scripts/__tests__" "$TMP/ml/__tests__" "$TMP/scratch/logs"
printf 'export function alphaThing() {}\nexport const GAMMA_LIMIT = 3;\n' > "$TMP/src/routes/thing.ts"
touch "$TMP/src/routes/other.ts" "$TMP/src/__tests__/thing.test.ts" \
  "$TMP/scripts/tool.ts" "$TMP/scripts/__tests__/tool.test.ts" \
  "$TMP/ml/model.py" "$TMP/ml/__tests__/model_test.py" "$TMP/scratch/logs/run.log" "$TMP/infra/lib/stack.ts"
export COMMANDECK_SCRATCH="$TMP/scratch/logs"
# The gate reads ~/.claude.json to learn whether serena is on for this checkout.
export HOME="$TMP/home"
printf '{"mcpServers":{"serena":{}}}\n' > "$HOME/.claude.json"

run_keep() { printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' "$SID" "$TMP" "$(printf '%s' "$1" | jq -Rs .)" | bash "$GATE" >/dev/null 2>&1; echo $?; }
# A refusal now clears its directory (the retry passes), so the cases below that
# ask "does this file block?" over and over would clear each other. `run` puts
# the tracker back after each call; `run_keep` is the one-turn-retry cases.
run() { local rc; cp "$SERENA_TRACKER" "$TMP/tracker.snap" 2>/dev/null; rc=$(run_keep "$1"); if [ -e "$TMP/tracker.snap" ]; then mv "$TMP/tracker.snap" "$SERENA_TRACKER"; else rm -f "$SERENA_TRACKER"; fi; echo "$rc"; }
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 (expected exit $2, got $3)"; fi; }

echo "bash-symbols-before-read.sh"
check "sed -n on a runtime .ts with no serena lookup is blocked" 2 "$(run "sed -n '1,80p' src/routes/thing.ts")"
check "a second read with no serena call still blocks"         2 "$(run "cat src/routes/thing.ts")"
check "serena silent all session: the next file blocks too"     2 "$(run "cat src/routes/other.ts")"
touch "$SERENA_DOWN"
check "a serena call errored this session: the gate stands down" 0 "$(run "cat src/routes/other.ts")"
rm -f "$SERENA_DOWN"
printf 'src/routes/other.ts\n' > "$SERENA_TRACKER"
check "a file serena answered for passes"                       0 "$(run "head -50 src/routes/other.ts")"
check "a file serena has not answered for blocks (serena alive)" 2 "$(run "tail -n 40 infra/lib/stack.ts")"
check "a test file is never blocked"                            0 "$(run "cat src/__tests__/thing.test.ts")"
check "grep is not a read"                                      0 "$(run "grep -n foo src/routes/thing.ts")"
check "a command with no .ts file passes"                       0 "$(run "cat package.json")"

# One-turn recovery: a refusal records the directory as cleared, so the retry passes.
rm -f "$SERENA_TRACKER"
check "a read of an unread file is refused"                     2 "$(run_keep "cat src/routes/thing.ts")"
check "the immediate retry passes"                              0 "$(run_keep "cat src/routes/thing.ts")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
