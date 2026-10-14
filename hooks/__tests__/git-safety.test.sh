#!/usr/bin/env bash
# Self-test for git-safety.sh: each way to throw work away is refused, wherever
# the git call sits in the command, and ordinary work, the recommended
# --force-with-lease and text that only names a git command pass.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/git-safety.sh"
PASS=0 FAIL=0

check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
cmd() { jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }
run() { bash "$HOOK" >/dev/null 2>&1 <<<"$(cmd "$1")"; echo $?; }
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

# Without its strip helper the hook must refuse, not read an empty command.
LONE=$(mktemp -d); cp "$HOOK" "$LONE/"
check "a missing strip-quoted.sh blocks"        2 \
  "$(bash "$LONE/git-safety.sh" >/dev/null 2>&1 <<<"$(cmd 'git push --force')"; echo $?)"
rm -rf "$LONE"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
