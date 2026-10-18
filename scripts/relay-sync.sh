#!/usr/bin/env bash
# relay-sync.sh [--rebase] -- is the relay (Chief of Staff) worktree behind the project's main, and bring it current.
# No flag only reads, and prints one line: `relay: none`, `relay: current` or `relay: <n> commits behind main`.
# --rebase runs `git rebase main` in the relay worktree. It refuses, changing nothing, when the worktree has
# uncommitted changes or a rebase already under way, and aborts a rebase that conflicts. The base is local main, not a fetched remote: the plugin
# merges locally and never pushes, so local main is where the relay's hooks and rules come from.
# Setup and update ask the owner before they pass --rebase: the relay pane may be running.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
case ${1:-} in ''|--rebase) ;; *) echo "usage: relay-sync.sh [--rebase]" >&2; exit 2 ;; esac
R=$PP_WORKSPACES/Chief-of-Staff
[ -e "$R/.git" ] || { echo "relay: none"; exit 0; }
N=$(git -C "$R" rev-list --count HEAD..main) || { echo "relay: cannot compare $R with main" >&2; exit 1; }
[ "$N" -gt 0 ] || { echo "relay: current"; exit 0; }
[ "${1:-}" = --rebase ] || { echo "relay: $N commit$([ "$N" = 1 ] || echo s) behind main"; exit 0; }
[ -z "$(git -C "$R" status --porcelain --untracked-files=no)" ] \
  || { echo "relay: not rebased: $R has uncommitted changes. Commit or discard them, then ask again."; exit 1; }
GD=$(git -C "$R" rev-parse --absolute-git-dir) || { echo "relay: cannot read the git dir of $R" >&2; exit 1; }
# A rebase already under way is the owner's: starting another fails, and the --abort below would cancel theirs.
{ [ -e "$GD/rebase-merge" ] || [ -e "$GD/rebase-apply" ]; } \
  && { echo "relay: not rebased: $R is in the middle of a rebase. Finish or abort it, then ask again."; exit 1; }
git -C "$R" rebase main >/dev/null 2>&1 \
  || { git -C "$R" rebase --abort >/dev/null 2>&1; echo "relay: not rebased: its own commits conflict with main, so the rebase was undone. Rebase $R by hand."; exit 1; }
echo "relay: rebased onto main"
