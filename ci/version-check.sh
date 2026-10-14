#!/usr/bin/env bash
# version-check.sh [<base>] -- fail when the plugin changed against the main
# branch and .claude-plugin/plugin.json still carries the version main has: a
# machine that has the plugin sees nothing new on update until the number
# moves. <base> is the commit or branch to compare with, origin/main by
# default; the comparison is from where this tree left it, and counts what is
# not committed yet. The version must differ from the one this tree left and
# from the one <base> has now: another branch may have taken the same number.
# What counts as the plugin: the folders in PLUGIN below. What does not: the
# files at the top of the repository (README.md, CHANGELOG.md and the like),
# ci/ and .github/. A test under hooks/ or scripts/ counts: it ships.
# Exit 0 nothing to say, 1 the version must change, 2 no base to compare with.
# Self-test: bash scripts/__tests__/version-check.test.sh
set -euo pipefail
PLUGIN=(.claude-plugin/ config/ dashboard/ hooks/ scripts/ skills/ templates/)
BASE=${1:-origin/main}
cd "$(git rev-parse --show-toplevel)"
FROM=$(git merge-base "$BASE" HEAD 2>/dev/null) || { echo "version-check: nothing named $BASE to compare with here; fetch the main branch first" >&2; exit 2; }
CHANGED=$({ git diff --name-only "$FROM" -- "${PLUGIN[@]}"; git ls-files --others --exclude-standard -- "${PLUGIN[@]}"; } | sort -u)
[ -n "$CHANGED" ] || { echo "version-check: no plugin file changed against $BASE"; exit 0; }
version_at() { git show "$1:.claude-plugin/plugin.json" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true; }
WAS=$(version_at "$FROM") HAS=$(version_at "$BASE")
NOW=$(jq -r '.version // empty' .claude-plugin/plugin.json)
if [ -n "$NOW" ] && [ "$NOW" != "$WAS" ] && [ "$NOW" != "$HAS" ]; then echo "version-check: the plugin changed and its version did, ${WAS:-none} to $NOW"; exit 0; fi
{
  echo "version-check: the plugin changed against $BASE and its version is still ${NOW:-missing}${HAS:+ ($BASE has $HAS)}."
  echo "Raise it in .claude-plugin/plugin.json and the README's badge, with a CHANGELOG.md entry: the third part for a fix, the second for new behaviour."
  echo "What counts as the plugin: ${PLUGIN[*]}. Changed there ($(wc -l <<<"$CHANGED" | tr -d ' ')):"
  head -10 <<<"$CHANGED" | sed 's/^/  /'
} >&2
exit 1
