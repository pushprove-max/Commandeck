#!/usr/bin/env bash
# Self-test for git-safety.sh: each way to throw work away is refused, wherever
# the git call sits in the command, and ordinary work, the recommended
# --force-with-lease and text that only names a git command pass.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/git-safety.sh"
PASS=0 FAIL=0

check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
cmd() { jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }
# A Builder pane runs this test with COMMANDECK_BUILDER=1 set; the plain cases are the ones outside it.
run() { env -u COMMANDECK_BUILDER bash "$HOOK" >/dev/null 2>&1 <<<"$(cmd "$1")"; echo $?; }
blocks() { for C in "$@"; do check "blocks: $C" 2 "$(run "$C")"; done; }
passes() { for C in "$@"; do check "passes: $C" 0 "$(run "$C")"; done; }

# --- force push and hard reset, wherever the git call sits ---
check "a bare force push blocks"                2 "$(run 'git push --force origin main')"
check "a force push after && blocks"            2 "$(run 'cd /repo && git push --force origin main')"
check "git push -f blocks"                      2 "$(run 'git push -f origin main')"
check "a reset --hard after && blocks"          2 "$(run 'cd /repo && git reset --hard origin/main')"
check "git -C <path> push --force blocks"       2 "$(run 'git -C /home/me/repos/some-project push --force')"
check "git push -u origin <branch> passes"      0 "$(run 'git push -u origin builder/some-unit')"

# --- --force-with-lease is the recommended form and must pass ---
check "--force-with-lease passes"               0 "$(run 'git push --force-with-lease origin main')"
check "the message still recommends the lease form" 0 \
  "$(bash "$HOOK" 2>&1 >/dev/null <<<"$(cmd 'git push --force')" | grep -qF -- '--force-with-lease' && echo 0 || echo 1)"

# --- ordinary work is untouched ---
check "an ordinary push passes"                 0 "$(run 'git push origin main')"
check "a plain status passes"                   0 "$(run 'git status --porcelain')"
check "malformed JSON passes rather than wedging" 0 "$(run 'not json')"

# --- text that names a git command is not one ---
check "a commit message naming a force push passes" 0 \
  "$(run "git commit -m 'never run git push --force here'")"
check "a heredoc commit message naming reset --hard passes" 0 \
  "$(run $'git commit -m "$(cat <<\'EOF\'\nfix: stop using git reset --hard here\nEOF\n)"')"
check "a real force push after a heredoc commit still blocks" 2 \
  "$(run $'git commit -F - <<EOF\nmsg\nEOF\ngit push --force')"

# --- the other ways to discard work ---
blocks 'git checkout -- .' 'git restore .' 'git clean -fdx' 'git stash drop' 'git branch -D feature' \
  'git worktree remove --force /tmp/wt'
passes 'git switch feature' 'git restore --staged src/x.ts' 'git clean -n' 'git stash list' 'git branch -d merged'
# r5 sweep: git takes any unambiguous prefix of a long option, so `--forc` is --force.
blocks 'git worktree remove --forc /tmp/wt' 'git worktree remove --f /tmp/wt' 'git checkout --forc main' 'git switch --disc main' \
  'git clean --forc' 'git branch --del --forc feature' 'git gc --pru=now' 'git restore --staged --work x.ts' \
  'git reset --har' 'git reset --h HEAD~1'
passes 'git reset --help'

