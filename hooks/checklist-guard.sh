#!/usr/bin/env bash
# PreToolUse hook (TaskCreate, TaskUpdate), main's session only (git dir == common dir): keep the owner's checklist short.
# Refused: a TaskCreate while 8 items are pending or in progress; a subject over 80 characters or one holding an id
# (an issue or PR number, a message, task, dispatch or terminal id, a commit hash); a TaskUpdate to `completed`, since a
# done item is deleted and the checkpoint's Closed section keeps it. The task folder is this session's
# (<config>/tasks/<list id or session id>/); one that cannot be read lets the call through: this guards the list's
# size, not data. A worker session is not checked.
# Self-test: bash hooks/__tests__/checklist-guard.test.sh
set -uo pipefail
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT")}
GITDIR=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
[ "$GITDIR" = "$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ] || exit 0
IFS=$'\001' read -r TOOL SUBJECT STATUS SID < <(jq -r '[.tool_name // "", .tool_input.subject // "", .tool_input.status // "", .session_id // ""] | join("\u0001")' <<<"$INPUT" 2>/dev/null)
CAP=8 MAXLEN=80
block() { printf 'BLOCKED: %s\n' "$1" >&2; exit 2; }
if [ "$TOOL" = TaskUpdate ] && [ "$STATUS" = completed ]; then
  block "a done checklist item is deleted, not marked completed: the checkpoint's Closed section keeps it. Call \`TaskUpdate\` with status \`deleted\` for this task."
fi
[ "$TOOL" = TaskCreate ] || [ -n "$SUBJECT" ] || exit 0
if [ "${#SUBJECT}" -gt "$MAXLEN" ]; then
  block "a checklist subject is $MAXLEN characters at most; this one has ${#SUBJECT}. Shorten it and call \`$TOOL\` again: the owner reads a title, and the detail goes in the checkpoint."
fi
# No ids in a subject: the owner reads these on screen. An issue or PR number (issue 336, issue-336, #12, PR 12), a
# message, task, dispatch or terminal id, a commit hash (7 to 40 hex characters holding a digit and a letter a-f).
ID=$(grep -oiE '#[0-9]+|(^|[^A-Za-z])(issues?|pr)[ -]?#?[0-9]+|(msg|task|ctx|term|dcap)_[A-Za-z0-9]+' <<<"$SUBJECT" | head -1)
[ -n "$ID" ] || ID=$(grep -oE '\b[0-9a-fA-F]{7,40}\b' <<<"$SUBJECT" | grep '[0-9]' | grep -i '[a-f]' | head -1)
if [ -n "$ID" ]; then
  ID=$(sed -E 's/^[^A-Za-z0-9#]//' <<<"$ID")
  block "a checklist subject holds no ids (no issue or PR number, message, task or dispatch id, or commit hash); this one has \`${ID# }\`. Say what the item is in words and call \`$TOOL\` again."
fi
[ "$TOOL" = TaskCreate ] || exit 0
DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/tasks/${CLAUDE_CODE_TASK_LIST_ID:-$SID}
[ -n "${CLAUDE_CODE_TASK_LIST_ID:-$SID}" ] && [ -d "$DIR" ] || exit 0
FILES=("$DIR"/*.json); [ -e "${FILES[0]}" ] || exit 0
OPEN=$(jq -s '[.[] | select(.status == "pending" or .status == "in_progress")] | length' "${FILES[@]}" 2>/dev/null) || exit 0
[[ $OPEN =~ ^[0-9]+$ ]] || exit 0
if [ "$OPEN" -ge "$CAP" ]; then
  block "the checklist holds $OPEN open items and $CAP is the most. Delete one that is done (\`TaskUpdate\` with status \`deleted\`) or merge two, then call \`TaskCreate\` again."
fi
exit 0
