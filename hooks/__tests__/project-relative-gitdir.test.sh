#!/usr/bin/env bash
# project-relative-gitdir.test.sh -- git can write a worktree's `.git` file
# with a relative path (worktree.useRelativePaths). The path is relative to
# the worktree's root. What this pins: from a subfolder of such a worktree the
# project is still the main checkout, so its commandeck.json switches are read.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

mkdir -p "$T/main/.git/worktrees/wt" "$T/main/.claude" "$T/wt/src/deep"
echo '{"strictHooks": true}' > "$T/main/.claude/commandeck.json"
echo 'gitdir: ../main/.git/worktrees/wt' > "$T/wt/.git"
at() { (cd "$1" && . "$ROOT/hooks/lib/project.sh" && pp_project && echo "$PP_PROJECT $PP_PROJECT_DIR" && pp_flag strictHooks && echo on); }
check "from the worktree's root the project is main" "main $T/main on" "$(at "$T/wt" | paste -sd' ' -)"
check "and from a subfolder of it too" "main $T/main on" "$(at "$T/wt/src/deep" | paste -sd' ' -)"
echo "gitdir: $T/main/.git/worktrees/wt" > "$T/wt/.git"
check "a full path reads as before" "main $T/main on" "$(at "$T/wt/src/deep" | paste -sd' ' -)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