# r6 finding: an empty pair of quotes adds nothing to the word bash passes, so `clean""` is still clean.
blocks 'git clean"" -fdx' 'git clean -f""dx' 'git"" clean -fdx' "git restore'' ." 'git stash"" drop' 'git checkout"" -- .'
passes 'git clean"" -n' 'git stash"" list'
# r7 finding: quoting next to quoting is still the one word bash passes.
blocks '"""git" clean -fdx' '""\git clean -fdx' 'git """clean" -fdx' "git ''\"clean\" -fdx" 'git ""\reset --hard'
# --- issue 357, pass 2 (D6): a forced remove passes only a clean worktree, whoever added it (the session grant is gone) ---
# Real worktrees under a scratch TMPDIR. pre/post are the hook calls around each add (post's --record-add flag is now
# ignored: the hook records nothing); "ran" is the command really run between them, as Claude Code does.
WT=$(mktemp -d); export TMPDIR=$WT/tmp COMMANDECK_SCRATCH=$WT/scr; mkdir -p "$TMPDIR" "$COMMANDECK_SCRATCH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q "$WT/repo" && git -C "$WT/repo" commit -q --allow-empty -m init
payload() { jq -cn --arg c "$2" --arg s "$1" --arg d "${PCWD:-$WT/repo}" '{tool_name:"Bash", session_id:$s, cwd:$d, tool_input:{command:$c}}'; }
pre() { bash "$HOOK" >/dev/null 2>&1 <<<"$(payload "$1" "$2")"; echo $?; }
post() { bash "$HOOK" --record-add >/dev/null 2>&1 <<<"$(payload "$1" "$2")"; echo $?; }
add_cmd() { echo "git worktree add $1 HEAD"; }
rm_cmd() { echo "git worktree remove --force $1"; }
# A adds a worktree and puts an uncommitted file in it.
A=$TMPDIR/wt-a; (cd "$WT/repo" && pre sA "$(add_cmd "$A")" >/dev/null && git worktree add -q "$A" HEAD) && post sA "$(add_cmd "$A")" >/dev/null
echo work > "$A/uncommitted.txt"
# Catches (pass 2, D6): ownership excusing a dirty tree, so a forced remove of the session's own tmp worktree deletes
# the work left in it. Owned or not, a forced remove passes only a clean tree.
check "a tmp worktree this session added, holding untracked work: forced remove blocked, the file kept" \
  "2 yes" "$(pre sA "$(rm_cmd "$A")") $([ -f "$A/uncommitted.txt" ] && echo yes || echo no)"
mv "$A/uncommitted.txt" "$WT/aside.txt" # clean now: the issue 357 pass below is for a clean owned tree
check "removing a tmp worktree this session added is allowed" 0 "$(pre sA "$(rm_cmd "$A")")"
mv "$WT/aside.txt" "$A/uncommitted.txt" # dirty again for session B's cases
# B's add on A's path fails (the path exists); B's forced remove of it is then blocked.
(cd "$WT/repo" && pre sB "$(add_cmd "$A")" >/dev/null; git worktree add -q "$A" HEAD 2>/dev/null || true)
post sB "$(add_cmd "$A")" >/dev/null
check "session B's failed add on session A's worktree path, then B's forced remove: blocked, A's worktree and its uncommitted file still there" \
  "2 yes" "$(pre sB "$(rm_cmd "$A")") $([ -f "$A/uncommitted.txt" ] && echo yes || echo no)"
# An add that fails on a missing ref, followed by `; true`, exits 0 and fires PostToolUse: no worktree is at the path.
C=$TMPDIR/wt-c; CC="git worktree add $C no-such-ref; true"
(cd "$WT/repo" && pre sC "$CC" >/dev/null; git worktree add -q "$C" no-such-ref 2>/dev/null || true); post sC "$CC" >/dev/null
check "a failed add followed by \`; true\` grants nothing" 2 "$(pre sC "$(rm_cmd "$C")")"
# PreToolUse alone (the add never succeeded, so no PostToolUse) grants nothing.
D=$TMPDIR/wt-d; pre sD "$(add_cmd "$D")" >/dev/null
check "an add with no PostToolUse (the add failed) grants nothing" 2 "$(pre sD "$(rm_cmd "$D")")"
# No session id, a path outside tmp, and a path another session owns all stay blocked.
check "a forced remove with no session id stays blocked" 2 "$(run "$(rm_cmd "$A")")"
check "forced removal of a worktree the session did not create stays blocked" 2 "$(pre sOther "$(rm_cmd "$A")")"
# (outside /tmp, /private/tmp and TMPDIR: under the home folder)
E=$HOME/.git-safety-test-$$; (cd "$WT/repo" && pre sE "$(add_cmd "$E")" >/dev/null && git worktree add -q "$E" HEAD) && post sE "$(add_cmd "$E")" >/dev/null
SE_CLEAN=$(pre sE "$(rm_cmd "$E")"); echo x > "$E/work.txt"
check "a worktree this session added outside the temporary folder: clean passes, with untracked work it blocks" "0 2" "$SE_CLEAN $(pre sE "$(rm_cmd "$E")")"
rm -f "$E/work.txt"
# r1 findings. A relative path is resolved by git from a folder the hook cannot see (a -C, or a cd earlier in the
# command): it is never owned, even when the session's folder holds a worktree of that name the session owns.
check "a relative path after -C or cd is never owned: both forced removes block" "2 2" \
  "$(PCWD=$TMPDIR pre sA "git -C $TMPDIR/other worktree remove --force wt-a") $(PCWD=$TMPDIR pre sA "cd $TMPDIR/other && git worktree remove --force wt-a")"
