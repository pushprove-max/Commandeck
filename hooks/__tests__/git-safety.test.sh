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
# --- issue 357: a forced remove is allowed only for a temporary worktree this session added on an absent path ---
# Real worktrees under a scratch TMPDIR. pre/post are the PreToolUse and PostToolUse (--record-add) calls of one
# session; "ran" is the command really run between them, as Claude Code does.
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
check "removing a tmp worktree this session added is allowed" 0 "$(pre sA "$(rm_cmd "$A")")"
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
check "a worktree this session added outside the temporary folder is not owned" 2 "$(pre sE "$(rm_cmd "$E")")"
# r1 findings. A relative path is resolved by git from a folder the hook cannot see (a -C, or a cd earlier in the
# command): it is never owned, even when the session's folder holds a worktree of that name the session owns.
check "a relative path after -C or cd is never owned: both forced removes block" "2 2" \
  "$(PCWD=$TMPDIR pre sA "git -C $TMPDIR/other worktree remove --force wt-a") $(PCWD=$TMPDIR pre sA "cd $TMPDIR/other && git worktree remove --force wt-a")"
# Every ownership ordering the review passes found, in order (class stale-worktree-owner). Ownership is proved only
# by one add: its own success, which PostToolUse shows only for a command on the fixed list, and the claim its
# PreToolUse wrote beside the absent path, which no later hooked add of the path has replaced.
# 1 (pass 1) a reused path: A adds and removes P; B adds a new worktree at P and leaves work in it.
P=$TMPDIR/wt-p
(cd "$WT/repo" && pre sA "$(add_cmd "$P")" >/dev/null && git worktree add -q "$P" HEAD) && post sA "$(add_cmd "$P")" >/dev/null
git -C "$WT/repo" worktree remove "$P"
(cd "$WT/repo" && pre sB "$(add_cmd "$P")" >/dev/null && git worktree add -q "$P" HEAD) && post sB "$(add_cmd "$P")" >/dev/null
echo b > "$P/b.txt"
S1="$(pre sA "$(rm_cmd "$P")") $(pre sB "$(rm_cmd "$P")")"
# 2 (pass 1) a failed add on a held path: A's add of Q fails (B's worktree is there), so no PostToolUse fires.
Q=$TMPDIR/wt-q
(cd "$WT/repo" && pre sB "$(add_cmd "$Q")" >/dev/null && git worktree add -q "$Q" HEAD) && post sB "$(add_cmd "$Q")" >/dev/null
(cd "$WT/repo" && pre sA "$(add_cmd "$Q")" >/dev/null; git worktree add -q "$Q" HEAD 2>/dev/null)
S2=$(pre sA "$(rm_cmd "$Q")")
# 3 (pass 2) concurrent adds: both PreToolUse calls see R absent; B's plain add wins; A's `add; true` fails but exits
# 0, and A's PostToolUse runs first. B then leaves work in R.
R=$TMPDIR/wt-r; RR="$(add_cmd "$R"); true"
pre sA "$RR" >/dev/null; pre sB "$(add_cmd "$R")" >/dev/null
git -C "$WT/repo" worktree add -q "$R" HEAD; (cd "$WT/repo" && git worktree add -q "$R" HEAD 2>/dev/null; true)
post sA "$RR" >/dev/null; post sB "$(add_cmd "$R")" >/dev/null
echo b > "$R/b.txt"
S3="$(pre sA "$(rm_cmd "$R")") $(pre sB "$(rm_cmd "$R")") $([ -f "$R/b.txt" ] && echo kept || echo lost)"
# 4 (pass 2 sweep) a chained remove: B owns R, but another call before or after the remove could change the path.
S4="$(pre sB "git worktree list; $(rm_cmd "$R")") $(pre sB "$(rm_cmd "$R") && true")"
# 5 the retry: the grant, the one piece of ownership state, is deleted between A's add and its remove. The forced
# remove blocks and names the plain remove, which the hook lets through and git carries out on a clean worktree.
U=$TMPDIR/wt-u
(cd "$WT/repo" && pre sA "$(add_cmd "$U")" >/dev/null && git worktree add -q "$U" HEAD) && post sA "$(add_cmd "$U")" >/dev/null
rm -f "$(git -C "$U" rev-parse --path-format=absolute --git-dir)/commandeck-owner"
MSG=$(bash "$HOOK" 2>&1 >/dev/null <<<"$(payload sA "$(rm_cmd "$U")")"); RC=$?
S5="$RC $(grep -qF 'git worktree remove <path>' <<<"$MSG" && echo named || echo unnamed) $(pre sA "git worktree remove $U")"
git -C "$WT/repo" worktree remove "$U" 2>/dev/null; S5="$S5 $([ -e "$U" ] && echo there || echo gone)"
# 6 (pass 4) a late record step: A's add of V succeeds, but its PostToolUse waits while the clean worktree is removed
# and B re-adds V and leaves work in it; then A's record step runs, then B's.
V=$TMPDIR/wt-v
(cd "$WT/repo" && pre sA "$(add_cmd "$V")" >/dev/null && git worktree add -q "$V" HEAD)
git -C "$WT/repo" worktree remove "$V"
(cd "$WT/repo" && pre sB "$(add_cmd "$V")" >/dev/null && git worktree add -q "$V" HEAD); echo b > "$V/b.txt"
post sA "$(add_cmd "$V")" >/dev/null; post sB "$(add_cmd "$V")" >/dev/null
S6="$(pre sA "$(rm_cmd "$V")") $(pre sB "$(rm_cmd "$V")") $([ -f "$V/b.txt" ] && echo kept || echo lost)"
# 7 (pass 4 sweep) an add that adds nothing: B's worktree at X has no grant (B's add was chained); A's
# `git --version worktree add X HEAD` exits 0 and adds nothing, through both hooks.
X=$TMPDIR/wt-x; XB="$(add_cmd "$X") && true" XA="git --version worktree add $X HEAD"
(cd "$WT/repo" && pre sB "$XB" >/dev/null && git worktree add -q "$X" HEAD) && post sB "$XB" >/dev/null
pre sA "$XA" >/dev/null; git --version >/dev/null; post sA "$XA" >/dev/null
S7=$(pre sA "$(rm_cmd "$X")")
# 8 the retry, for the claim: deleted between A's PreToolUse and its record step. No grant; the forced remove blocks
# and names the plain remove, which runs.
Y=$TMPDIR/wt-y
(cd "$WT/repo" && pre sA "$(add_cmd "$Y")" >/dev/null && git worktree add -q "$Y" HEAD)
rm -f "$TMPDIR/.commandeck-add.wt-y"; post sA "$(add_cmd "$Y")" >/dev/null
MSG=$(bash "$HOOK" 2>&1 >/dev/null <<<"$(payload sA "$(rm_cmd "$Y")")"); RC=$?
S8="$RC $(grep -qF 'git worktree remove <path>' <<<"$MSG" && echo named || echo unnamed) $(pre sA "git worktree remove $Y")"
git -C "$WT/repo" worktree remove "$Y" 2>/dev/null; S8="$S8 $([ -e "$Y" ] && echo there || echo gone)"
check "every ownership ordering found so far, in order: reused path, failed add on a held path, concurrent adds with a masked failure, chained remove, lost grant retried by a plain remove, late record step, an add that adds nothing, lost claim retried by a plain remove" \
  "2 0|2|2 0 kept|2 2|2 named 0 gone|2 0 kept|2|2 named 0 gone" "$S1|$S2|$S3|$S4|$S5|$S6|$S7|$S8"
check "the claim is written beside the absent path by its add, and B's add on A's existing path leaves A's claim" sA \
  "$(cat "$TMPDIR/.commandeck-add.wt-a" 2>/dev/null)"
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
check "--record-add never blocks, even on a Builder commit"   0 \
  "$(COMMANDECK_BUILDER=1 bash "$HOOK" --record-add >/dev/null 2>&1 <<<"$(cmd 'git commit -m wip')"; echo $?)"
LONE=$(mktemp -d); cp "$HOOK" "$LONE/"
check "a missing strip-quoted.sh blocks"        2 \
  "$(bash "$LONE/git-safety.sh" >/dev/null 2>&1 <<<"$(cmd 'git push --force')"; echo $?)"
rm -rf "$LONE"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
