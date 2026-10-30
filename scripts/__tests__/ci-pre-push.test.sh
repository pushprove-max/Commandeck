#!/usr/bin/env bash
# ci-pre-push.test.sh -- .githooks/pre-push in a fixture repo with a bare remote and a real `git push` (issue 497). A red
# shell test reached main because nothing ran the suite before the push. What this pins: a push to refs/heads/main runs
# the shell tests on the commit being pushed, in a detached worktree, and a red run refuses the push; a green run lets it
# through; a branch push and a delete of main run nothing. The fixture's own scripts/run-shell-tests.sh stands in for the
# suite: the real one never runs here, and this test needs the hook wired nowhere (the fixture points core.hooksPath at it).
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# mkfix <name> -- $T/<name>/w (the repo, two commits: HEAD~1 red, HEAD green) pushing to the bare $T/<name>/remote.
# The fixture runner logs the commit it ran on to $T/<name>/log and exits with the tracked file `verdict` at that commit,
# so a run on the wrong commit shows in the log and in the verdict, never as a fixed code.
mkfix() {
  local d=$T/$1
  mkdir -p "$d"
  git init -q --bare -b main "$d/remote"
  git -C "$d/remote" config receive.denyDeleteCurrent ignore
  git init -q -b main "$d/w"
  mkdir -p "$d/w/scripts"
  cat > "$d/w/scripts/run-shell-tests.sh" <<EOF
#!/usr/bin/env bash
git rev-parse HEAD >> "$d/log"
exit "\$(git show HEAD:verdict)"
EOF
  git -C "$d/w" config core.hooksPath "$REAL/.githooks"
  git -C "$d/w" remote add origin "$d/remote"
  echo 1 > "$d/w/verdict"; git -C "$d/w" add -A; git -C "$d/w" commit -qm red
  echo 0 > "$d/w/verdict"; git -C "$d/w" commit -qam green
}
# push <name> <refspec> -- a real push, with --git-dir given the way a caller outside the checkout does: Git then
# exports GIT_DIR to the hook, which is what the hook must clear before it enters the other worktree.
push() { (cd "$T/$1/w" && timeout 60 git --git-dir="$PWD/.git" push -q origin "$2" 2>&1); }
remote_main() { git -C "$T/$1/remote" rev-parse -q --verify refs/heads/main 2>/dev/null || echo none; }

# Catches: a push of a red commit to main that nothing refuses (the hook's exit on red removed).
mkfix red
git -C "$T/red/w" reset -q --hard HEAD~1
push red HEAD:refs/heads/main >/dev/null; rc=$?
check "push_refused_on_red_shell_test (the push fails)" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
check "push_refused_on_red_shell_test (main is not created on the remote)" none "$(remote_main red)"
check "push_refused_on_red_shell_test (the output names the refused commit)" 1 \
  "$(push red HEAD:refs/heads/main | grep -c "$(git -C "$T/red/w" rev-parse HEAD)")"

# Catches: the tests run on the wrong commit because Git's variables (GIT_DIR) still point at the pushing repo.
mkfix pushed
red=$(git -C "$T/pushed/w" rev-parse HEAD~1)
push pushed HEAD~1:refs/heads/main >/dev/null; rc=$?
check "push_runs_the_pushed_commit (the red parent is refused though HEAD is green)" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
check "push_runs_the_pushed_commit (the log holds the pushed commit)" "$red" "$(cat "$T/pushed/log" 2>/dev/null)"

# Catches: a green push blocked, or the hook leaving the worktree it added behind.
mkfix green
green=$(git -C "$T/green/w" rev-parse HEAD)
push green HEAD:refs/heads/main >/dev/null; rc=$?
check "green_push_passes: exit code" 0 "$rc"
check "green_push_passes: main is on the remote" "$green" "$(remote_main green)"
check "green_push_passes: the run was on the pushed commit" "$green" "$(cat "$T/green/log" 2>/dev/null)"
check "green_push_passes: no worktree is left behind" 1 "$(git -C "$T/green/w" worktree list | wc -l | tr -d ' ')"

# Catches: the suite run for every push, or for a delete of main, which has no commit to run.
mkfix branch
git -C "$T/branch/w" reset -q --hard HEAD~1
push branch HEAD:refs/heads/feature >/dev/null; rc=$?
check "branch_push_skips_the_run: a red branch push passes" 0 "$rc"
check "branch_push_skips_the_run: the branch is on the remote" "$(git -C "$T/branch/w" rev-parse HEAD)" \
  "$(git -C "$T/branch/remote" rev-parse refs/heads/feature)"
git -C "$T/branch/remote" update-ref refs/heads/main "$(git -C "$T/branch/w" rev-parse HEAD)"
push branch :refs/heads/main >/dev/null; rc=$?
check "branch_push_skips_the_run: a delete of main passes" 0 "$rc"
check "branch_push_skips_the_run: the runner never ran" none "$([ -e "$T/branch/log" ] && echo ran || echo none)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
