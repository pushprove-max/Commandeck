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
#   - commandeck:lean-worker and commandeck:lean-checker name no model or
#     effort of their own: a missing one comes from routing's roles.lean-worker
#     and roles.lean-checker (the file pp_routing names), sonnet and none when
#     that file cannot be read
#   - a general-purpose or untyped call whose description names no MCP tool or
#     skill is pointed at the lean agents (additionalContext), never refused
# Self-test: bash hooks/__tests__/agent-model-guard.test.sh
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# The matcher is a regex; TaskCreate, TaskList and the rest are not agents.
case "$(jq -r '.tool_name // empty' <<<"$INPUT")" in Agent|Task) ;; *) exit 0 ;; esac
# The routing file is read only for a lean agent, by the one variable pp_routing reads: no paths.sh per Agent call.
LEAN='{}'
case $(jq -r '.tool_input.subagent_type // empty' <<<"$INPUT") in
  commandeck:lean-worker|commandeck:lean-checker)
    LEAN=$(jq -c --arg r "$(jq -r '.tool_input.subagent_type | ltrimstr("commandeck:")' <<<"$INPUT")" \
      '.roles[$r] // {} | {model, effort} | with_entries(select(.value | type == "string"))' \
      "${COMMANDECK_ROUTING:-${BASH_SOURCE[0]%/*}/../config/routing.json}" 2>/dev/null) || LEAN='{}' ;;
esac
jq -c --arg b "${COMMANDECK_BUILDER:-}" --argjson lean "$LEAN" 'select(.tool_input.subagent_type != "fork")
  | .tool_input as $in | ($in.subagent_type // "") as $t
  | ($b == "1" and $t == "Explore" and ($in.model // "") != "haiku") as $builder
  | (if $builder then "haiku" elif ($in.model // "") != "" then null
     else $lean.model // ({Explore: "haiku", "general-purpose": "sonnet", debugger: "sonnet", "commandeck:helper": "sonnet",
       "commandeck:lean-worker": "sonnet", "commandeck:lean-checker": "sonnet"}[$t] // "opus") end) as $m
  | (if ($in.effort // "") == "" then $lean.effort else null end) as $e
  | (($t == "general-purpose" or $t == "") and (($in.description // "") | test("mcp__|\\bmcps?\\b|\\bskills?\\b"; "i") | not)) as $nudge
  | select($m != null or $e != null or $nudge)
  | {hookSpecificOutput: ({hookEventName: "PreToolUse"}
      + (if $m == null and $e == null then {} else {permissionDecision: "allow",
           permissionDecisionReason: (if $builder then "Builder pane: every Explore runs as haiku (agent-model-guard.sh)"
             elif $m != null then "no model named: runs as \($m)\(if $e then " at \($e) effort, from routing" else "" end) (agent-model-guard.sh)"
             else "no effort named: runs at \($e) effort, from routing (agent-model-guard.sh)" end),
           updatedInput: ($in + (if $m then {model: $m} else {} end) + (if $e then {effort: $e} else {} end))} end)
      + (if $nudge then {additionalContext: "Unless this task needs an MCP tool or a skill, use commandeck:lean-worker (edits, runs, tests) or commandeck:lean-checker (a blind read-only check): they start without CLAUDE.md, MCP servers or skills (agent-model-guard.sh)."} else {} end))}' <<<"$INPUT"
exit 0
