#!/usr/bin/env bash
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
GUARD=$REAL/hooks/builder-search-guard.sh
TMP=$(mktemp -d)
STREAKS=()
trap 'rm -rf "$TMP"; rm -f "${STREAKS[@]}"' EXIT
PASS=0 FAIL=0 CASE=0

check_case() {
  local expected=$1 initial=$2 command=$3 sid streak got
  CASE=$((CASE+1))
  sid="refute-$(basename "$TMP")-$CASE"
  streak="/tmp/claude-builder-search-streak-$sid"
  STREAKS+=("$streak")
  printf '%s\n' "$initial" > "$streak"
  jq -cn --arg s "$sid" --arg c "$command" \
    '{session_id:$s, hook_event_name:"PreToolUse",
      tool_name:"Bash", tool_input:{command:$c}}' |
    CLAUDE_PROJECT_DIR="$TMP" bash "$GUARD" 2>"$TMP/stderr"
  got=$?
  if [ "$got" = "$expected" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    printf 'FAIL %s: expected %s, got %s\n' "$command" "$expected" "$got"
  fi
}

# Quoting must not change whole-repo or recursive-search classification.
check_case 2 0 'find "." -name y'
check_case 2 0 'find "/" -name y'
check_case 2 0 "find \"$TMP\" -name y"
check_case 2 3 'grep "-rn" x src'
check_case 2 3 '"rg" x src'
check_case 2 3 '"find" . -name y'
check_case 2 3 'git "grep" x'

# Pattern/file operands must not turn a nonrecursive read into a search.
check_case 0 3 'grep -- -r src/file'
check_case 0 3 'grep -e -r src/file'
check_case 0 3 'grep -f -rules src/file'

printf '%s passed / %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
