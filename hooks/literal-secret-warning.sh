#!/usr/bin/env bash
# PreToolUse hook: warn on a literal secret assigned in executable code.
# The matcher routes MultiEdit here, so batch payloads must be read or the
# screen is decorative. One definition of that, shared: lib/edit-payload.sh.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
source "$(dirname "${BASH_SOURCE[0]}")/lib/edit-payload.sh" 2>/dev/null
# A guard that cannot read the payload must NOT pass the write: see the load
# sentinel at the bottom of lib/edit-payload.sh.
hook_payload_loaded 2>/dev/null || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load hooks/lib/edit-payload.sh, so it cannot screen this write. Reinstall the plugin and retry." >&2; exit 2; }
CONTENT=$(hook_new_text "$INPUT")

[ -z "$CONTENT" ] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
# Skip config/env files and test files
case "$FILE_PATH" in
  *.test.*|*__tests__*|*.env*|*config/env*) exit 0 ;;
esac
# EXECUTABLE CODE ONLY. A literal that looks like a secret is a finding when it
# SHIPS. In markdown, a sample payload, a lockfile or a fixture it is text, and
# the pattern below (`token: "<8+ chars>"`) matches ordinary prose there.
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py|*.sh) ;;
  *) exit 0 ;;
esac

# A literal secret. Reading a secret from the environment is NOT itself a
# leak, so the blanket "direct env var secret access" warning is gone: it fired
# on every legitimate config read and told the reader nothing they could act on.
# The exemption is the line's own: an environment read elsewhere in the write
# says nothing about a literal beside it.
if echo "$CONTENT" | grep -E "(password|secret|apiKey|token|credential)\s*[:=]\s*['\"][^'\"]{8,}['\"]" | grep -qvE "process\.env|getSetting|getParameter|SecretStore"; then
  HOOK_FIRE_ADVISE=1
  echo "WARNING: Possible hardcoded secret in $FILE_PATH. Read it from the environment or a secret store." >&2
fi

exit 0
