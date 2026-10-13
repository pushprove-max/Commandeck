#!/usr/bin/env bash
# The merge reads the unit's numbered review rounds only, and titles the squash.
# A file beside them that merely looks like a round (`<unit>-rrebase-reports.md`,
# a rebase-conflict report) is never the round the Builder proof reads:
#   1. with only that file, the proof finds no round file at all;
#   2. beside r1, the proof reads r1.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
SCRIPT=$ROOT/scripts/merge-unit-local.sh

UNIT=glob-unit
WT=$TMP/ws/$UNIT
mkdir -p "$WT/.claude/briefs"
git init -q -b main "$WT"
printf 'Codex thread: thr-x\n\nVERDICT: GO\n' > "$WT/.claude/briefs/$UNIT-rrebase-reports.md"
proof() { HOME=$TMP/home CODEX_HOME=$TMP/codex bash "$ROOT/scripts/builder-codex-pass.sh" --verify "$WT" "$UNIT" HEAD 2>&1 || true; }
[[ "$(proof)" == *"no Builder round file for $UNIT"* ]] || fail "the rebase-conflict report was read as a round: $(proof)"
printf 'hand-written\n\nVERDICT: GO\n' > "$WT/.claude/briefs/$UNIT-r1-reports.md"
[[ "$(proof)" == *"$UNIT-r1-reports.md names no Codex thread"* ]] || fail "the proof did not read r1: $(proof)"
echo "PASS: the Builder proof reads numbered rounds only; the rebase-conflict report is skipped"

# STEP 4 titles the squash. A branch with no commit of its own is refused in
# step 1 (a unit's papers are never committed), so the title block never sees one.
#   4. a branch whose only commit is tests keeps the last-commit fallback.
awk '/^TITLE=\$\(git -C "\$WT" log --reverse/ { on=1 } /^# A squash that deletes/ { exit } on { print }' "$SCRIPT" > "$TMP/title.sh"
[ -s "$TMP/title.sh" ] || fail "the STEP 4 title block is not in merge-unit-local.sh"
REPO=$TMP/repo
g() { git -C "$REPO" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null "$@"; }
git init -q -b main "$REPO"
g commit -q --allow-empty -m 'chore(metrics): main tip subject'
g checkout -q -b "builder/$UNIT"
WT=$REPO
mkdir -p "$REPO/__tests__" && echo t > "$REPO/__tests__/a.test.sh"
g add __tests__/a.test.sh && g commit -q -m 'test(x): add red tests'
# shellcheck disable=SC1090,SC1091
. "$TMP/title.sh"
[ "$TITLE" = 'test(x): add red tests' ] || fail "tests-only unit titled '$TITLE', want its last commit's subject"
echo "PASS: STEP 4 keeps the last-commit fallback for a tests-only unit"

# The squash keeps one subject. A unit once fixed two issues in
# two commits, and the title kept only the first ref (#47).
#   5. every issue ref a unit commit subject names reaches the title once;
#   6. base-title selection is unchanged; bodies and main's subjects add nothing.
fresh() { g checkout -q main && { g branch -q -D probe 2>/dev/null || true; } && g checkout -q -b probe; }
c() { mkdir -p "$(dirname "$REPO/$1")" && echo "$2" >> "$REPO/$1" && g add "$1" && g commit -q -m "$2" ${3:+-m "$3"}; }
title_is() {
  # shellcheck disable=SC1090,SC1091
  . "$TMP/title.sh"
  [ "$TITLE" = "$1" ] || fail "$2: titled '$TITLE', want '$1'"
}
g checkout -q main && c main.txt 'chore(main): main work (#99)'

fresh; c src/a.sh 'fix(a): first fix (#48)'; c src/b.sh 'fix(b): second fix (#47)'
title_is 'fix(a): first fix (#48) (#47)' "two fixes naming two issues"
fresh; c src/a.sh 'fix(a): only fix (#48)'
title_is 'fix(a): only fix (#48)' "a single commit"
fresh; c __tests__/a.test.sh 'test(a): red tests (#12)'; c src/a.sh 'feat(a): the unit (#12345)'
c src/a.sh 'fix(a): follow-up (#12345) (#12)' 'Refs #55'
title_is 'feat(a): the unit (#12345) (#12)' "feat after a test commit, a duplicate ref, #12 beside #12345, a body ref"
fresh; c __tests__/a.test.sh 'test(a): red tests (#48)'; c .claude/briefs/u.md 'docs(u): brief (#47)'
c src/a.sh 'fix(a): the fix'
title_is 'fix(a): the fix (#48, #47)' "refs from test and brief subjects that cannot title the squash"
fresh; c __tests__/a.test.sh 'test(a): red tests (#48)'; c __tests__/b.test.sh 'test(b): more tests (#47)'
title_is 'test(b): more tests (#47) (#48)' "the tests-only fallback"
echo "PASS: STEP 4 keeps every unit subject's issue ref once and leaves base-title selection alone"
