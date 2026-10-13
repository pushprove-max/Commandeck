#!/usr/bin/env bash
set -u
SOURCE=$(git rev-parse --show-toplevel)

# Simulate main topology without creating or modifying a checkout.
git() { printf '%s\n' /fixture/.git; }
export -f git

TEXT=$'Example:\n~~~text\nready?\n~~~\nDone.'
PAYLOAD=$(jq -cn --arg text "$TEXT" \
  '{last_assistant_message:$text, stop_hook_active:false}')

printf '%s' "$PAYLOAD" |
  CLAUDE_PROJECT_DIR=/fixture COMMANDECK_REVIEWER=0 \
  bash "$SOURCE/hooks/ask-stop-records-decision.sh"
RC=$?

[ "$RC" -eq 0 ] || {
  echo "FAIL: code-only question held a turn that asks the owner nothing" >&2
  exit 1
}
