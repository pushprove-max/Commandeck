#!/usr/bin/env bash
# Helper copies under <main>/.claude/worktrees/ and scratch copies under the scratch folder piled up when a removal was
# missed: about 70 in three days (issue 591). Pinned: worktree-sweep.sh removes one only when it is clean (no status
# line, no assume-unchanged or skip-worktree file), no process works in it, and its index and HEAD log are over 24 h old;
# it never forces, and deletes a branch only when its tip is in main. An unmerged branch, or a detached commit not in
# main, keeps its work. An lsof that fails keeps everything.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/scratch" "$T/home"
P=$T/p W=$T/p/.claude/worktrees
g() { git -c user.name=t -c user.email=t@t "$@"; }
git init -q -b main "$P" && echo one > "$P/a.txt" && g -C "$P" add a.txt && g -C "$P" commit -q -m first
# lsof stand-in: $T/lsof-out is its output; $T/lsof-fail makes it exit 1.
printf '#!/usr/bin/env bash\n[ ! -e %q ] || exit 1\ncat %q\n' "$T/lsof-fail" "$T/lsof-out" > "$T/bin/lsof"; chmod +x "$T/bin/lsof"
printf 'p1\nn/\n' > "$T/lsof-out"
# stale <worktree> -- its index and HEAD log two days old.
stale() { local d; d=$(git -C "$1" rev-parse --absolute-git-dir); touch -d '2 days ago' "$d/index" "$d/logs/HEAD"; }
add() { g -C "$P" worktree add -q "$@"; }
add -b h1 "$W/h1"                                  # clean, branch at main's tip
add -b h2 "$W/h2"; echo two > "$W/h2/b.txt"; g -C "$W/h2" add b.txt; g -C "$W/h2" commit -q -m ahead  # a branch not in main
add --detach "$W/h3"; echo three > "$W/h3/c.txt"; g -C "$W/h3" add c.txt; g -C "$W/h3" commit -q -m loose  # detached, not in main
add -b h4 "$W/h4"; printf 'p1\nn/\np2\nn%s/sub\n' "$W/h4" > "$T/lsof-out"   # a process works in it
add -b h6 "$W/h6"; echo junk > "$W/h6/new.txt"     # untracked file
add -b h7 "$W/h7"; g -C "$W/h7" update-index --assume-unchanged a.txt; echo edit > "$W/h7/a.txt"
add -b h8 "$W/h8"; g -C "$W/h8" update-index --skip-worktree a.txt; echo edit > "$W/h8/a.txt"
add -b h9 "$W/h9"
add -b h10 "$W/h10"                                 # touched now
add --detach "$T/scratch/s1"                       # a scratch copy at main's tip
for w in h1 h2 h3 h4 h6 h7 h8 h9; do stale "$W/$w"; done; stale "$T/scratch/s1"
D9=$(git -C "$W/h9" rev-parse --absolute-git-dir); printf 'not an index' > "$D9/index"; touch -d '2 days ago' "$D9/index"
sweep() { (cd "$P" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$P" COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_WORKSPACES="$T/ws" \
  PATH="$T/bin:$PATH" bash "$REAL/scripts/worktree-sweep.sh" 2>&1); }
OUT=$(sweep); RC=$?
has() { [ -d "$1" ] && echo kept || echo gone; }
br() { git -C "$P" rev-parse -q --verify "refs/heads/$1" >/dev/null && echo branch || echo nobranch; }
check "an idle clean helper worktree older than 24 hours is removed and reported" "0 gone nobranch 1" \
  "$RC $(has "$W/h1") $(br h1) $(grep -cx "removed $W/h1" <<<"$OUT")"
check "a stale clean helper worktree whose branch is not in main is removed and its branch kept" "gone branch 1" \
  "$(has "$W/h2") $(br h2) $(grep -cx "kept branch h2 $(git -C "$P" rev-parse h2): not in main" <<<"$OUT")"
check "a stale helper worktree detached at a commit not in main is kept" "kept 1" "$(has "$W/h3") $(grep -c "^kept $W/h3: " <<<"$OUT")"
check "a helper worktree a live process uses is kept" "kept 1" "$(has "$W/h4") $(grep -c "^kept $W/h4: " <<<"$OUT")"
check "a helper worktree with uncommitted files is kept" "kept junk" "$(has "$W/h6") $(cat "$W/h6/new.txt")"
check "a stale helper worktree with an assume-unchanged edit is kept" "kept edit" "$(has "$W/h7") $(cat "$W/h7/a.txt")"
check "a stale helper worktree with a skip-worktree edit is kept" "kept edit" "$(has "$W/h8") $(cat "$W/h8/a.txt")"
check "a stale helper worktree whose index cannot be read is kept" "kept 1" "$(has "$W/h9") $(grep -c "^kept $W/h9: " <<<"$OUT")"
check "a helper worktree touched under 24 hours ago is kept" "kept 1" "$(has "$W/h10") $(grep -c "^kept $W/h10: touched under 24 h ago" <<<"$OUT")"
check "a stale scratch worktree under the scratch folder is removed" "gone 1" "$(has "$T/scratch/s1") $(grep -cx "removed $T/scratch/s1" <<<"$OUT")"
check "the main checkout itself is never a candidate" "kept 0" "$(has "$P") $(grep -c "$P:\|$P\$" <<<"$OUT")"
add -b h11 "$W/h11"; stale "$W/h11"; touch "$T/lsof-fail"
OUT=$(sweep)
check "a stale clean helper worktree is kept when lsof fails" "kept 1" \
  "$(has "$W/h11") $(grep -cx "kept $W/h11: lsof failed (exit 1) or named no working directory" <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
