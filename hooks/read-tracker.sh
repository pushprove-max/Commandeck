#!/usr/bin/env bash
# PostToolUse hook: nudge a worker that searches source with the shell and
# never asks serena or codebase-memory.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# A FAILED read is not a read. PostToolUse fires either way, and recording a
# refused or errored read tells a gate the agent knows something it never saw.
IS_ERROR=$(echo "$INPUT" | jq -r 'if (.tool_response|type) == "object" then (.tool_response.is_error // (.tool_response.error|if . then true else false end) // false) else false end' 2>/dev/null)
[ "$(echo "$INPUT" | jq -r '.hook_event_name // empty')" = PostToolUseFailure ] && IS_ERROR=true

# A worker that searches with the shell and never asks serena or
# codebase-memory is working blind (cut 1, 2026-09-18: 245 rg, 0 MCP calls).
# Any MCP call, even an errored one, shows the tools are in use. Past this many
# shell searches with none, the worker is nudged and main told, once.
MCP_UNUSED_AFTER=25
MCP_KEY=$(echo "$INPUT" | jq -r '.session_id // empty'); MCP_KEY=${MCP_KEY:-${CLAUDE_SESSION_ID:-${PPID}}}
case "$TOOL_NAME" in mcp__serena__*|mcp__codebase-memory__*) : > "/tmp/claude-mcp-used-$MCP_KEY" ;; esac
[ "${TOOL_NAME#mcp__}" != "$TOOL_NAME" ] && exit 0
# Only a search naming a source root the symbols gate covers, or a .ts/.tsx/.py
# file, counts: a builder editing .claude/hooks has nothing for serena to answer,
# and the nudge fired on one on 2026-09-18.
mcp_unused_tripwire() {
  local N="/tmp/claude-mcp-shell-searches-$MCP_KEY" TOLD="/tmp/claude-mcp-unused-told-$MCP_KEY" DIR GD TP LINE IDS
  [ -e "/tmp/claude-mcp-used-$MCP_KEY" ] || [ -e "$TOLD" ] && return 0
  printf '%s' "$1" | grep -qE '(^|[;&|(])[[:space:]]*(rg|grep|cat|sed[[:space:]]+-n)[[:space:]]' || return 0
  # Path OPERANDS only: a search pattern such as 'src/|shared/' is not a path.
  CMD=$1 python3 - <<'PY' || return 0
import os, re, shlex, sys
SRC = re.compile(r"(^|/)(src|lib|app|scripts)(/|$)|\.(tsx?|py)$")
# Options that take a separate value, per tool: -E is rg's encoding but grep's
# extended-regex switch, -r is rg's replacement but grep's recursion.
LONG = {"--regexp", "--file", "--glob", "--iglob", "--type", "--type-not", "--type-add",
    "--include", "--exclude", "--exclude-dir", "--max-count", "--context", "--after-context",
    "--before-context", "--max-depth", "--max-filesize", "--max-columns", "--sort", "--sortr",
    "--color", "--colors", "--encoding", "--replace", "--threads", "--context-separator"}
VALUED = {"rg": {"-e", "-f", "-g", "-t", "-T", "-m", "-A", "-B", "-C", "-E", "-M", "-r", "-j", "-d"} | LONG,
      "grep": {"-e", "-f", "-m", "-A", "-B", "-C", "-d", "-D"} | LONG,
      "sed": {"-e", "-f"}, "cat": set()}
PATTERN_FLAGS = {"-e", "-f", "--regexp", "--file", "--files", "--type-list"}
for line in os.environ["CMD"].splitlines():
    try:
        lex = shlex.shlex(line, posix=True, punctuation_chars=";&|<>()")
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        toks = line.split()
    seg = []
    for t in toks + [";"]:
        if not (t and set(t) <= set(";&|<>()")):
            seg.append(t)
            continue
        if seg and seg[0] in ("rg", "grep", "cat", "sed"):
            args, pattern_given, skip = [], seg[0] == "cat", False
            for a in seg[1:]:
                if skip:
                    skip = False
                elif a in VALUED[seg[0]]:
                    skip, pattern_given = True, pattern_given or a in PATTERN_FLAGS
                elif a.startswith("-"):
                    pattern_given = pattern_given or a.split("=")[0] in PATTERN_FLAGS
                else:
                    args.append(a)
            if not pattern_given:
                args = args[1:]
            if any(".claude/" not in a and SRC.search(a) for a in args):
                sys.exit(0)
        seg = []
sys.exit(1)
PY
  echo >> "$N"
  [ "$(wc -l < "$N")" -ge "$MCP_UNUSED_AFTER" ] || return 0
  : > "$TOLD"
  # Main's own session (git dir == common dir) is exempt.
  DIR=${CLAUDE_PROJECT_DIR:-$PWD}
  GD=$(env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE git -C "$DIR" rev-parse --git-dir 2>/dev/null) || return 0
  [ "$GD" = "$(env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE git -C "$DIR" rev-parse --git-common-dir 2>/dev/null)" ] && return 0
  # The send line comes from the dispatch preamble in this session's transcript.
  # Newer Orca preambles carry no dispatch capability, so it is optional; an
  # older preamble's capability is kept.
  TP=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  LINE=$(grep -oE 'send --from term_[A-Za-z0-9_-]+( --dispatch-capability dcap_[A-Za-z0-9_-]+)? --type escalation' "$TP" 2>/dev/null | tail -1)
  IDS=$(grep -oE -- '--task-id task_[A-Za-z0-9_]+ --dispatch-id ctx_[A-Za-z0-9_]+' "$TP" 2>/dev/null | tail -1)
  # Unquoted on purpose: both captures are flag/value pairs of [A-Za-z0-9_-].
  [ -z "$LINE" ] || [ -z "$IDS" ] || timeout 10 orca-ide orchestration $LINE \
    --subject "$(basename "$DIR"): $MCP_UNUSED_AFTER shell searches, no serena or codebase-memory call" \
    --body "Worker $(basename "$DIR") (pane ${ORCA_TERMINAL_HANDLE:-unknown}, session $MCP_KEY) has run $MCP_UNUSED_AFTER source searches and no MCP call." \
    $IDS --json >/dev/null 2>&1 || true
  echo "MCP UNUSED: $MCP_UNUSED_AFTER shell searches and not one serena or codebase-memory call. Use serena find_symbol / find_referencing_symbols and codebase-memory search_graph / trace_path for code; if they are missing from this session, stop and say so. Main has been told." >&2
  return 2
}

[ "$IS_ERROR" = true ] && exit 0

if [ "$TOOL_NAME" = Bash ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
  # The nudge names serena, so it is for projects that have it.
  pp_serena || exit 0
  mcp_unused_tripwire "$CMD"
  exit $?
fi
exit 0
