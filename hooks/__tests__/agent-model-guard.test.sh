#!/usr/bin/env bash
# Self-test for agent-model-guard.sh. Run: bash hooks/__tests__/agent-model-guard.test.sh
#
# A helper agent with no model would inherit main's seat (Opus, 1M); the hook
# names Opus for it instead of refusing, so the call runs on its first attempt
# with no retry turn. A named model runs as named: Haiku is allowed
# (owner ruling 2026-10-07) and neither Sonnet nor Haiku carries a
# job limit (owner, 2026-10-07), so the hook never refuses a call.
set -u
# Run inside a Builder pane, the variable would turn the named-model cases below.
unset COMMANDECK_BUILDER
HOOK="$(cd "$(dirname "$0")/.." && pwd)/agent-model-guard.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
run() { jq -cn --argjson i "$1" '{tool_name:"Agent", tool_input:$i}' | bash "$HOOK" >/dev/null 2>&1; echo $?; }

NOMODEL='{"subagent_type":"general-purpose","description":"find callers","prompt":"list callers","run_in_background":true}'
check "no model is not refused (no retry turn)"     0 "$(run "$NOMODEL")"
OUT=$(jq -cn --argjson i "$NOMODEL" '{tool_name:"Agent", tool_input:$i}' | bash "$HOOK" 2>/dev/null)
check "unnamed general-purpose runs as Sonnet, every other argument kept" 1 \
  "$(jq -e --argjson i "$NOMODEL" '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.updatedInput == ($i + {model: "sonnet"})' <<<"$OUT" >/dev/null 2>&1 && echo 1 || echo 0)"
check "a named model is passed through untouched (no rewrite)" "" \
  "$(jq -cn '{tool_name:"Agent", tool_input:{model:"opus",description:"x",prompt:"y"}}' | bash "$HOOK" 2>/dev/null)"
check "a named sonnet model is not rewritten to Opus" "" \
  "$(jq -cn '{tool_name:"Agent", tool_input:{model:"claude-sonnet-5-5",description:"Review the diff",prompt:"y"}}' | bash "$HOOK" 2>/dev/null)"
check "a fork keeps inheriting (no rewrite)" "" \
  "$(jq -cn '{tool_name:"Agent", tool_input:{subagent_type:"fork",description:"x",prompt:"y"}}' | bash "$HOOK" 2>/dev/null)"
check "no model on a fork passes"                   0 "$(run '{"subagent_type":"fork","description":"x","prompt":"y"}')"
check "haiku passes"                                0 "$(run '{"model":"haiku","description":"find callers","prompt":"list callers"}')"
check "a haiku model id passes"                     0 "$(run '{"model":"claude-haiku-5-5","description":"x","prompt":"y"}')"
check "haiku on a fork passes"                      0 "$(run '{"subagent_type":"fork","model":"haiku","description":"x","prompt":"y"}')"
check "haiku as implementer passes"                 0 "$(run '{"model":"haiku","subagent_type":"implementer","description":"x","prompt":"y"}')"
check "sonnet as debugger passes"                   0 "$(run '{"model":"sonnet","subagent_type":"debugger","description":"x","prompt":"y"}')"
check "sonnet asked to review and validate passes"  0 "$(run '{"model":"sonnet","description":"Review the diff","prompt":"Validate the fix holds, then debug it."}')"
check "opus for review passes"                      0 "$(run '{"model":"opus","subagent_type":"debugger","description":"Review","prompt":"debug it"}')"
check "the legacy Task tool name gets the Opus default too (no subagent_type)" 1 \
  "$(jq -cn '{tool_name:"Task", tool_input:{description:"x",prompt:"y"}}' | bash "$HOOK" 2>/dev/null | jq -e '.hookSpecificOutput.updatedInput.model == "opus"' >/dev/null 2>&1 && echo 1 || echo 0)"
check "TaskCreate is not an agent call"             0 "$(jq -cn '{tool_name:"TaskCreate", tool_input:{subject:"x",description:"review it"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
check "TaskCreate is never rewritten"               "" "$(jq -cn '{tool_name:"TaskCreate", tool_input:{subject:"x",description:"y"}}' | bash "$HOOK" 2>/dev/null)"

