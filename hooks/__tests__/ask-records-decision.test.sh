#!/usr/bin/env bash
# A question main puts to the owner must land in the decisions ledger, or the
# owner's open asks vanish from every list that shows them. The hook builds
# each row's id with hooks/lib/decision-id.jq; when that file is missing jq
# fails, the hook records nothing and still exits 0, so only the ledger shows it.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP/main"; mkdir -p "$TMP/main/.claude/metrics" "$TMP/home"
L=$TMP/main/.claude/metrics/decisions.jsonl; : > "$L"
. "$REAL/hooks/lib/ask-decoy.sh"
ask() { # header question -> the hook's exit code
  jq -cn --arg d "$ASK_DECOY" --arg h "$1" --arg q "$2" --arg cwd "$TMP/main" \
    '{cwd: $cwd, tool_name: "AskUserQuestion", tool_input: {questions: [{header: $h, question: $q,
      options: [{label: $d}, {label: "Ship it (Recommended)"}, {label: "Hold"}]}]}}' \
  | env -u CLAUDE_PROJECT_DIR -u COMMANDECK_REVIEWER HOME="$TMP/home" COMMANDECK_MAIN="$TMP/main" \
      COMMANDECK_HOOK_FIRE_LOG="$TMP/fire.jsonl" bash "$REAL/hooks/ask-records-decision.sh" >/dev/null 2>"$TMP/err"; echo $?
}
DAY=$(date +%Y-%m-%d)
check "a first question is let through" 0 "$(ask 'Ship: Now?' 'Ship the release today?')"
check "it is recorded once" 1 "$(wc -l < "$L" | tr -d ' ')"
check "its id is the header slug plus the date" "ship-now-$DAY" "$(jq -r .id "$L")"
check "its default is the recommended option, unmarked" "Ship it" "$(jq -r .proposedDefault "$L")"
check "the same question again is blocked" 2 "$(ask 'Ship: Now?' 'Ship the release today?')"
check "and adds no row" 1 "$(wc -l < "$L" | tr -d ' ')"
check "a question with another header gets its own id" "0 deploy-window-$DAY" \
  "$(ask 'Deploy window' 'Which hour suits the database migration?') $(tail -1 "$L" | jq -r .id)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
