#!/usr/bin/env bash
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export COMMANDECK_HOOK_FIRE_LOG="$T/fires.jsonl"
(
  . "$ROOT/hooks/lib/hook-fire-log.sh"
  hook_fire_log_arm '{"session_id":{"session_id":"11111111-2222-4333-8444-555555555555"},"tool_name":{"tool_name":"PrivateToken"},"hook_event_name":"PostToolUse","tool_input":{}}'
)
jq -e '.session_id == "" and .tool == "" and .event == "PostToolUse"' \
  "$COMMANDECK_HOOK_FIRE_LOG"

# Only a TOP-LEVEL string member answers for a field, whatever sits before it.
fire() { ( . "$ROOT/hooks/lib/hook-fire-log.sh"; hook_fire_log_arm "$1" ); }
row() { tail -1 "$COMMANDECK_HOOK_FIRE_LOG" | jq -r '"\(.session_id)|\(.event)|\(.tool)"'; }
U=11111111-2222-4333-8444-555555555555
# A key nested in an EARLIER top-level object never answers; the walk goes on past it.
fire "$(jq -cn --arg u "$U" '{extra:{session_id:$u, tool_name:"Evil", hook_event_name:"Evil"}, hook_event_name:"PreToolUse", session_id:null}')"
[ "$(row)" = "|PreToolUse|" ]
# An array is not a string either.
fire "$(jq -cn --arg u "$U" '{session_id:[$u], tool_name:"Bash"}')"
[ "$(row)" = "||Bash" ]
# Braces, brackets and escaped quotes inside strings do not unbalance the walk.
fire "$(jq -cn --arg u "$U" '{cwd:"/a{b}[c\"d\\", extra:{p:"}]{\"", q:["\\"]}, session_id:$u, hook_event_name:"Stop", tool_name:"mcp__x__y"}')"
[ "$(row)" = "$U|Stop|mcp__x__y" ]
# Bare scalars are stepped over; the members after them are still read.
fire "$(jq -cn --arg u "$U" '{stop_hook_active:true, n:-1.5e3, x:null, session_id:$u}')"
[ "$(row)" = "$U||" ]
