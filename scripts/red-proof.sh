#!/usr/bin/env bash
# red-proof.sh <file> <line> <replacement> -- <test command...>
# Proves that ONE named test catches ONE named break: each run gets a fresh scratch worktree of this checkout
# (HEAD plus the working tree's changes, tracked and untracked). It runs the test as is, then with line <line>
# of <file> replaced by <replacement> ("" blanks it), then as is once more. Never edits this checkout.
#   exit 0  RED: green as is, red with the break
#   exit 1  NOT RED: the test still passes with the break, so it does not catch it
#   exit 2  no proof: bad arguments, a file outside the scratch copy, or the test red without the break
# Not mutation testing: one break, named by the caller, one test.
set -uo pipefail
usage() { echo "usage: red-proof.sh <file> <line> <replacement> -- <test command...>" >&2; exit 2; }
[ $# -ge 5 ] && [ "$4" = -- ] || usage
FILE=$1 LINE=$2 NEW=$3; shift 4
case $LINE in ''|*[!0-9]*|0) usage ;; esac
ROOT=$(git rev-parse --show-toplevel) || exit 2
REL=${FILE#"$ROOT"/}
case $REL in /*|../*|*/../*) echo "red-proof: name $FILE from the checkout's root" >&2; exit 2 ;; esac
[ -f "$ROOT/$REL" ] || { echo "red-proof: no file $REL" >&2; exit 2; }
# Only a file the scratch copy holds itself: an ignored dependency is a link to this checkout's, and a tracked link
# points out of the copy, so writing the break through either would change the original.
[ -n "$(git -C "$ROOT" ls-files --cached --others --exclude-standard -- "$REL")" ] && [ ! -L "$ROOT/$REL" ] \
  || { echo "red-proof: $REL is not a plain file of this checkout (ignored, a link, or behind one); the break would land outside the scratch copy" >&2; exit 2; }
[ "$LINE" -le "$(wc -l < "$ROOT/$REL")" ] || { echo "red-proof: $REL has no line $LINE" >&2; exit 2; }
[ "$(sed -n "${LINE}p" "$ROOT/$REL")" != "$NEW" ] || { echo "red-proof: line $LINE of $REL already reads that; nothing breaks" >&2; exit 2; }

BOX=$(mktemp -d "${TMPDIR:-/tmp}/red-proof.XXXXXX") || exit 2
( cd "$ROOT" && git diff --binary HEAD ) > "$BOX/changes.diff"
cleanup() {
  for wt in "$BOX"/wt-*; do [ ! -d "$wt" ] || git -C "$ROOT" worktree remove --force "$wt" >/dev/null 2>&1; done
  git -C "$ROOT" worktree prune >/dev/null 2>&1; rm -rf "$BOX"
}
trap cleanup EXIT
# scratch <name>: a fresh copy for one run, so nothing an earlier run left in its copy reaches the next.
scratch() {
  WT=$BOX/wt-$1
  # No repo hooks: the scratch checkout is not a branch anyone reviews or merges.
  git -C "$ROOT" -c core.hooksPath=/dev/null worktree add --quiet --detach "$WT" HEAD || { echo "red-proof: could not make the scratch worktree" >&2; exit 2; }
  [ ! -s "$BOX/changes.diff" ] || git -C "$WT" apply --whitespace=nowarn "$BOX/changes.diff" \
    || { echo "red-proof: the working tree's changes did not apply to the scratch copy" >&2; exit 2; }
  ( cd "$ROOT" && git ls-files --others --exclude-standard -z ) | while IFS= read -r -d '' f; do
    mkdir -p "$WT/$(dirname "$f")" && cp -p "$ROOT/$f" "$WT/$f"
  done
  # Installed dependencies are not in git; the scratch copy reads this checkout's.
  [ ! -e "$ROOT/node_modules" ] || [ -e "$WT/node_modules" ] || ln -s "$ROOT/node_modules" "$WT/node_modules"
  return 0
}

run_test() { (cd "$WT" && "$@") > "$BOX/out" 2>&1; }
show() { tail -n 15 "$BOX/out" | sed 's/^/  | /'; }
scratch as-is
if ! run_test "$@"; then
  echo "red-proof: NO PROOF: the test already fails in the scratch copy without the break"; show; exit 2
fi
scratch broken
# Through ENVIRON, not -v: awk -v rewrites backslash escapes, so a replacement holding a regex would change.
RP_NEW=$NEW awk -v n="$LINE" 'NR == n { print ENVIRON["RP_NEW"]; next } { print }' "$WT/$REL" > "$BOX/broken" \
  && cat "$BOX/broken" > "$WT/$REL" || exit 2
if run_test "$@"; then
  echo "red-proof: NOT RED: the test passes with $REL:$LINE replaced, so it does not catch that break"; show; exit 1
fi
cp "$BOX/out" "$BOX/out-broken"
# State outside the copies (a temp file, a dependency) is shared: the unbroken test must pass again after the break.
scratch again
if ! run_test "$@"; then
  echo "red-proof: NO PROOF: the test fails without the break when run again, so its red is not the break's"; show; exit 2
fi
cp "$BOX/out-broken" "$BOX/out"
echo "red-proof: RED: the test passes as is and fails with $REL:$LINE replaced by: $NEW"; show
exit 0
