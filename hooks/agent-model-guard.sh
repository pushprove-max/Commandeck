#!/usr/bin/env bash
# PreToolUse hook on Agent|Task: a helper agent runs on the model its call names.
#   - no `model` would inherit main's seat, the costliest one: the call runs as
#     Opus instead, through updatedInput, so it needs no retry turn;
#     a fork alone keeps inheriting
#   - an unnamed Explore call runs as Haiku;
#     an unnamed general-purpose or debugger call runs as Sonnet
#   - a named model runs as named, Sonnet and Haiku included, for any job:
#     this hook never refuses a call
#   - except in a Builder pane (COMMANDECK_BUILDER=1): every Explore runs
#     as Haiku there, a named model included
#   - an untyped call, which would run as Opus, is told to name a type
#     (additionalContext), never refused
# Self-test: bash hooks/__tests__/agent-model-guard.test.sh
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# The matcher is a regex; TaskCreate, TaskList and the rest are not agents.
case "$(jq -r '.tool_name // empty' <<<"$INPUT")" in Agent|Task) ;; *) exit 0 ;; esac
jq -c --arg b "${COMMANDECK_BUILDER:-}" 'select(.tool_input.subagent_type != "fork")
  | .tool_input as $in | ($in.subagent_type // "") as $t
  | ($b == "1" and $t == "Explore" and ($in.model // "") != "haiku") as $builder
  | (if $builder then "haiku" elif ($in.model // "") != "" then null
     else {Explore: "haiku", "general-purpose": "sonnet", debugger: "sonnet"}[$t] // "opus" end) as $m
  | ($t == "") as $nudge
  | select($m != null or $nudge)
  | {hookSpecificOutput: ({hookEventName: "PreToolUse"}
      + (if $m == null then {} else {permissionDecision: "allow",
           permissionDecisionReason: (if $builder then "Builder pane: every Explore runs as haiku (agent-model-guard.sh)"
             else "no model named: runs as \($m) (agent-model-guard.sh)" end),
           updatedInput: ($in + {model: $m})} end)
      + (if $nudge then {additionalContext: "Name a subagent type: Explore (runs as Haiku) for search and lookup, general-purpose (runs as Sonnet) for judgment, edits or tests (agent-model-guard.sh)."} else {} end))}' <<<"$INPUT"
exit 0
