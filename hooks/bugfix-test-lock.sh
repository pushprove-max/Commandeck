#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit): a failing test, once written, is the spec for the fix. While its path is
# listed in .claude/bugfix-lock the file tools refuse to touch it: fix the code, then rerun the test as written.
# Issue 517. Self-test: bash hooks/__tests__/bugfix-test-lock.test.sh
#
# A tripwire against the common path, not a security boundary. It does not parse Bash, so `sed -i` on a locked test
# passes: a guess at intent from a shell string is not a parse that can be won, and a guard that claims to be
# complete is worse than none.
#
# Lock file (the project root, run state, never committed): one repo-relative path per line; blank lines and `#`
# comments are ignored. An absolute path, a `..` or a glob line is warned about on stderr and ignored, never
# honoured: a line nobody can read would lock the wrong edit.
#
# Unlock is process: the Builder writes the lock and empties it once the fix is verified. Nothing here checks when.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Retire when: zero blocks across 90 days of real rows from a project that lists files in .claude/bugfix-lock

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] || exit 0
ROOT=$(realpath -m "$ROOT" 2>/dev/null || printf '%s' "$ROOT")
LOCK="$ROOT/.claude/bugfix-lock"
# No lock file is the normal state: no output at all.
[ -f "$LOCK" ] || exit 0

# A MultiEdit may carry the path on each edit; read both places.
TARGETS=$(jq -r '[.tool_input.file_path // empty, (.tool_input.edits // [] | .[] | .file_path // empty)] | .[]' <<<"$INPUT" 2>/dev/null)
[ -n "$TARGETS" ] || exit 0

# Both sides go through one canonicalizer: the tool may send an absolute path where the lock holds a relative one.
# -m keeps a Write to a file that does not exist yet working.
canon() {
  local p=$1
  case $p in /*) ;; *) p="$ROOT/$p" ;; esac
  realpath -m -- "$p" 2>/dev/null || printf '%s\n' "$p"
}

LOCKED=()
while IFS= read -r RAW || [ -n "$RAW" ]; do
  LINE=$(printf '%s' "$RAW" | tr -d '\r')
  LINE="${LINE#"${LINE%%[![:space:]]*}"}"
  LINE="${LINE%"${LINE##*[![:space:]]}"}"
  [ -n "$LINE" ] || continue
  case $LINE in \#*) continue ;; esac
  case $LINE in
    /*|*..*|*\**|*\?*|*\[*|*\]*)
      echo "bugfix-test-lock: ignoring lock line '$LINE': a line is a repo-relative path with no '..' and no glob." >&2
      continue ;;
  esac
  LOCKED+=("$(canon "$LINE")")
done < "$LOCK"
[ ${#LOCKED[@]} -gt 0 ] || exit 0

while IFS= read -r TARGET; do
  ABS=$(canon "$TARGET")
  for L in "${LOCKED[@]}"; do
    [ "$ABS" = "$L" ] || continue
    REL="${ABS#"$ROOT"/}"
    cat >&2 <<EOF
BLOCKED: $REL is a locked failing test. Fix the code, not the test, then run the test again as it is. See what the lock guards with \`git diff -- $REL\`.
If your brief or a review finding names a change to this test, make it with the Edit tool on .claude/bugfix-lock: delete the line '$REL', make only the named change, then Edit the line back, and show the test before and after in your evidence file. Any wider change is a question for main.
The line leaves .claude/bugfix-lock only after the fix is verified.
EOF
    HOOK_FIRE_REASON=locked-test
    exit 2
  done
done <<<"$TARGETS"
exit 0