# The one-word checkout is looked up where git runs: under -C, that folder, not the session's.
mkdir -p "$WT/co"; echo x > "$WT/co/only-here.txt"
check "git -C <dir> checkout <a file only that folder has> blocks" 2 "$(pre sX "git -C $WT/co checkout only-here.txt")"
rm -rf "$E" "$WT"; unset TMPDIR COMMANDECK_SCRATCH
# Without its strip helper the hook must refuse, not read an empty command.
# --- issue 371: a Builder never commits by hand; the pass script commits what is staged ---
brun() { COMMANDECK_BUILDER=1 bash "$HOOK" 2>&1 >/dev/null <<<"$(cmd "$1")"; }
brc() { COMMANDECK_BUILDER=1 bash "$HOOK" >/dev/null 2>&1 <<<"$(cmd "$1")"; echo $?; }
check "a hand commit in a Builder pane is refused"            2 "$(brc 'git commit -m "wip"')"
check "... after && and with -C <worktree>"                   2 "$(brc 'cd /repo && git -C /wt/unit commit -am wip')"
check "... after --attr-source and its value (git takes it as two words)" 2 "$(brc 'git --attr-source HEAD commit -m wip')"
check "... the refusal says the pass script commits"          1 "$(brun 'git commit -m wip' | grep -c 'builder-codex-pass.sh commits what is staged')"
check "... a model co-author trailer is named in the refusal" 1 \
  "$(brun $'git commit -F - <<EOF\nfix\n\nCo-Authored-By: Claude <noreply@anthropic.com>\nEOF' | grep -c 'model co-author trailer')"
check "... a plain message does not name a trailer"           0 "$(brun 'git commit -m wip' | grep -c 'co-author trailer')"
check "a commit outside a Builder pane passes"                0 "$(run 'git commit -m wip')"
check "the pass script run in a Builder pane passes"          0 "$(brc 'bash scripts/builder-codex-pass.sh u 2 review')"
check "git log naming commit in a Builder pane passes"        0 "$(brc 'git log --grep commit')"
check "a Builder's staging and status calls pass"             0 "$(brc 'git add -A && git status --porcelain')"
LONE=$(mktemp -d); cp "$HOOK" "$LONE/"
check "a missing strip-quoted.sh blocks"        2 \
  "$(bash "$LONE/git-safety.sh" >/dev/null 2>&1 <<<"$(cmd 'git push --force')"; echo $?)"
rm -rf "$LONE"

# --- a forced remove of a worktree with nothing to lose passes; any uncommitted or untracked work still blocks ---
# The owner's rule blocks only on uncommitted work, so `git status --porcelain --untracked-files=all` decides alone.
CW=$(mktemp -d); export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q "$CW/repo" && echo v1 > "$CW/repo/tracked.txt" && git -C "$CW/repo" add tracked.txt && git -C "$CW/repo" commit -q -m init
for N in clean untracked modified; do git -C "$CW/repo" worktree add -q "$CW/wt-$N" HEAD; done
check "a clean worktree remove --force passes" 0 "$(run "git worktree remove --force $CW/wt-clean")"
echo scratch > "$CW/wt-untracked/new.txt"
echo v2 > "$CW/wt-modified/tracked.txt"
check "a worktree with uncommitted or untracked work still blocks: an untracked file" 2 "$(run "git worktree remove --force $CW/wt-untracked")"
check "a worktree with uncommitted or untracked work still blocks: a modified file" 2 "$(run "git worktree remove --force $CW/wt-modified")"
check "a worktree with uncommitted or untracked work still blocks" "2 2" \
  "$(run "git worktree remove --force $CW/wt-untracked") $(run "git worktree remove --force $CW/wt-modified")"
