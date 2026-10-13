#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
# Self-test for web-fetch-blocker.sh.
#
# The narrowing it pins: the hook refused EVERY WebFetch and told the caller to
# launch a browser instead. An ordinary HTML page fetches fine, so the blanket
# refusal bought a browser launch on every one of them. The failure it exists
# for -- a JS-gated or bot-walled page returning a block page the summary hides
# -- is visible only in the RESULT, so the hook now says what to do then and
# lets the cheap path run first.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/web-fetch-blocker.sh"
PASS=0 FAIL=0

check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
fetch() { jq -cn --arg u "$1" '{tool_name:"WebFetch", tool_input:{url:$u}}'; }
run()   { bash "$HOOK" >/dev/null 2>&1 <<<"$1"; echo $?; }
warns() { bash "$HOOK" 2>&1 >/dev/null <<<"$1"; }

URL='https://example.com/docs'

# --- no blanket refusal -------------------------------------------------------
check "an ordinary fetch is permitted"        0 "$(run "$(fetch "$URL")")"
check "a claude.ai artifact is permitted"     0 \
  "$(run "$(fetch 'https://claude.ai/code/artifact/abc123')")"

# --- the advice survives ------------------------------------------------------
check "the advisory names agent-browser"      0 \
  "$(warns "$(fetch "$URL")" | grep -qF 'agent-browser read' && echo 0 || echo 1)"
check "the advisory carries the URL"          0 \
  "$(warns "$(fetch "$URL")" | grep -qF "$URL" && echo 0 || echo 1)"
check "the advisory says WHEN to reach for it" 0 \
  "$(warns "$(fetch "$URL")" | grep -qiE 'empty|bot wall' && echo 0 || echo 1)"
check "an artifact fetch is SILENT"           "" \
  "$(bash "$HOOK" 2>&1 <<<"$(fetch 'https://claude.ai/code/artifact/abc123')")"

# --- other tools are none of its business -------------------------------------
check "a Bash payload passes"                 0 \
  "$(run "$(jq -cn '{tool_name:"Bash",tool_input:{command:"ls"}}')")"
check "a Bash payload is SILENT"              "" \
  "$(bash "$HOOK" 2>&1 <<<"$(jq -cn '{tool_name:"Bash",tool_input:{command:"ls"}}')")"
check "malformed JSON passes rather than wedging" 0 "$(run 'not json')"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
