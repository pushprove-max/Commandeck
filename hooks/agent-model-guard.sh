#!/usr/bin/env bash
# PreToolUse hook on Agent|Task: a helper agent runs on the model its call names.
#   - no `model` would inherit main's seat, the costliest one: the call runs as
#     Opus instead, through updatedInput, so it needs no retry turn;
#     a fork alone keeps inheriting
#   - an unnamed Explore call runs as Haiku (owner ruling 2026-10-08);
#     an unnamed general-purpose, debugger or commandeck:helper call runs as Sonnet
#   - a named model runs as named, Sonnet and Haiku included, for any job
#     (owner rulings 2026-10-07): this hook
#     never refuses a call
#   - except in a Builder pane (COMMANDECK_BUILDER=1): every Explore runs
#     as Haiku there, a named model included
# Self-test: bash hooks/__tests__/agent-model-guard.test.sh
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# The matcher is a regex; TaskCreate, TaskList and the rest are not agents.
case "$(jq -r '.tool_name // empty' <<<"$INPUT")" in Agent|Task) ;; *) exit 0 ;; esac
jq -c --arg b "${COMMANDECK_BUILDER:-}" 'select(.tool_input.subagent_type != "fork")
  | ($b == "1" and .tool_input.subagent_type == "Explore" and (.tool_input.model // "") != "haiku") as $builder
  | select($builder or (.tool_input.model // "") == "")
  | (if $builder then "haiku"
     else {Explore: "haiku", "general-purpose": "sonnet", debugger: "sonnet", "commandeck:helper": "sonnet"}[.tool_input.subagent_type // ""] // "opus" end) as $m
  | {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow",
       permissionDecisionReason: (if $builder then "Builder pane: every Explore runs as haiku (agent-model-guard.sh)"
                                  else "no model named: runs as \($m) (agent-model-guard.sh)" end),
       updatedInput: (.tool_input + {model: $m})}}' <<<"$INPUT"
exit 0
