#!/usr/bin/env bash
# merge-unit-local.sh STEP 4 archives the unit's brief files. Main stages the
# next cut's brief (`<unit>-cut<N>-*.md`) beside them before the merge, and the
# `<unit>*.md` glob archived and removed it too, so the next cut lost its brief.
#   1. a staged `<unit>-cut1-audit.md` stays on disk and out of the tar;
#   2. the round file `<unit>-r1-reports.md` is still archived.
set -euo pipefail
ROOT_REAL=$(git rev-parse --show-toplevel)
SCRIPT=$ROOT_REAL/scripts/merge-unit-local.sh
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# The archive loop, sliced out of the script.
awk '/^  KEPT=0 MAIN_FILES=\(\)/ { on=1 } on { print } on && /^  done( |$)/ { exit }' "$SCRIPT" > "$TMP/archive.sh"
[ -s "$TMP/archive.sh" ] || fail "the STEP 4 archive loop is not in merge-unit-local.sh"

UNIT=cut-unit
ROOT=$TMP/repo
ARCHIVE=$TMP/briefs-$UNIT.tar
# shellcheck disable=SC2034  # read by the sliced loop: no worktree holds a namesake of main's files
WT=$TMP/wt
git init -q "$ROOT"
mkdir -p "$ROOT/.claude/briefs"
for f in "$UNIT.md" "$UNIT-r1-reports.md" "$UNIT-cut1-audit.md" "$UNIT-evidence.md"; do echo x > "$ROOT/.claude/briefs/$f"; done
cd "$ROOT"
# The loop lists the unit's files with paths.sh's pp_unit_briefs, sliced out the same way.
awk '/^pp_unit_briefs\(\) \{/ { on=1 } on { print } on && /^}$/ { exit }' "$ROOT_REAL/scripts/paths.sh" > "$TMP/briefs.sh"
[ -s "$TMP/briefs.sh" ] || fail "pp_unit_briefs is not in paths.sh"
# shellcheck disable=SC1090,SC1091
. "$TMP/briefs.sh"
# shellcheck disable=SC1090,SC1091
. "$TMP/archive.sh"

LISTED=$(tar -tf "$ARCHIVE")
[ -f "$ROOT/.claude/briefs/$UNIT-cut1-audit.md" ] || fail "the staged next-cut brief was removed"
grep -qx "$UNIT-cut1-audit.md" <<<"$LISTED" && fail "the staged next-cut brief went into the archive"
grep -qx "$UNIT-r1-reports.md" <<<"$LISTED" || fail "the round report was not archived: $LISTED"
grep -qx "$UNIT.md" <<<"$LISTED" || fail "the unit brief was not archived: $LISTED"
echo "PASS: STEP 4 archives the unit's brief files and leaves a staged next-cut brief in place"
