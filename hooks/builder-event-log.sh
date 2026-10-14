#!/usr/bin/env bash
# Builder event log: one JSON line per subagent start and stop and per
# Codex pass start and end, appended to <worktree>/.claude/builder-events.jsonl
# (gitignored). Registered only in a Builder worktree's settings.local.json by
# worktree-setup.sh --builder. Findings and convergence live in the round files,
# not here. Never blocks a tool call.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
ROOT=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
[ -n "$ROOT" ] || exit 0
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# A Bash command that runs tests or a build (kind "test": the longest STUCK limit). Source: package.json scripts, with-suite-lock.sh.
# A self-test run by hand, or any command under its own `timeout N`, is one too: the 180 s shell limit flagged a healthy run.
TEST_RE='(^|[ /;&|])(npm (run )?(test|build|lint|typecheck)[a-z:-]*|npx (vitest|tsc|tsx)|node( [^ ]+)* --test|run-shell-tests\.sh|with-suite-lock\.sh|vitest|tsc|timeout( -[^ ]+)*( [0-9.]+[smhd]?)+|(bash|sh|node|python3?)( -[^ ]+)* [^ ]*__tests__/[^ ]+)( |$)'
EV=$(jq -r '"\(.hook_event_name // ""):\(.tool_name // "")"' <<<"$INPUT")
case "$EV" in
  PreToolUse:Agent|PreToolUse:Task)
    # The model the call asked for; agent-model-guard.sh may rewrite it, and the stop line records what ran.
    LINE=$(jq -c --arg ts "$NOW" '{ts: $ts, event: "subagent-request", type: (.tool_input.subagent_type // null),
      model: (.tool_input.model // null), description: (.tool_input.description // null)}' <<<"$INPUT") ;;
  SubagentStart:*)
    LINE=$(jq -c --arg ts "$NOW" '{ts: $ts, event: "subagent-start", agent_id: (.agent_id // null),
      type: (if (.agent_type // "") == "" then null else .agent_type end)}' <<<"$INPUT") ;;
  SubagentStop:*)
    # The Codex rows come from builder-codex-pass.sh: a background Bash call returns before the pass ends.
    T=$(jq -r '.agent_transcript_path // empty' <<<"$INPUT")
    U=null REASON="no agent_transcript_path in the SubagentStop payload"
    if [ -n "$T" ]; then
      REASON="no file at $T"
      if [ -f "$T" ]; then
        U=$(bash "${BASH_SOURCE[0]%/*}/../scripts/seat-event.sh" --usage claude "$T" 2>/dev/null) || U=null
        REASON="no usage in $T"
      fi
    fi
    jq -e 'type == "object"' <<<"$U" >/dev/null 2>&1 || U=null
    LINE=$(jq -c --arg ts "$NOW" --argjson u "$U" --arg r "$REASON" '{ts: $ts, event: "subagent-stop", agent_id: (.agent_id // null),
      type: (if (.agent_type // "") == "" then null else .agent_type end), model: ($u.model // null), tokens: ($u.tokens // null)}
      + (if $u == null then {reason: $r} else {} end)' <<<"$INPUT") ;;
  # Agent and Task legitimately run for minutes and have their own start and stop rows.
  PostToolUse:Agent|PostToolUse:Task|PostToolUseFailure:Agent|PostToolUseFailure:Task) exit 0 ;;
  PreToolUse:*)
    # call is a checksum of the tool and its input: a repeated call is visible, no command text is stored.
    CK=$(jq -c '[.tool_name, .tool_input]' <<<"$INPUT" | cksum | cut -d' ' -f1)
    # agent: the helper whose call this is, null for the pane's own. A stopped helper's open calls are over.
    LINE=$(jq -c --arg ts "$NOW" --arg re "$TEST_RE" --arg ck "$CK" '{ts: $ts, event: "tool-start", use: (.tool_use_id // null), agent: (.agent_id // null), tool: .tool_name,
      kind: (if .tool_name != "Bash" then "tool" else (.tool_input.command // "") as $c
        | if ($c | test("builder-codex-pass\\.sh")) then "codex" elif ($c | test($re)) then "test"
          # An inbox wait blocks for its whole timeout (540 s) by design: its own kind and limit.
          elif ($c | test("orchestration check\\b[^;&|]*--wait")) then "wait" else "shell" end end), call: $ck,
      # The timeout a Bash call carries (ms in the tool input): the STUCK rule does not fire inside it.
      timeoutSec: (if .tool_name == "Bash" then (.tool_input.timeout | numbers | . / 1000 | floor) // null else null end)}' <<<"$INPUT") ;;
  # A call denied before it runs has a tool-start and no tool-end. Its batch's end names every call
  # of the batch, a blocked one included, for the pane and for a subagent alike (seen on 2.1.296).
  PostToolBatch:*)
    LINE=$(jq -c --arg ts "$NOW" '{ts: $ts, event: "batch-end", uses: [.tool_calls[]?.tool_use_id | strings]}' <<<"$INPUT") ;;
  # The auto-mode classifier's denial has its own event too.
  PermissionDenied:*)
    LINE=$(jq -c --arg ts "$NOW" '{ts: $ts, event: "tool-refused", use: (.tool_use_id // null), hook: "permission-denied"}' <<<"$INPUT") ;;
  # A helper the pane stops gets no SubagentStop and no end for the call it was in (seen on 2.1.296):
  # the TaskStop that worked is its stop row. A stopped shell job's id matches no helper.
  PostToolUse:TaskStop)
    LINE=$(jq -c --arg ts "$NOW" '{ts: $ts, event: "tool-end", use: (.tool_use_id // null), ok: ((.tool_response.is_error? // false) != true)},
      (select((.tool_response.is_error? // false) != true)
        | {ts: $ts, event: "subagent-stop", agent_id: (.tool_input.task_id // .tool_input.shell_id // null), type: null, model: null, tokens: null, reason: "stopped by the pane"})' <<<"$INPUT") ;;
  PostToolUse:*|PostToolUseFailure:*)
    LINE=$(jq -c --arg ts "$NOW" '{ts: $ts, event: "tool-end", use: (.tool_use_id // null),
      ok: ((.hook_event_name != "PostToolUseFailure") and ((.tool_response.is_error? // false) != true))}' <<<"$INPUT") ;;
  *) exit 0 ;;
esac
mkdir -p "$ROOT/.claude" && printf '%s\n' "$LINE" >> "$ROOT/.claude/builder-events.jsonl"
exit 0
