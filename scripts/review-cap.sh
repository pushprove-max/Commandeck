#!/usr/bin/env bash
# review-cap.sh <unit> <rounds> -- main's one command for the owner's extra
# review rounds on one unit: writes <main>/.claude/briefs/<unit>-review-cap.md,
# which builder-*-pass.sh reads before reviewLoop.maxRounds. The briefs folder
# is never committed, so neither checkout gets dirty and the merge's step 1
# still passes; the merge archives the file with the unit's other papers.
# Refused in a linked worktree: a Builder does not raise its own limit.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
. "$(dirname "$0")/paths.sh"
USAGE="usage: review-cap.sh <unit> <rounds>"
UNIT=${1:?$USAGE} R=${2:?$USAGE}
[[ $UNIT =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bad unit name: $UNIT" >&2; exit 2; }
[[ $R =~ ^[1-9][0-9]*$ ]] || { echo "rounds must be a whole number above 0, not $R" >&2; exit 2; }
[ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ] \
  || { echo "review-cap.sh is main's command: run it in main's checkout, not in a worktree" >&2; exit 2; }
mkdir -p "$PP_MAIN/.claude/briefs"
printf '%s\n' "$R" > "$PP_MAIN/.claude/briefs/$UNIT-review-cap.md"
echo "review-cap: $UNIT may run passes up to round $R"
