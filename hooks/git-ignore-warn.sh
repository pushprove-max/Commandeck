#!/usr/bin/env bash
# PostToolUse hook (Write): surface it IMMEDIATELY when a written file is
# gitignored -- the file will silently never ship.
#
# Seed incident (6f48f3a0): the end-state publisher was written into scripts/,
# whose deny-by-default gitignore swallowed it; the "committed" work simply
# did not exist in the repo, and nothing said so until a later session went
# looking. `git check-ignore` knows in one call.
#
# Deliberate scratch paths (logs/, coverage/, tmp/, a scratchpad dir) are
# skipped: nothing there was ever meant to ship, so the warning is only noise.
#
# Advisory, so it EXITS 0 and carries its advice as native additionalContext
# (staged-index-warn.sh set that shape). A non-zero advisory shows a Codex seat
# `Script failed` with no text at all, so the seat never hears the advice and
# redoes the work. The write itself has already happened -- the demanded
# action is a decision, not a revert: `git add -f`, an unignore rule, a
# different path, or "scratch file, carry on".

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0
# Write ONLY, checked against tool_name rather than trusted to the matcher:
# the hook is registered in the shared Edit|Write|MultiEdit group, and firing
# on every EDIT of a deliberately-ignored file (settings.local.json, the
# convergence marker) re-warns forever on ordinary work (Codex round-1 P2).
# The seed incident was a NEW file written into an ignored path; Write is
# where that happens.
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "Write" ] || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0
# git reports the physical toplevel; a path through a symlink (macOS /tmp)
# would otherwise read as outside the repo and never warn.
FILE_PATH=$(realpath -- "$FILE_PATH")

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
case "$FILE_PATH" in
  "$ROOT"/*) ;;      # only files inside the repo can be swallowed by it
  *) exit 0 ;;
esac

# Already tracked files cannot be silently lost -- check-ignore on a tracked
# path reports the PATTERN, not the risk, so skip them.
git -C "$ROOT" --no-optional-locks ls-files --error-unmatch -- "$FILE_PATH" >/dev/null 2>&1 && exit 0

# DELIBERATE SCRATCH PATHS. These directories exist to hold files that are not
# meant to ship -- logs, coverage output, build products, the repo's own tmp
# tree. Announcing that a log file will not be committed is noise, and the
# 6f48f3a0 shape (real work written into an ignored path) never looks like one
# of these.
case "${FILE_PATH#"$ROOT"/}" in
  tmp/*|logs/*|coverage/*|dist/*|cdk.out/*|node_modules/*|*/node_modules/*) exit 0 ;;
  *.log|*.tsbuildinfo|*/scratchpad/*|scratchpad/*) exit 0 ;;
  .claude/briefs/*|todo/main-todo.md) exit 0 ;;   # setup hides these from git on purpose (install-lib.sh IL_STATE)
esac

# -v also prints a `!` rule that brings the path back, so the verdict is asked
# for first, without it.
git -C "$ROOT" --no-optional-locks check-ignore -q -- "$FILE_PATH" 2>/dev/null || exit 0
PATTERN=$(git -C "$ROOT" --no-optional-locks check-ignore -v -- "$FILE_PATH" 2>/dev/null | head -1)
[ -z "$PATTERN" ] && exit 0

ADVICE=$(cat <<EOF
GITIGNORED: the file just written will silently never ship.

  file:    ${FILE_PATH#"$ROOT"/}
  matched: $PATTERN

This is the 6f48f3a0 failure shape: work written into an ignored path reads
as done, commits "succeed" around it, and the artifact does not exist in the
repo. Decide now: move it, \`git add -f\` it, add an unignore rule -- or, if
it is genuinely a scratch/session file, say so and carry on.
EOF
)
HOOK_FIRE_ADVISE=1
printf '%s\n' "$ADVICE" >&2
jq -cn --arg message "$ADVICE" '{
  systemMessage:$message,
  hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$message}
}' 2>/dev/null || true
exit 0
