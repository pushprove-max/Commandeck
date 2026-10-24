#!/usr/bin/env bash
# PreToolUse hook on Edit|Write: Block skipped/focused tests (masking).
# .only silently drops the rest of the suite; .skip/xit hide failing tests --
# both defeat coverage and let regressions through green.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0
source "$(dirname "${BASH_SOURCE[0]}")/lib/edit-payload.sh" 2>/dev/null
# A guard that cannot read the payload must NOT pass the write: see the load
# sentinel at the bottom of lib/edit-payload.sh.
hook_payload_loaded 2>/dev/null || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load hooks/lib/edit-payload.sh, so it cannot screen this write. Reinstall the plugin (\`claude plugin install commandeck@commandeck\`) and retry." >&2; exit 2; }
CONTENT=$(hook_new_text "$INPUT")
[ -z "$CONTENT" ] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
# A hook self-test QUOTES `it.only` as the fixture it must catch; it is not a
# suite of this repo's tests and skips nothing. Same exemption the other content
# guards give their own directory.
#
# BOTH PATH FORMS. A payload may carry the path relative to the repo root, and
# `*/hooks/*` does not match hooks/__tests__/x.test.sh -- that
# path then fell through to `*__tests__*` below and the fixture was screened as
# a real test.
#
# ONLY THE SHELL SELF-TESTS. A project's own folder named hooks (React's
# src/hooks) holds real tests, and `*/hooks/*` let `it.only` through in them.
case "$FILE_PATH" in
  */hooks/__tests__/*.sh|hooks/__tests__/*.sh) exit 0 ;;
esac
case "$FILE_PATH" in
  *.test.*|*.spec.*|*__tests__*|*/e2e/*) ;;
  *) exit 0 ;;
esac
# Focus/skip fns must be matched as CALLS: bare \bfit\b matched the English word
# "fit" in an assertion message and blocked a legit test (2026-07-06). The paren
# is ADJACENT for the same reason -- `does not fit (see the spec)` in a message
# still matched `fit[[:space:]]*\(`, and nobody writes the Jasmine form with a
# space before its arguments.
PATTERN='\b(describe|it|test|context)\.(only|skip)\b|\b(xit|xdescribe|fit|fdescribe)\(|\b(it|test)\.todo\b'
# `// skip-ok: <reason>` is the approved-skip marker -- an assertion
# counter honours exactly this form, so a skip
# annotated the sanctioned way must not be refused by its sibling guard. The
# marker is per LINE: annotating one skip does not license the next.
OFFENDERS=$(echo "$CONTENT" | grep -E "$PATTERN" | grep -vE '//[[:space:]]*skip-ok:')
if [ -n "$OFFENDERS" ]; then
  MATCH=$(printf '%s\n' "$OFFENDERS" | grep -oE "$PATTERN" | head -1)
  echo "BLOCKED: '$MATCH' in $FILE_PATH skips or focuses tests -- that masks failures and disables coverage." >&2
  echo "Remove it and make the test pass. An intentional skip carries // skip-ok: <reason> on the same line, and that is the owner's decision, not a default." >&2
  exit 2
fi

exit 0
