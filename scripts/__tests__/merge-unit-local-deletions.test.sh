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
  mkdir -p "$REPO/.claude/briefs"; cp "$w/.claude/briefs/$1.md" "$REPO/.claude/briefs/$1-builder-brief.md"
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
mkdir -p "$REPO/.claude/briefs"; cp "$W4/.claude/briefs/dl4.md" "$REPO/.claude/briefs/dl4-builder-brief.md"
echo 'Cut `d4/`.' > "$W4/.claude/plans/p4.md"; git -C "$W4" rm -qr d4; git -C "$W4" add .claude/plans/p4.md; git -C "$W4" commit -qm "cut d4 and say so in the plan"; go dl4
H4=$(git -C "$REPO" rev-parse HEAD)
check "a unit that adds the directory to the plan itself is refused: the plan counts as committed at the fork point" "1 $H4" \
  "$(merge dl4) $(git -C "$REPO" rev-parse HEAD)"
gone dl5 'Delete the old pages: `d5/`.' d5x
check "a named directory is not a name prefix: d5/ does not let d5x/ go" "1 1" \
  "$(merge dl5) $(grep -c 'the squash deletes d5x/' "$TMP/out")"
# Issues 557 and 560: the check reads main's copy of the brief ($REPO/.claude/briefs/<unit>-builder-brief.md, written at
# launch), never the worktree's, which the Builder edits. A plan is found the way the launcher finds it: the paths under
# the brief's Plan section (backticks optional) and any backticked .claude/plans/<name>.md; a plan only mentioned in
# prose authorises nothing. The evidence's Files deleted list, which the Builder writes, approves nothing on its own.
# A backticked glob that starts with a literal folder approves the deletions it matches.
for d in e1 e2 c1 c2 e5 f6 g7 h8 i9 k1 assets nb; do mkdir -p "$REPO/$d/sub"; echo old > "$REPO/$d/old.js"; echo old > "$REPO/$d/sub/old.js"; done
for pl in 'pc|Cut `c1/`.' 'pe|Cut `e5/`.' 'pf|Cut `f6/`.' 'pg|Cut `g7/`.' 'pi|Delete i9/old.js.'; do echo "${pl#*|}" > "$REPO/.claude/plans/${pl%%|*}.md"; done
git -C "$REPO" add -A e1 e2 c1 c2 e5 f6 g7 h8 i9 k1 assets nb .claude/plans; git -C "$REPO" commit -qm "main: more files to delete"
# cutdir <unit> <main's copy of the brief> <dir> [evidence's Files deleted entry] -- a unit that deletes <dir>
cutdir() { gone "$1" 'Delete the old pages.' "$3"; printf '# %s\n\n%s\n' "$1" "$2" > "$REPO/.claude/briefs/$1-builder-brief.md"
  [ -z "${4:-}" ] || printf '\n## Files deleted\n- %s\n' "$4" >> "$COMMANDECK_WORKSPACES/$1/.claude/briefs/$1-evidence.md"; }
left() { find "$REPO/$1" -type f 2>/dev/null | wc -l | tr -d ' '; }

cutdir wb 'Nothing named.' e1; printf '# wb\n\nDelete `e1/`.\n' > "$COMMANDECK_WORKSPACES/wb/.claude/briefs/wb.md"
check "a deletion named only in the worktree's brief copy is refused" "1 1 2" \
  "$(merge wb) $(grep -c "the squash deletes e1/.*which the brief never names" "$TMP/out") $(left e1)"
cutdir mb 'Delete the old pages: `e2/`.' e2
check "a deletion named in main's brief copy is accepted" "0 0" "$(merge mb) $(left e2)"
mk mp; git -C "$COMMANDECK_WORKSPACES/mp" rm -qr c1 c2 && git -C "$COMMANDECK_WORKSPACES/mp" commit -qm "cut c1 and c2"; go mp
mkdir -p "$REPO/.claude/briefs"; printf '# mp\n\nFollow `.claude/plans/pc.md` and delete `c2/`.\n' > "$REPO/.claude/briefs/mp-builder-brief.md"
check "a plan and a named directory in main's copy still list their deletions" "0 0 0" "$(merge mp) $(left c1) $(left c2)"
mk nc; git -C "$COMMANDECK_WORKSPACES/nc" rm -qr nb && git -C "$COMMANDECK_WORKSPACES/nc" commit -qm "cut nb"; go nc
check "a squash that deletes a file with no brief copy in main is refused naming the copy command" "1 1 2" \
  "$(merge nc) $(grep -c "cp $COMMANDECK_WORKSPACES/nc/.claude/briefs/nc.md $REPO/.claude/briefs/nc-builder-brief.md" "$TMP/out") $(left nb)"
cutdir pl1 $'#### Plan\n\n.claude/plans/pe.md' e5
check "a plan named in plain text under the Plan section lists its deletions" "0 0" "$(merge pl1) $(left e5)"
cutdir pl2 'The plan is .claude/plans/pf.md, read it.' f6
check "a plan only mentioned in prose authorises nothing" "1 2" "$(merge pl2) $(left f6)"
cutdir pl3 'Read `.claude/plans/pg.md` first.' g7
check "a backticked plan path anywhere in the brief still lists its deletions" "0 0" "$(merge pl3) $(left g7)"
cutdir ev1 'Nothing named.' h8/old.js 'h8/old.js'
check "a deletion named only in the evidence's Files deleted list is refused" "1 1 2" \
  "$(merge ev1) $(grep -c "approves nothing on its own" "$TMP/out") $(left h8)"
cutdir ev2 'The plan is `.claude/plans/pi.md`.' i9/old.js 'i9/old.js'
check "a deletion named in the evidence list and in a plan main's brief names is accepted" "0 1" "$(merge ev2) $(left i9)"
cutdir gl1 'Remove `assets/*.js` for good.' assets
check "a deletion matched by a backticked glob in main's copy is accepted" "0 0" "$(merge gl1) $(left assets)"
cutdir gl2 'Remove `*.js`, `*` and `?/x` and `[ab]/x`.' k1
check "a glob with no literal folder approves nothing" "1 2" "$(merge gl2) $(left k1)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
