#!/usr/bin/env bash
# The contract of git-safety.sh's discard checks: no command the hook blocked
# before this batch passes now. Each probe goes through the earlier hook
# (fixtures/git-safety-before) and through this one.
# The probes: every one-line command of git-safety.test.sh, and the forms five
# review passes found.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PASS=0 FAIL=0
run() { bash "$1" >/dev/null 2>&1 <<<"$(jq -cn --arg c "$2" '{tool_name:"Bash", tool_input:{command:$c}}')"; echo $?; }
N=0 WAS=0
while IFS= read -r probe; do
  [ -n "$probe" ] || continue
  N=$((N+1))
  [ "$(run "$HERE/fixtures/git-safety-before/git-safety.sh" "$probe")" = 2 ] || continue
  WAS=$((WAS+1))
  if [ "$(run "$HERE/../git-safety.sh" "$probe")" = 2 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL blocked before, passes now: $probe"; fi
done < <(grep -oE "run '[^']+'" "$HERE/git-safety.test.sh" | sed -E "s/^run '//; s/'\$//"; cat <<'PROBES'
"git" "reset" --hard
FOO=1 "git" "reset" --hard
env "git" clean -fdx
env -u git "git" reset --hard
sudo -u git "git" clean -fdx
echo "`git reset --hard`"
echo `git reset --hard`
echo "$(git reset --hard)"
echo "`echo "`printf x`"`"; git reset --hard
echo "`echo "`printf x`"`"; git clean -fdx
echo "`echo "`printf x`"`"; git restore .
git reset --hard
git -C /repo clean -fdx
cd /repo && git checkout -- .
git stash drop
git restore .
git branch -D topic
git worktree remove --force /x
git push --force origin main
PROBES
)
# The list is worth nothing if it is not read, or if the earlier hook blocks none of it.
[ "$N" -ge 80 ] && [ "$WAS" -ge 20 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL $N probes read, $WAS blocked by the earlier hook: too few to prove anything"; }
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
