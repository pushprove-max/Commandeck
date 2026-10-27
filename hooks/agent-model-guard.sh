#!/usr/bin/env bash
# PreToolUse hook on Agent|Task: a helper agent runs on the model its call names.
#   - no `model` would inherit main's seat, the costliest one: the call runs as
#     Opus instead, through updatedInput, so it needs no retry turn;
#     a fork alone keeps inheriting
#   - an unnamed Explore call runs as Haiku;
#     an unnamed general-purpose or debugger call runs as Sonnet
#     (roles.builder.helpers in config/routing.json holds these models;
#     a routing overlay with no such map runs the shipped one)
#   - a named model runs as named, Sonnet and Haiku included, for any job:
#     this hook never refuses a call
#   - except in a Builder, plan-author or fix-round pane (helper-pane.sh): every
#     call of a type in roles.builder.helpers runs as its model there, a named
#     model included; a call whose named model, in any case or as a full id,
#     holds its type's model or the search (Explore) model keeps it (issue 400)
#   - an untyped call, which would run as Opus, is told to name a type
#     (additionalContext), never refused
#   - a helpers map that cannot be read leaves the call as it is and says so
#     in one systemMessage line
# Self-test: bash hooks/__tests__/agent-model-guard.test.sh
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
. "${BASH_SOURCE[0]%/*}/lib/helper-pane.sh"
# The matcher is a regex; TaskCreate, TaskList and the rest are not agents.
case "$(jq -r '.tool_name // empty' <<<"$INPUT")" in Agent|Task) ;; *) exit 0 ;; esac
# Issue 397: the helper models are routing settings, not constants here.
# An overlay written before helpers existed has no map (setup keeps its builder row as it is): the shipped one applies.
SHIPPED=${BASH_SOURCE[0]%/*}/../config/routing.json
ROUTING=${COMMANDECK_ROUTING:-$SHIPPED}
PANE=0; ! is_helper_pane || PANE=1
if ! OUT=$(jq -c --arg pane "$PANE" --slurpfile r "$ROUTING" --slurpfile d "$SHIPPED" 'select(.tool_input.subagent_type != "fork")
  | ($r[0].roles.builder.helpers // $d[0].roles.builder.helpers
     | if type == "object" and length > 0 then . else error("no helpers map") end) as $h
  | .tool_input as $in | ($in.subagent_type // "") as $t
  | (($in.model // "") | ascii_downcase) as $n
  | ([$h[$t] // empty, $h.Explore // empty] | map(ascii_downcase) | any(. as $f | $n | contains($f))) as $kept
  | ($pane == "1" and ($h | has($t)) and ($kept | not)) as $enforce
  | (if $enforce then $h[$t] elif ($in.model // "") != "" then null else $h[$t] // "opus" end) as $m
  | ($t == "") as $nudge
  | select($m != null or $nudge)
  | {hookSpecificOutput: ({hookEventName: "PreToolUse"}
      + (if $m == null then {} else {permissionDecision: "allow",
           permissionDecisionReason: (if $enforce then "helper pane: every \($t) call runs as \($m) (agent-model-guard.sh)"
             else "no model named: runs as \($m) (agent-model-guard.sh)" end),
           updatedInput: ($in + {model: $m})} end)
      + (if $nudge then {additionalContext: "Name a subagent type: Explore (runs as Haiku) for search and lookup, general-purpose (runs as Sonnet) for judgment, edits or tests (agent-model-guard.sh)."} else {} end))}' <<<"$INPUT" 2>/dev/null); then
  # Issue 397: one line, built without jq; nothing is blocked.
  M="agent-model-guard.sh could not run (the routing file is unreadable or holds no roles.builder.helpers map): this call keeps the model it names"
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$M" "$M"
  exit 0
fi
[ -z "$OUT" ] || printf '%s\n' "$OUT"
exit 0
