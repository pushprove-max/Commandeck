#!/usr/bin/env bash
# PostToolUse hook (Read|Bash), default tier: record the absolute path of every file this session read, one per
# line, in /tmp/claude-read-tracker-<session id>. companion-read-guard.sh is the one reader (issue 520).
# read-tracker.sh is strict-tier and records no paths, so this is a separate hook.
# Writes only when .claude/companions.tsv exists: a project with no pairs keeps no file. The session id must be
# a UUID. A failed or refused read is not a read. A shell read comes from lib/shell_reads.py in its `proof` mode (dump
# and read lines): only a read the command's text shows reached the agent, so a query that may print nothing is left out.
# Never cleaned, as the other /tmp/claude-* files: a lost file costs one more read.
# Self-test: bash hooks/__tests__/companion-read-guard.test.sh
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
IFS=$'\001' read -r SID TOOL CWD FILE CMD EVENT ERR SHOWN < <(jq -r '[.session_id // "", .tool_name // "", .cwd // "",
  .tool_input.file_path // "", (.tool_input.command // "" | gsub("[\u0001\n]"; " ")), .hook_event_name // "",
  (if (.tool_response | type) == "object" then (.tool_response.is_error // (.tool_response.error | if . then true else false end) // false) else false end | tostring),
  ((.tool_response | objects | .file | objects | .content | strings | length > 0) // false | tostring)]
  | join("\u0001")' <<<"$INPUT" 2>/dev/null)
HEX='[0-9A-Fa-f]'
[[ ${SID-} =~ ^$HEX{8}-$HEX{4}-$HEX{4}-$HEX{4}-$HEX{12}$ ]] || exit 0
[ "${ERR-}" != true ] && [ "${EVENT-}" != PostToolUseFailure ] || exit 0
ROOT=$(git -C "${CLAUDE_PROJECT_DIR:-${CWD:-$PWD}}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$ROOT/.claude/companions.tsv" ] || exit 0
CWD=${CWD:-${CLAUDE_PROJECT_DIR:-$PWD}}
TRACKER=/tmp/claude-read-tracker-$SID

record() { # $1 = path
  grep -qxF -- "$1" "$TRACKER" 2>/dev/null || printf '%s\n' "$1" >> "$TRACKER"
}

case "$TOOL" in
  Read)
    # Only a Read that showed text is a read: one past the end answers `content: ""` (#531).
    [ -n "$FILE" ] && [ "${SHOWN-}" = true ] || exit 0
    case "$FILE" in /*) ;; *) FILE=$CWD/$FILE ;; esac
    [ -f "$FILE" ] && record "$(realpath -m "$FILE")" ;;
  Bash)
    while IFS=$'\t' read -r KIND ABS; do
      case "$KIND" in dump | read) [ -n "${ABS-}" ] && record "$ABS" ;; esac
    done < <(python3 -I "${BASH_SOURCE[0]%/*}/lib/shell_reads.py" "$CMD" "$CWD" proof 2>/dev/null) ;;
esac
exit 0
