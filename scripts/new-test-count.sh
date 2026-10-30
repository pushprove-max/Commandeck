#!/usr/bin/env bash
# new-test-count.sh <base> -- issue 433: how many tests the unit's own change adds, for the new-test cap the pass
# script holds a change to (reviewLoop.newTestCap). Prints the count on its first line, then each new label.
# The change is the unit's own: from where HEAD left <base> (git merge-base), never a review base, so work already on
# main is not counted again. Test files are the skip/only guard's (hooks/lib/test-path.sh). A new test is a label
# added in a test file: `check "<label>"` in a shell file, `it(` or `test(` with a string label in any other. A label
# also on a removed line was moved, not added. Checks made in a loop or through a helper count as one or none: the
# count is a review gate on labels, not a proof of count.
set -uo pipefail
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
BASE=${1:?usage: new-test-count.sh <base>}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/../hooks/lib/test-path.sh" || { echo "new-test-count: cannot load hooks/lib/test-path.sh" >&2; exit 2; }
FROM=$(git merge-base "$BASE" HEAD) || { echo "new-test-count: cannot find where HEAD left $BASE" >&2; exit 2; }
# The change as the pass will commit it, uncommitted and untracked files included: staged into a copy of the index.
IDX=$(mktemp) || exit 2; trap 'rm -f "$IDX"' EXIT
cp "$(git rev-parse --absolute-git-dir)/index" "$IDX" 2>/dev/null || : > "$IDX"
export GIT_INDEX_FILE=$IDX
git add -A && git reset -q -- .claude/briefs 2>/dev/null || { echo "new-test-count: cannot stage the change in a copy of the index" >&2; exit 2; }
FILES=$(git diff --cached --name-only --no-renames "$FROM") || { echo "new-test-count: git diff $FROM failed" >&2; exit 2; }
labels() { # <file> <+|->: the labels on that side of the file's diff, one per line
  local re
  case $1 in
    # A check call opens its line: `check "x"` quoted inside a fixture's printf is no test of this file.
    *.sh) re='^[[:space:]]*check[[:space:]]+"[^"]+"' ;;
    *) re="\\b(it|test)\\([[:space:]]*(\"[^\"]+\"|'[^']+'|\`[^\`]+\`)" ;;
  esac
  git diff --cached -U0 --no-renames --no-ext-diff --no-textconv "$FROM" -- "$1" \
    | grep -E "^[$2]" | grep -vE '^(\+\+\+|---) ' | cut -c2- | grep -oE "$re" | sed -E 's/^[^"'"'"'`]*["'"'"'`]//; s/["'"'"'`]$//'
}
TESTS=$(while IFS= read -r f; do [ -n "$f" ] && is_test_path "$f" && echo "$f"; done <<<"$FILES")
side() { while IFS= read -r f; do [ -z "$f" ] || labels "$f" "$1"; done <<<"$TESTS"; }
# A removed label, in this file or another (a file split by section), was moved: each cancels one addition of it.
NEW=$(awk 'FILENAME == ARGV[1] { gone[$0]++; next } gone[$0] > 0 { gone[$0]--; next } { print }' <(side -) <(side +))
grep -c . <<<"$NEW"
[ -z "$NEW" ] || printf '%s\n' "$NEW"
