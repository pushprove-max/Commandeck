#!/usr/bin/env bash
# commit-hook-edits.sh <unit> [message] [new-path...] -- commit the tracked edits
# a post-edit hook left behind in a converged unit worktree, so
# merge-unit-local.sh's clean-tree precondition can pass.
#
# Why: a lint-fix hook can rewrite a file AFTER the loop's round commit lands,
# and a worker never commits (the commit guard refuses it), so the edit strands
# and the local merge refuses. Main is barred from touching a worker worktree
# directly; a helper under scripts/ is the sanctioned door, and it keeps the
# operation narrow. Retire this only when no post-edit hook can rewrite a file
# after the round commit AND every seat runs under a loop that commits for it
# (see the hand-launched case below).
#
# Narrow on purpose: tracked modifications only, plus any new path main names.
# A hand-launched seat has no loop to commit for it, and the worktree guard
# blocks main's own `git -C <wt> commit`, so this is main's commit door too.
# The worktree is $PP_WORKSPACES/<unit> (scripts/paths.sh).
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "${0}"; exit 0 ;; esac
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
UNIT=${1:?usage: commit-hook-edits.sh <unit> [message] [new-path...]}
MSG=${2:-"fix($UNIT): apply the post-edit hook's corrections"}
shift $(( $# < 2 ? $# : 2 ))
WT=$PP_WORKSPACES/$UNIT
[ -d "$WT/.git" ] || [ -f "$WT/.git" ] || { echo "no worktree at $WT" >&2; exit 2; }

git -C "$WT" add -u
[ $# -eq 0 ] || git -C "$WT" add -- "$@"
# `add -u` stages tracked paths only, so a brand-new deliverable -- an evidence
# file, a report -- is silently left behind while the script still says
# `committed`. Refuse instead, and name the files so main can add them or
# remove them.
# The loop's own `.claude/briefs/<unit>*` files (reports .md, verdicts .json,
# class-site lists .txt) are always untracked in a live unit and never
# committed, so they alone do not refuse.
UNTRACKED=$(git -C "$WT" ls-files --others --exclude-standard | while IFS= read -r p; do
  case "$p" in (".claude/briefs/$UNIT"*) ;; (*) printf '%s\n' "$p" ;; esac
done)
[ -z "$UNTRACKED" ] || {
  printf 'untracked files in %s -- name them as arguments or remove them:\n%s\n' "$UNIT" "$UNTRACKED" >&2
  exit 3
}
git -C "$WT" diff --cached --quiet && { echo "nothing staged in $UNIT"; exit 0; }
echo "staging:"; git -C "$WT" diff --cached --stat
# The commit guard refuses any commit made in a linked checkout, because a
# worker must return a diff and never publish. This helper is the integrator
# acting on a converged unit, which is the case the documented override exists
# for.
COMMANDECK_ALLOW_AGENT_GIT=1 git -C "$WT" commit -q -m "$MSG"
echo "committed $(git -C "$WT" rev-parse --short HEAD)"
git -C "$WT" status --porcelain | grep -v '^??' && { echo "worktree still has tracked changes" >&2; exit 1; } || true
