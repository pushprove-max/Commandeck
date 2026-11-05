#!/usr/bin/env bash
# helper-apply.sh <child-worktree> -- apply a helper's whole delta (its commits since the fork, its uncommitted edits and
# its untracked files) to the current checkout, then remove the helper's worktree and branch. Prints `applied <path>`, or
# one `REFUSED: <why>` line and removes nothing.
#
# Issue 591: helper worktrees were left after their diff was applied, about 70 in three days; the sweep
# (worktree-sweep.sh) removes only what is over 24 hours old, so the removal is tied to the apply here. It uses --force
# because the work is now in this checkout, and only after every changed path's bytes are proven equal in both. Refused:
# a path outside <main>/.claude/worktrees/ and the scratch folder; one a live process works in; a staged path whose
# working tree differs (the delta would drop the staged bytes); an assume-unchanged or skip-worktree path (git diff hides
# its edits); an ignored file the parent lacks or holds other bytes of (--force would delete it); a diff that does not apply.
case ${1-} in -h|--help|"") sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; [ -n "${1-}" ]; exit $? ;; esac
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh" || exit 1
no() { echo "REFUSED: $1; nothing removed"; exit 1; }
SCR=$(cd "$PP_SCRATCH" 2>/dev/null && pwd -P) || SCR=$PP_SCRATCH
C=$(cd "$1" 2>/dev/null && pwd -P) || no "$1 is not a folder"
case $C/ in "$PP_MAIN_P"/.claude/worktrees/?*|"$SCR"/?*) ;; *) no "$C is not under $PP_MAIN_P/.claude/worktrees/ or the scratch folder" ;; esac
# The same in-use test as worktree-sweep.sh: an lsof that fails or names no working directory refuses.
CWDS=$(lsof -a -d cwd -Fn 2>/dev/null); LRC=$?
[ "$LRC" = 0 ] && grep -q '^n' <<<"$CWDS" || no "lsof failed (exit $LRC) or named no working directory, so a live process in $C cannot be ruled out"
! awk -v p="$C" 'substr($0, 1, 1) == "n" { d = substr($0, 2); if (d == p || index(d, p "/") == 1) { f = 1; exit } } END { exit !f }' <<<"$CWDS" \
  || no "a process works in $C"
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || no "the current folder is not a git checkout"
[ "$(cd "$TOP" && pwd -P)" != "$C" ] || no "$C is the current checkout"
BR=$(git -C "$C" symbolic-ref -q --short HEAD) || BR=
B=$(git merge-base HEAD "$(git -C "$C" rev-parse HEAD)") || no "$C shares no history with this checkout"
p=$(git -C "$C" ls-files -v | awk '/^([a-z]|S) / { print substr($0, 3); exit }')
[ -z "$p" ] || no "$p is marked assume-unchanged or skip-worktree"
p=$(comm -12 <(git -C "$C" diff --cached --name-only | sort) <(git -C "$C" diff --name-only | sort) | head -1)
[ -z "$p" ] || no "$p has staged content that differs from its working tree"
# same <a> <b>: one path is equal in both; a symlink is a link to the same target in both (pass 4: cp -p and
# hash-object follow a link, so a link applied as the bytes it points at passed the proof and was lost).
same() {
  if [ -L "$1" ] || [ -L "$2" ]; then [ -L "$1" ] && [ -L "$2" ] && [ "$(readlink "$1")" = "$(readlink "$2")" ]
  else [ -f "$1" ] && [ -f "$2" ] && [ "$(git hash-object "$1")" = "$(git hash-object "$2")" ]; fi
}
absent() { [ ! -e "$1" ] && [ ! -L "$1" ]; }
bad=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  same "$C/$p" "$TOP/$p" || bad+=("$p")
done < <(git -C "$C" ls-files -o -i --exclude-standard)
[ "${#bad[@]}" = 0 ] || no "${bad[0]} is ignored and the parent lacks it or holds other bytes ($(( ${#bad[@]} - 1 )) more); copy or delete it, then rerun"
UNT=$(git -C "$C" ls-files -o --exclude-standard)
while IFS= read -r p; do
  [ -z "$p" ] || absent "$TOP/$p" || same "$C/$p" "$TOP/$p" || no "untracked $p already exists in this checkout with other bytes"
done <<<"$UNT"
PATCH=$(mktemp); trap 'rm -f "$PATCH"' EXIT
git -C "$C" diff --binary "$B" > "$PATCH" || no "the diff of $C cannot be read"
if [ -s "$PATCH" ]; then
  (cd "$TOP" && git apply --check "$PATCH" 2>/dev/null) || no "the diff of $C does not apply here"
  (cd "$TOP" && git apply "$PATCH") || no "the diff of $C failed to apply"
fi
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ -L "$C/$p" ]; then mkdir -p "$(dirname "$TOP/$p")" && ln -sfn "$(readlink "$C/$p")" "$TOP/$p"
  else mkdir -p "$(dirname "$TOP/$p")" && cp -p "$C/$p" "$TOP/$p"; fi || no "untracked $p could not be copied"
done <<<"$UNT"
# Proof every byte reached this checkout: each changed or untracked path is equal in both (a link as a link), or absent in both.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if absent "$C/$p"; then absent "$TOP/$p"; else same "$C/$p" "$TOP/$p"; fi || no "$p differs after apply"
done < <(git -C "$C" diff --name-only "$B"; printf '%s\n' "$UNT")
git -C "$PP_MAIN" worktree remove --force "$C" || { echo "REFUSED: applied, but git worktree remove failed for $C"; exit 1; }
[ -z "$BR" ] || git -C "$PP_MAIN" branch -D "$BR" >/dev/null || echo "applied, but git branch -D $BR failed" >&2
echo "applied $C"