check "a worktree with uncommitted or untracked work still blocks: a missing path" 2 "$(run "git worktree remove --force $CW/wt-missing")"
check "a worktree with uncommitted or untracked work still blocks: a git failure (not a repository)" 2 "$(run "git worktree remove --force $CW")"

# D63: status never shows an edit to a file marked assume-unchanged or skip-worktree, so a forced remove of such a tree
# would delete the edit unseen. ls-files -v tags those files lowercase or S; either one is work to lose.
for N in assume skip; do git -C "$CW/repo" worktree add -q "$CW/wt-$N" HEAD; echo hidden > "$CW/wt-$N/tracked.txt"; done
git -C "$CW/wt-assume" update-index --assume-unchanged tracked.txt
git -C "$CW/wt-skip" update-index --skip-worktree tracked.txt
check "a force remove of a worktree with an assume-unchanged edit is blocked" 2 "$(run "git worktree remove --force $CW/wt-assume")"
check "a force remove of a worktree with a skip-worktree edit is blocked" 2 "$(run "git worktree remove --force $CW/wt-skip")"
rm -rf "$CW"

# Issue 629 (D18): a scratch copy is throwaway, so a forced remove of one strictly under the scratch root passes dirty, in
# the fixed-list form only. A path that climbs out with .., a symlink out, the root itself, or a dirty tree elsewhere blocks.
SC=$(cd "$(mktemp -d)" && pwd -P)
git init -q "$SC/repo" && echo v1 > "$SC/repo/tracked.txt" && git -C "$SC/repo" add tracked.txt && git -C "$SC/repo" commit -q -m init
mkdir -p "$SC/scratch"; for N in scratch/wt out; do git -C "$SC/repo" worktree add -q "$SC/$N" HEAD; echo dirty > "$SC/$N/new.txt"; done
ln -s "$SC/out" "$SC/scratch/link"
sr() { COMMANDECK_SCRATCH="$SC/scratch" run "$1"; }
check "a forced remove of a dirty worktree outside the scratch root is blocked" 2 "$(sr "git worktree remove --force $SC/out")"
check "a forced remove whose path climbs out of the scratch root with .. is blocked" 2 "$(sr "git worktree remove --force $SC/scratch/../out")"
check "a forced remove through a symlink out of the scratch root is blocked" 2 "$(sr "git worktree remove --force $SC/scratch/link")"
check "a forced remove of the scratch root itself is blocked" 2 "$(sr "git worktree remove --force $SC/scratch")"
check "a forced remove under the scratch root beside a second command is blocked" 2 "$(sr "git worktree remove --force $SC/scratch/wt; echo")"
check "a forced remove of a dirty worktree under the scratch root passes" 0 "$(sr "git worktree remove --force $SC/scratch/wt")"
rm -rf "$SC"

# --- D64: checkout/restore --ours|--theirs passes when every path is unmerged where the call runs ---
# A merge left f.txt unmerged; other.txt is clean. The paths are the words after `--`, and for restore with no `--` its plain words.
CF=$(mktemp -d); git init -q -b main "$CF" && printf 'a\n' > "$CF/f.txt" && printf 'o\n' > "$CF/other.txt" && git -C "$CF" add . && git -C "$CF" commit -q -m init
git -C "$CF" checkout -q -b side && printf 'side\n' > "$CF/f.txt" && git -C "$CF" commit -q -am side
git -C "$CF" checkout -q main && printf 'main\n' > "$CF/f.txt" && git -C "$CF" commit -q -am main
git -C "$CF" merge side >/dev/null 2>&1
check "checkout --ours of an unmerged path passes" 0 "$(run "git -C $CF checkout --ours -- f.txt")"
check "checkout --theirs of a path that is not unmerged is blocked" 2 "$(run "git -C $CF checkout --theirs -- other.txt")"
# -C makes f.txt unmerged where the call runs, so only the --git-dir flag can block it.
check "restore --ours with --git-dir is blocked" 2 "$(run "git -C $CF --git-dir $CF/.git restore --ours -- f.txt")"
check "restore --theirs of an unmerged path without -- passes" 0 "$(run "git -C $CF restore --theirs f.txt")"
rm -rf "$CF"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
