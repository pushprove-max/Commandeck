#!/usr/bin/env bash
# PreToolUse hook (Read), Builders only (COMMANDECK_BUILDER=1): refuse a Read with no offset or limit of a text
# file over 400 lines, and name a range. Issue 247: a whole long file read once is carried on every later turn of
# the build, where the lines it needed were a range a grep -n would have found. Subagents read for their own
# context and are never refused. Open on failure (a cost guard: a crash must not stop a Builder reading).
# Self-test: bash hooks/__tests__/read-range-guard.test.sh
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
[ "${COMMANDECK_BUILDER-}" = 1 ] || exit 0
MAX=400
IFS=$'\001' read -r AID FILE RANGED < <(jq -r '[.agent_id // "", .tool_input.file_path // "",
  (.tool_input.offset != null or .tool_input.limit != null | tostring)] | join("\u0001")' <<<"$INPUT" 2>/dev/null)
[ -z "$AID" ] && [ "$RANGED" = false ] && [ -f "$FILE" ] || exit 0
grep -Iq . "$FILE" 2>/dev/null || exit 0
N=$(wc -l < "$FILE" 2>/dev/null | tr -d ' ')
[ "${N:-0}" -gt "$MAX" ] || exit 0
echo "BLOCKED: $FILE has $N lines; a whole read of it rides every later turn. Find the line first with \`grep -n <pattern> $FILE\`, then Read a range: offset 1, limit 200, or offset <line> with the limit you need." >&2
exit 2
