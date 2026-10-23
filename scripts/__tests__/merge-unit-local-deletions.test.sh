#!/usr/bin/env bash
# covers: scripts/merge-unit-local.sh
# merge-unit-local.sh step 4's deletion check (issue 326). Its own file: merge-unit-local.test.sh already runs near its cap.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-unit-local-setup.sh"

# Issue 326: a directory named once, in backticks with its trailing slash, lists every file under it, whether in the brief
# or in a plan the brief names; a plan counts as committed at the fork point, so a unit cannot authorise its own
# deletion by editing it. Rebuilt admin pages (hashed file names) are the case: nobody can name each file.
for d in d1 d2 d3 d4 d5 d5x; do mkdir -p "$REPO/$d/sub"; echo old > "$REPO/$d/f.js"; echo old > "$REPO/$d/sub/g.js"; done
mkdir -p "$REPO/.claude/plans"; echo 'Cut the old pages: `d3/`.' > "$REPO/.claude/plans/p3.md"; echo 'Nothing is cut.' > "$REPO/.claude/plans/p4.md"
git -C "$REPO" add -A d1 d2 d3 d4 d5 d5x .claude/plans; git -C "$REPO" commit -qm "main: files to delete"
# gone <unit> <brief text> <dir>: a unit whose one commit deletes every file under <dir>, with that brief
gone() { mk "$1"; local w=$COMMANDECK_WORKSPACES/$1; printf '# %s\n\n%s\n' "$1" "$2" > "$w/.claude/briefs/$1.md"
  git -C "$w" rm -qr "$3" && git -C "$w" commit -qm "cut $3"; go "$1"; }
H1=$(git -C "$REPO" rev-parse HEAD)
gone dl1 'Delete the old pages.' d1
check "files the brief never names are refused, as before, and main is unchanged" "1 1 $H1" \
  "$(merge dl1) $(grep -c 'the squash deletes d1/.* which the brief never names' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
gone dl2 'Delete the old pages: `d2/`.' d2
check "a directory named once with its trailing slash in the brief lets every file under it go" "0 0" \
  "$(merge dl2) $(ls "$REPO/d2" 2>/dev/null | wc -l | tr -d ' ')"
gone dl3 'Follow `.claude/plans/p3.md`.' d3
check "a directory named in a plan the brief names lets every file under it go" "0 0" \
  "$(merge dl3) $(ls "$REPO/d3" 2>/dev/null | wc -l | tr -d ' ')"
mk dl4; W4=$COMMANDECK_WORKSPACES/dl4
printf '# dl4\n\nFollow `.claude/plans/p4.md`.\n' > "$W4/.claude/briefs/dl4.md"
echo 'Cut `d4/`.' > "$W4/.claude/plans/p4.md"; git -C "$W4" rm -qr d4; git -C "$W4" add .claude/plans/p4.md; git -C "$W4" commit -qm "cut d4 and say so in the plan"; go dl4
H4=$(git -C "$REPO" rev-parse HEAD)
check "a unit that adds the directory to the plan itself is refused: the plan counts as committed at the fork point" "1 $H4" \
  "$(merge dl4) $(git -C "$REPO" rev-parse HEAD)"
gone dl5 'Delete the old pages: `d5/`.' d5x
check "a named directory is not a name prefix: d5/ does not let d5x/ go" "1 1" \
  "$(merge dl5) $(grep -c 'the squash deletes d5x/' "$TMP/out")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
