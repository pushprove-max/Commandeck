#!/usr/bin/env bash
# Stop hook: a closing reply past 3,000 characters that names no file is sent back once, to be written to a file and
# answered with the path and a short summary (issue 552). A long reply stays in the context and is replayed on every
# later turn; a file is read once, by whoever needs it.
# Retire when: Claude Code caps or summarises a long closing reply itself
#
# One hold per chain: the second stop (stop_hook_active) passes, as does a reviewer pane. A reply names a file when
# a word holds a `/` and ends in an extension. The payload's last_assistant_message is the reply (Codex sends it
# too, hooks/codex-dispatch.sh); an absent one passes.
#
# Self-test: bash hooks/__tests__/long-reply-stop.test.sh
set -uo pipefail
LIMIT=3000

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
[ "$(jq -r '.stop_hook_active // false' <<<"$INPUT" 2>/dev/null)" = true ] && exit 0
[ "${COMMANDECK_REVIEWER:-}" = 1 ] && exit 0
TEXT=$(jq -r '.last_assistant_message // empty' <<<"$INPUT" 2>/dev/null)
[ "${#TEXT}" -gt "$LIMIT" ] || exit 0
[[ $TEXT =~ [^[:space:]]*/[^[:space:]]*\.[A-Za-z0-9]+ ]] && exit 0

printf '%s\n' "HELD: this closing reply is ${#TEXT} characters and names no file. It would stay in the context for every later turn." \
  "Write the full reply to a file, then end the turn with the file's path and a short summary. If the reply must stay as it is, end the turn again." >&2
HOOK_FIRE_REASON=long-reply-no-file
exit 2
