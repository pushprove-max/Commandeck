#!/usr/bin/env bash
# Used by symbols-before-read.sh's first-edit gate: the refusal names the files
# that use the file's top-level symbols, so the retry needs no lookup turn.

# symbol_outline FILE: top-level names on one line, at most 80, in file order.
# shortcut: a line-anchored regex pass, so a declaration indented inside a
# block or a re-export (`export { a }`) is not listed; upgrade to serena.
symbol_outline() {
  case "$1" in
    *.py) sed -nE -e 's/^(async +)?(def|class) +([A-Za-z_][A-Za-z0-9_]*).*/\3/p' -e 's/^([A-Z][A-Z0-9_]+) *(:[^=]*)?=.*/\1/p' "$1" ;;
    *) sed -nE 's/^(export +)?(default +)?(declare +)?(abstract +)?(async +)?(function\*?|class|interface|type|enum|namespace|const|let|var) +([A-Za-z_$][A-Za-z0-9_$]*).*/\7/p' "$1" ;;
  esac 2>/dev/null | awk '!seen[$0]++' | head -80 | paste -sd' ' -
}

# new_in_branch FILE: true when FILE sits in a linked worktree and is on
# neither base of its branch (the merge base with local main, and with
# origin/main when that exists). Such a file has no callers, so the gate asks
# for no references call first. The base
# decides, never the working tree: a base file deleted and written again is
# still a base file. The path is compared as the disk resolves it (no `..`, no
# link, any letter case, since the Mac's disk folds case), and with no base to
# compare with the answer is no, so a gate keeps refusing rather than guess.
# shortcut: a base file copied or renamed to a new path counts as new; compare
# content with the base if that ever lets real code through unasked.
new_in_branch() {
  local dir top rel ref base tree found=0
  [ -L "$1" ] && return 1
  dir=$(cd "${1%/*}" 2>/dev/null && pwd -P) || return 1
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ "$(git -C "$dir" rev-parse --path-format=absolute --git-dir 2>/dev/null)" != "$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ] || return 1
  case "$dir/" in "$top"/*) ;; *) return 1 ;; esac
  rel="${dir#"$top"}/${1##*/}"; rel=${rel#/}
  for ref in refs/heads/main refs/remotes/origin/main; do
    base=$(git -C "$top" merge-base HEAD "$ref" 2>/dev/null) || continue
    found=1
    # Read whole, then searched: under pipefail a grep that stops early would read as "not found".
    tree=$(git -C "$top" -c core.quotepath=off ls-tree -r --name-only "$base" 2>/dev/null) || return 1
    grep -qixF -- "$rel" <<<"$tree" && return 1
  done
  [ "$found" = 1 ]
}
