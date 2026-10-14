#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1
# Self-test for symbols-before-read.sh and the serena recording added to
# read-tracker.sh. Run: bash hooks/__tests__/symbols-before-read.test.sh
#
# Pinned: a runtime file serena has not answered for is refused, the refusal
# clears its directory so the retry passes, and test and markdown files pass.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/symbols-before-read.sh"
TRACKER="$ROOT/hooks/read-tracker.sh"
PASS=0; FAIL=0
SID="symtest-$$"
SERENA_TRACKER="/tmp/claude-serena-tracker-${SID}"
READ_TRACKER="/tmp/claude-read-tracker-${SID}"
SERENA_DOWN="/tmp/claude-serena-down-${SID}"
# Physical path: macOS mktemp answers /var/..., git rev-parse /private/var/...
TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMP" "$SERENA_TRACKER" "$READ_TRACKER" "$SERENA_DOWN"' EXIT

git -C "$TMP" init -q
mkdir -p "$TMP/src/routes" "$TMP/src/queue" "$TMP/src/__tests__" "$TMP/scripts/__tests__" "$TMP/ml/__tests__"
touch "$TMP/src/routes/thing.ts" "$TMP/src/routes/notes.md" \
      "$TMP/src/routes/index.ts" "$TMP/src/queue/index.ts" \
      "$TMP/src/__tests__/thing.test.ts" "$TMP/scripts/tool.ts" "$TMP/scripts/__tests__/tool.test.ts" \
      "$TMP/ml/model.py" "$TMP/ml/__tests__/model_test.py" "$TMP/src/routes/types.d.ts"
printf 'export function alphaThing() {}\nexport interface BetaShape { a: number }\nexport const GAMMA_LIMIT = 3;\nclass DeltaHelper {}\nexport type EpsilonId = string;\n' > "$TMP/src/routes/thing.ts"
# The gate reads ~/.claude.json to learn whether serena is on for this checkout.
export HOME="$TMP/home"; mkdir -p "$HOME"
printf '{"mcpServers":{"serena":{}}}\n' > "$HOME/.claude.json"

payload() { printf '{"session_id":"%s","tool_name":"%s","tool_input":%s}' "$SID" "$1" "$2"; }

check() { # name expected_exit actual_exit
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"
  else FAIL=$((FAIL+1)); echo "  FAIL $1 (expected exit $2, got $3)"; fi
}

run_gate() { payload Read "{\"file_path\":\"$1\"}" | bash "$GATE" >/dev/null 2>&1; echo $?; }
run_gate_input() { payload Read "$1" | bash "$GATE" >/dev/null 2>&1; echo $?; }

echo "symbols-before-read.sh"
check "runtime .ts with no serena lookup is blocked" 2 "$(run_gate "$TMP/src/routes/thing.ts")"
rm -f "$SERENA_TRACKER"
OUT=$(payload Read "{\"file_path\":\"$TMP/src/routes/thing.ts\"}" | bash "$GATE" 2>&1 >/dev/null)
check "the immediate retry passes"                   0 "$(run_gate "$TMP/src/routes/thing.ts")"
check "a neighbour in the same directory passes"     0 "$(run_gate "$TMP/src/routes/index.ts")"
check "a file in another directory still blocks"     2 "$(run_gate "$TMP/src/queue/index.ts")"
check "a markdown file is never blocked"             0 "$(run_gate "$TMP/src/routes/notes.md")"
check "a test file is never blocked"                 0 "$(run_gate "$TMP/src/__tests__/thing.test.ts")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
