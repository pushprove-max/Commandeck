#!/usr/bin/env bash
# reviewed-tree.sh <worktree> <unit> -- is the worktree still the tree its
# newest Codex pass read? Prints one word:
#   true   HEAD is the `Reviewed:` commit of the unit's newest round file and
#          nothing is uncommitted outside .claude/briefs/ (the brief files are
#          what a pass leaves out of its commit: builder-codex-pass.sh)
#   false  HEAD has moved past that commit, or a runtime file is uncommitted
#   null   not known: no worktree, no round file, no Reviewed line, or git failed
# The dashboard's step strip and the build review both say "ready to merge" and
# "skipped, unchanged" from this one fact. It is a display's fact: the merge
# itself proves the tip with builder-codex-pass.sh --verify.
set -uo pipefail
WT=${1:?worktree} UNIT=${2:?unit}
newest=$(for f in "$WT/.claude/briefs/$UNIT-r"[0-9]*-reports.md; do
  n=${f##*/}; n=${n#"$UNIT-r"}; n=${n%-reports.md}
  [[ $n =~ ^[0-9]+$ ]] && [ -e "$f" ] && echo "$((10#$n)) $f"
done | sort -n | tail -1 | cut -d' ' -f2-)
[ -n "$newest" ] || { echo null; exit 0; }
# The header only, up to its first empty line: below it is Codex's own text.
read=$(sed -n '/^$/q; s/^Reviewed: \([0-9a-f]\{40,64\}\)$/\1/p' "$newest" | head -1)
head=$(git -C "$WT" rev-parse -q --verify HEAD 2>/dev/null) && dirty=$(git -C "$WT" status --porcelain -- . ':(exclude).claude/briefs' 2>/dev/null) \
  && [ -n "$read" ] || { echo null; exit 0; }
[ "$head" = "$read" ] && [ -z "$dirty" ] && echo true || echo false
