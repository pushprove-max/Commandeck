#!/usr/bin/env bash
# PostToolUse hook (Edit|Write|MultiEdit): run a freshness pass on a worker brief or
# plan at the moment it matters -- when main writes it, just before dispatch.
#
# A brief written over several edits went out citing files that had moved. The
# checks are cheap and only warn: a moved path is a thing for a person to judge.
#   1. Every repo path the brief cites still exists, EXCEPT the ones the brief
#      says it is about to create. A dead citation is the failure; a path in a
#      line that reads "create ...", "NEW ..." or "add ..." is the brief's own
#      output and warning about it trained the warning away.
#   2. A plan that names a heavy or padded fixture carries a `Timed checks:` line.
#
# BRIEF_FRESHNESS_DRY_RUN=1 also prints how many cited paths were checked, so
# the self-test proves the gate read the brief and did not just stay silent.
# Retire when: a linter checks every path a brief cites

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"

# PREFILTER. A substring test on the raw payload, before the first jq: the
# scope test below can only match when this one does, so a payload this skips
# could never have reached the rule. It is what keeps a path-scoped hook from
# costing a fork on every unrelated edit.
case "$INPUT" in *.claude/briefs/*|*.claude/plans/*) ;; *) exit 0 ;; esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
case "$FILE_PATH" in
  */.claude/briefs/*.md|*/.claude/plans/*.md) ;;
  *) exit 0 ;;
esac
[ -f "$FILE_PATH" ] || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Plan warning, before the CITED early exit so a plan citing no path still gets it. It warns and
# never blocks: this hook runs after the write, and the fixture match is a keyword guess.
case "${FILE_PATH##*/}" in _*) ;; *)
  if grep -qiE 'heavy fixture|padded fixture' "$FILE_PATH" && ! grep -qE '^Timed checks: .+' "$FILE_PATH"; then
    HOOK_FIRE_ADVISE=1
    echo "WARN [brief-freshness] a heavy or padded fixture with no 'Timed checks: <checks>' line: name the time-bound checks of that test file and order the heavy case after them." >&2
  fi ;;
esac

# Repo paths a brief cites.
CITED=$(grep -oE '(hooks|templates|config|skills|ci|docs)/[A-Za-z0-9_./-]+\.(tsx|ts|js|mjs|sh|json|md)' \
  "$FILE_PATH" 2>/dev/null | sort -u)
[ -z "$CITED" ] && exit 0

# A path the brief is COMMISSIONING is not a stale citation. The test is the
# citing line itself: "create", "new" or "add" next to the path is the brief
# saying the file does not exist yet, which is the whole point of writing it.
planned() {
  grep -iE "(create|creates|new|add|adds|write)[^\n]*$(printf '%s' "$1" | sed 's/[.[\*^$/]/\\&/g')" \
    "$FILE_PATH" >/dev/null 2>&1
}

MISSING=""
PLANNED=0
while IFS= read -r p; do
  [ -e "$ROOT/$p" ] && continue
  if planned "$p"; then PLANNED=$((PLANNED + 1)); continue; fi
  MISSING="$MISSING  $p"$'\n'
done <<< "$CITED"

if [ -n "$MISSING" ]; then
  HOOK_FIRE_ADVISE=1
  echo "WARN [brief-freshness] this brief cites files that do not exist:" >&2
  printf '%s' "$MISSING" >&2
  echo "  Fix the brief before dispatching; the worker cannot find them either." >&2
  [ "$PLANNED" -gt 0 ] && echo "  ($PLANNED more are described as new files, so they are not counted here.)" >&2
fi

[ -z "${BRIEF_FRESHNESS_DRY_RUN:-}" ] || echo "[brief-freshness] checked $(echo "$CITED" | wc -l) cited paths"
exit 0