# An unnamed Explore call runs as Haiku (owner ruling 2026-10-08); the
# match is exact, as Claude Code spells the type, and a named model still wins.
EXPLORE='{"subagent_type":"Explore","description":"find callers","prompt":"list callers","run_in_background":true}'
rewritten() { jq -cn --arg t "$1" --argjson i "$2" '{tool_name:$t, tool_input:$i}' | bash "$HOOK" 2>/dev/null \
  | jq -e --argjson i "$2" --arg m "$3" '.hookSpecificOutput.updatedInput == ($i + {model: $m}) and (.hookSpecificOutput.permissionDecisionReason | ascii_downcase | contains($m))' >/dev/null 2>&1 && echo 1 || echo 0; }
check "unnamed Explore is not refused"              0 "$(run "$EXPLORE")"
check "unnamed Explore runs as Haiku, every other argument kept, reason names it" 1 "$(rewritten Agent "$EXPLORE" haiku)"
check "the legacy Task tool name runs an unnamed Explore as Haiku too" 1 "$(rewritten Task "$EXPLORE" haiku)"
check "Explore naming opus is not rewritten"        "" "$(jq -cn --argjson i "$EXPLORE" '{tool_name:"Agent", tool_input:($i + {model:"opus"})}' | bash "$HOOK" 2>/dev/null)"
check "Explore naming sonnet is not rewritten"      "" "$(jq -cn --argjson i "$EXPLORE" '{tool_name:"Agent", tool_input:($i + {model:"sonnet"})}' | bash "$HOOK" 2>/dev/null)"
# Unnamed general-purpose and debugger calls run as Sonnet 5.5; a named model still wins.
DEBUGGER='{"subagent_type":"debugger","description":"find the cause","prompt":"trace it"}'
check "unnamed debugger runs as Sonnet, reason names it" 1 "$(rewritten Agent "$DEBUGGER" sonnet)"
check "the legacy Task tool name runs an unnamed general-purpose as Sonnet too" 1 "$(rewritten Task "$NOMODEL" sonnet)"
check "general-purpose naming opus is not rewritten" "" "$(jq -cn --argjson i "$NOMODEL" '{tool_name:"Agent", tool_input:($i + {model:"opus"})}' | bash "$HOOK" 2>/dev/null)"
check "debugger naming opus is not rewritten"       "" "$(jq -cn --argjson i "$DEBUGGER" '{tool_name:"Agent", tool_input:($i + {model:"opus"})}' | bash "$HOOK" 2>/dev/null)"
check "an unnamed implementer still runs as Opus"   1 "$(rewritten Agent '{"subagent_type":"implementer","description":"x","prompt":"y"}' opus)"
check "lower-case explore still runs as Opus (exact match)" 1 "$(rewritten Agent '{"subagent_type":"explore","description":"x","prompt":"y"}' opus)"
check "no subagent_type still runs as Opus"         1 "$(rewritten Agent '{"description":"x","prompt":"y"}' opus)"

# A Builder pane (COMMANDECK_BUILDER=1) is one Opus seat that runs its own
# code searches: every Explore runs as Haiku there, a named model included, or
# one habit of naming opus multiplies the batch's cost. The named-model rule
# above still holds everywhere else, and for every other agent type.
builder() { jq -cn --argjson i "$1" '{tool_name:"Agent", tool_input:$i}' | COMMANDECK_BUILDER=1 bash "$HOOK" 2>/dev/null; }
as_haiku() { builder "$1" | jq -e --argjson i "$1" '.hookSpecificOutput.updatedInput == ($i + {model: "haiku"})' >/dev/null 2>&1 && echo 1 || echo 0; }
check "Builder: Explore naming opus runs as Haiku, every other argument kept" 1 "$(as_haiku "$(jq -c '. + {model:"opus"}' <<<"$EXPLORE")")"
check "Builder: Explore naming sonnet runs as Haiku" 1 "$(as_haiku "$(jq -c '. + {model:"sonnet"}' <<<"$EXPLORE")")"
check "Builder: unnamed Explore runs as Haiku" 1 "$(as_haiku "$EXPLORE")"
check "Builder: Explore naming haiku is left alone" "" "$(builder "$(jq -c '. + {model:"haiku"}' <<<"$EXPLORE")")"
check "Builder: general-purpose naming opus is not rewritten" "" "$(builder "$(jq -c '. + {model:"opus"}' <<<"$NOMODEL")")"
check "Builder: a fork naming opus is not rewritten" "" "$(builder '{"subagent_type":"fork","model":"opus","description":"x","prompt":"y"}')"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
