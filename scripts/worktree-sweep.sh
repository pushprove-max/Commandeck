#!/usr/bin/env bash
# worktree-sweep.sh -- remove this checkout's idle helper worktrees (<main>/.claude/worktrees/) and scratch worktrees
# (under the scratch folder), one `removed <path>` line each, with `kept <path>: <reason>` for each one it leaves.
#
# Issue 591: copies left by a missed removal piled up, about 70 in three days. A worktree goes only when it is clean
# (no status line and no assume-unchanged or skip-worktree file, the rule git-safety.sh wt_clean reads: status hides
# those files' edits, and a plain remove deletes them), no process works in it, and its index and HEAD log are over
# 24 h old. It is removed with `git worktree remove`, never --force. Its branch is deleted with `git branch -d` only when
# the tip is in main; an unmerged branch stays, the durable reference to its commits, and a detached HEAD not in main
# keeps the worktree. The in-use check is one `lsof -a -d cwd -Fn`: an lsof that fails or names no working directory
# keeps every candidate. main-watch.sh runs this at most once an hour. Exit 1 when a removal failed.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh" || exit 1
NOW=$(date +%s)
SCR=$(cd "$PP_SCRATCH" 2>/dev/null && pwd -P) || SCR=$PP_SCRATCH
CWDS=$(lsof -a -d cwd -Fn 2>/dev/null); LRC=$?
LSOF_OK=0; [ "$LRC" != 0 ] || ! grep -q '^n' <<<"$CWDS" || LSOF_OK=1
# in_use <dir> -- a process's working directory is <dir> or under it.
in_use() { awk -v p="$1" 'substr($0, 1, 1) == "n" { d = substr($0, 2); if (d == p || index(d, p "/") == 1) { f = 1; exit } } END { exit !f }' <<<"$CWDS"; }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
clean() {
  local o; o=$(git -C "$1" ls-files -v 2>/dev/null) || return 1
  [[ $o =~ (^|$'\n')[a-zS]\  ]] && return 1
  o=$(git -C "$1" status --porcelain --untracked-files=all 2>/dev/null) && [ -z "$o" ]
}
in_main() { git -C "$PP_MAIN" merge-base --is-ancestor "$1" refs/heads/main 2>/dev/null; }
rc=0
while IFS=$'\t' read -r wt head br; do
  c=$(cd "$wt" 2>/dev/null && pwd -P) || continue # a folder already gone is `git worktree prune`'s
  case $c/ in "$PP_MAIN_P"/.claude/worktrees/*|"$SCR"/*) ;; *) continue ;; esac
  [ "$LSOF_OK" = 1 ] || { echo "kept $c: lsof failed (exit $LRC) or named no working directory"; continue; }
  gd=$(git -C "$c" rev-parse --absolute-git-dir 2>/dev/null) || { echo "kept $c: its git folder cannot be read"; continue; }
  # The age is read before status, which may rewrite the index.
  t=$(mtime "$gd/index") || { echo "kept $c: no index"; continue; }
  h=$(mtime "$gd/logs/HEAD") || h=0
  [ "$t" -le $((NOW - 86400)) ] && [ "$h" -le $((NOW - 86400)) ] || { echo "kept $c: touched under 24 h ago"; continue; }
  ! in_use "$c" || { echo "kept $c: a process works in it"; continue; }
  clean "$c" || { echo "kept $c: not clean (a status line, an assume-unchanged or skip-worktree file, or an unreadable index)"; continue; }
  [ -n "$br" ] || in_main "$head" || { echo "kept $c: detached at $head, not in main"; continue; }
  if out=$(git -C "$PP_MAIN" worktree remove "$c" 2>&1); then echo "removed $c"
  else echo "kept $c: git worktree remove failed: $(tail -n 1 <<<"$out")"; rc=1; continue; fi
  [ -n "$br" ] || continue
  if in_main "$head"; then
    git -C "$PP_MAIN" branch -d "$br" >/dev/null 2>&1 && echo "deleted branch $br" || echo "kept branch $br $head: git branch -d refused"
  else echo "kept branch $br $head: not in main"; fi
done < <(git -C "$PP_MAIN" worktree list --porcelain 2>/dev/null | awk '
  /^worktree / { w = substr($0, 10); h = ""; b = "" }
  /^HEAD / { h = $2 }
  /^branch / { b = substr($2, 12) }
  /^$/ { if (w != "") print w "\t" h "\t" b; w = "" }
  END { if (w != "") print w "\t" h "\t" b }')
exit "$rc"
