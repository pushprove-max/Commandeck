#!/usr/bin/env bash
# Claude PreToolUse gate for worker panes: where the project has serena, the
# first call of a session needs it running; after budget exhaustion a durable
# handoff is required.
# codex: skip -- Codex has no Claude transcript hook; orca-wait emits its budget warning.
set -uo pipefail
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0
IFS=$'\t' read -r TOOL SID < <(printf '%s' "$INPUT" | jq -r '[.tool_name // "", .session_id // ""] | @tsv')
MCP_CHECKED=/tmp/claude-mcp-checked-$SID
case "$TOOL" in Edit|Write|Bash) ;; *) { [ -z "$SID" ] || [ -e "$MCP_CHECKED" ]; } && exit 0 ;; esac
# The budget is a worker pane's; the main checkout (git dir == common dir) is
# the orchestrator's session and runs for thousands of turns by design.
# An inherited GIT_DIR would answer for the wrong repo, so the lookup drops it.
GIT_DIR_OF=$(env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir 2>/dev/null || true)
if [ -n "$GIT_DIR_OF" ] && [ "$GIT_DIR_OF" = "$(env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null)" ]; then exit 0; fi
# The Chief-of-Staff relay pane denies both code servers on purpose and,
# like main, runs long; exact name only (same seat test as agent-startup-context.sh).
TOP=$(env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE git -C "$CLAUDE_PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
[ "${TOP##*/}" = Chief-of-Staff ] && exit 0
UNIT=$(basename "$CLAUDE_PROJECT_DIR")
# A worker with no serena server ran a whole cut on rg and
# sed and nobody knew (2026-09-18). Whatever the cause, the server runs
# somewhere under the session's claude process, so look there until a call passes. The first refusal
# asks for the same call again and the gate looks again; the second tells
# main, and the calls after it pass: main decides.
# under <pid>: is it the claude process or one of its descendants?
under() {
  local p=$1
  for _ in 1 2 3 4 5 6 7 8; do
    [ "$p" = "$CLAUDE_PID" ] && return 0
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [ "${p:-0}" -gt 1 ] 2>/dev/null || return 1
  done
  return 1
}
have() { local pid; for pid in $(pgrep -f "$1"); do under "$pid" && return 0; done; return 1; }
missing() {
  MISSING=""
  have 'serena.*start-mcp-server' || MISSING="serena"
  [ -n "$MISSING" ]
}
if [ -n "$SID" ] && [ ! -e "$MCP_CHECKED" ]; then
  P=$PPID CLAUDE_PID=""
  # ps, not /proc: macOS has no /proc, and its comm is the full executable path.
  for _ in 1 2 3 4 5 6; do
    [ "$P" -gt 1 ] 2>/dev/null || break
    read -r PP COMM < <(ps -o ppid=,comm= -p "$P" 2>/dev/null)
    [ "${COMM##*/}" = claude ] && { CLAUDE_PID=$P; break; }
    P=$PP
  done
  MISSING=""
  if [ -n "$CLAUDE_PID" ] && pp_serena; then
    # A session's server takes a few seconds to start: look for that long before deciding.
    LEFT=${COMMANDECK_MCP_WAIT:-10}
    while missing && [ "$LEFT" -gt 0 ]; do sleep 1; LEFT=$((LEFT - 1)); done
  fi
  if [ -n "$MISSING" ]; then
    WHY="$MISSING is not running in this session (no server process under claude pid $CLAUDE_PID)"
    if [ ! -e "$MCP_CHECKED.again" ]; then
      : > "$MCP_CHECKED.again"
      echo "BLOCKED: $WHY. Make the same call once more: the gate looks again. Do not work around it with rg or sed." >&2
      exit 2
    fi
    : > "$MCP_CHECKED"
    RUN=${COMMANDECK_RUN:-$( { tr -d '[:space:]' < "$(pp_run_file)"; } 2>/dev/null)}
    TOLD="Main could NOT be told (the send failed): send it yourself with orca-ide orchestration send --type escalation, then wait"
    [ -z "$RUN" ] || ! timeout 10 orca-ide orchestration send --run "$RUN" --to "run:$RUN" --type escalation \
      --subject "$UNIT: $MISSING missing from the worker pane" \
      --body "Worker $UNIT (pane ${ORCA_TERMINAL_HANDLE:-unknown}, session $SID) started without $MISSING: no server process under claude pid $CLAUDE_PID." \
      --json >/dev/null 2>&1 || TOLD="Main has been told. Stop and wait"
    echo "BLOCKED: $WHY, on a second look. $TOLD for main's answer. Do not work around it with rg or sed." >&2
    exit 2
  fi
  : > "$MCP_CHECKED"
fi
case "$TOOL" in Edit|Write|Bash) ;; *) exit 0;; esac
LOG=$(printf '%s' "$INPUT" | jq -r '.transcript_path // .transcriptPath // empty'); [ -f "$LOG" ] || exit 0
# shellcheck source=lib/pane-budget.sh
. "$(dirname "$0")/lib/pane-budget.sh"
pane_budget "$LOG" "$CLAUDE_PROJECT_DIR" && exit 0
HANDOFF="$CLAUDE_PROJECT_DIR/.claude/briefs/${UNIT}-handoff.md"
# The handoff the gate demands must itself be writable through the gate.
[ "$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')" = "$HANDOFF" ] && exit 0
if [ ! -f "$HANDOFF" ]; then
  echo "pane budget exceeded ($PB_SUMMARY); write $HANDOFF with headings: decisions, unresolved findings, current commit, test evidence" >&2
  echo "options: simplify the unit; reset the pane from the handoff file; reassign to a fresh pane; escalate to a design pane" >&2
  exit 2
fi
# Every missing heading in one refusal, with the skeleton to paste.
MISSING_HEADINGS=()
for heading in decisions 'unresolved findings' 'current commit' 'test evidence'; do
  grep -qi "^#* *$heading" "$HANDOFF" || MISSING_HEADINGS+=("$heading")
done
if [ ${#MISSING_HEADINGS[@]} -gt 0 ]; then
  echo "handoff $HANDOFF lacks headings: $(IFS=,; echo "${MISSING_HEADINGS[*]}" | sed 's/,/, /g'). Add them all in one edit; the full skeleton:" >&2
  printf '## %s\n' decisions 'unresolved findings' 'current commit' 'test evidence' >&2
  exit 2
fi
