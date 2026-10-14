#!/usr/bin/env bash
# Self-test for builder-search-guard.sh. Run: bash hooks/__tests__/builder-search-guard.test.sh
#
# Pinned: three searches in a row are small, the fourth goes to Explore, and an
# Edit, Write or Agent call starts the count again -- without that reset a
# Builder would be locked out of searching for the rest of its session. A
# whole-repo search is refused on call 1; a subagent is never counted.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"; rm -f /tmp/claude-builder-search-streak-gs-*' EXIT
GUARD=$REAL/hooks/builder-search-guard.sh
mkdir -p "$TMP/g"
ev() { CLAUDE_PROJECT_DIR=$TMP/g bash "$GUARD" <<<"$(jq -c --arg e "$1" --arg s "$2" '. + {hook_event_name:$e, session_id:$s}' <<<"$3")"; }
sgr() { ev PreToolUse "$1" "$2" 2>"$TMP/gerr"; echo $?; } # sgr <session> <json>: asked only, as when another guard refuses the call; prints the exit code, stderr in $TMP/gerr
sg() { local rc; rc=$(sgr "$1" "$2"); [ "$rc" != 0 ] || ev PostToolUse "$1" "$2"; echo "$rc"; } # a call that ran when let through
tool() { jq -cn --arg t "$1" --argjson i "$2" '{tool_name:$t, tool_input:$i}'; }
bash_() { tool Bash "$(jq -cn --arg c "$1" '{command:$c}')"; }
GREP=$(tool Grep '{"pattern":"x","path":"src"}'); GLOB=$(tool Glob '{"pattern":"*.ts","path":"src"}')
EXPLORE_LINE='This is now a large search (4+ lookups). Hand it to an Explore subagent (Agent, subagent_type Explore).'
rm -f /tmp/claude-builder-search-streak-gs-*
check "searches 1-3 of a streak pass" "0 0 0" "$(echo "$(sg gs-1 "$GREP") $(sg gs-1 "$GLOB") $(sg gs-1 "$(bash_ 'rg x src')")")"
check "the 4th is refused" 2 "$(sg gs-1 "$GREP")"
check "the refusal is one line naming Agent and Explore" "1 $EXPLORE_LINE" "$(wc -l < "$TMP/gerr" | tr -d ' ') $(cat "$TMP/gerr")"
check "an Agent call resets the streak" "0 0" "$(echo "$(sg gs-1 "$(tool Agent '{"subagent_type":"Explore"}')") $(sg gs-1 "$GREP")")"
for t in Edit Write; do
  sg gs-1 "$GREP" >/dev/null; sg gs-1 "$GREP" >/dev/null; sg gs-1 "$GREP" >/dev/null
  check "a $t call resets after a refusal" "2 0 0" "$(echo "$(sg gs-1 "$GREP") $(sg gs-1 "$(tool $t '{"file_path":"a"}')") $(sg gs-1 "$GREP")")"
done
check "a whole-repo Grep and Glob (no path) are refused on call 1" "2 2" "$(echo "$(sg gs-2 "$(tool Grep '{"pattern":"x"}')") $(sg gs-3 "$(tool Glob '{"pattern":"*"}')")")"
check "find . is whole-repo on call 1" 2 "$(sg gs-4 "$(bash_ 'find . -name y')")"
check "find on a directory is a small search" 0 "$(sg gs-5 "$(bash_ 'find src -name y')")"
# A refused or counted Explore subagent would leave the Builder no way to do a large search.
SUB=$(jq -c '. + {agent_id:"a1", agent_type:"Explore"}' <<<"$GREP")
check "four subagent searches all pass, and the main session is still on call 1" "0 0 0 0 0" \
  "$(echo "$(sg gs-6 "$SUB") $(sg gs-6 "$SUB") $(sg gs-6 "$SUB") $(sg gs-6 "$SUB") $(sg gs-6 "$GREP")")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
