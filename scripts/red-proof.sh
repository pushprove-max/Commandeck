#!/usr/bin/env bash
# red-proof.sh <file> <line> <replacement> -- <test command...>  |  red-proof.sh --batch <list>
# Proves that ONE named test catches ONE named break: each run gets a fresh scratch worktree of this checkout
# (HEAD plus the working tree's changes, tracked and untracked). It runs the test as is, then with line <line>
# of <file> replaced by <replacement> ("" blanks it), then as is once more. Never edits this checkout.
# --batch takes lines of <file> TAB <line> TAB <replacement> TAB <test command, run by bash -c> and runs them all in
# ONE scratch worktree, the file restored after each break; it exits with the worst result of its proofs.
# A test file whose header comment names a <NAME>_TEST_CASE variable runs one case; a whole run of it is refused (issue 246).
#   exit 0  RED: green as is, red with the break
#   exit 1  NOT RED: the test still passes with the break, so it does not catch it
#   exit 2  no proof: bad arguments, a file outside the scratch copy, a whole case-aware run, or the test red
#           without the break
# Not mutation testing: one break, named by the caller, one test.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
usage() { echo "usage: red-proof.sh <file> <line> <replacement> -- <test command...> | --batch <list>" >&2; exit 2; }
if [ "${1-}" = --batch ]; then [ $# = 2 ] && [ -r "$2" ] || usage
else [ $# -ge 5 ] && [ "$4" = -- ] || usage; fi
ROOT=$(git rev-parse --show-toplevel) || exit 2
# valid <file> <line> <replacement> <test command words...> -- 0 when the break can be proved; sets REL, LINE, NEW.
valid() {
  local FILE=$1 W V WS; LINE=$2 NEW=$3; shift 3
  case $LINE in ''|*[!0-9]*|0) echo "red-proof: $LINE is no line number" >&2; return 2 ;; esac
  REL=${FILE#"$ROOT"/}
  case $REL in /*|../*|*/../*) echo "red-proof: name $FILE from the checkout's root" >&2; return 2 ;; esac
  [ -f "$ROOT/$REL" ] || { echo "red-proof: no file $REL" >&2; return 2; }
  # Only a file the scratch copy holds itself: an ignored dependency is a link to this checkout's, and a tracked link
  # points out of the copy, so writing the break through either would change the original.
  [ -n "$(git -C "$ROOT" ls-files --cached --others --exclude-standard -- "$REL")" ] && [ ! -L "$ROOT/$REL" ] \
    || { echo "red-proof: $REL is not a plain file of this checkout (ignored, a link, or behind one); the break would land outside the scratch copy" >&2; return 2; }
  [ "$LINE" -le "$(wc -l < "$ROOT/$REL")" ] || { echo "red-proof: $REL has no line $LINE" >&2; return 2; }
  [ "$(sed -n "${LINE}p" "$ROOT/$REL")" != "$NEW" ] || { echo "red-proof: line $LINE of $REL already reads that; nothing breaks" >&2; return 2; }
  # A case-aware test file named by the command needs its variable set, in this environment or in the command.
  # Its header says so (the convention); a name in the body may be a fixture's text, not a selector.
  read -ra WS <<<"$*"
  for W in "${WS[@]}"; do
    [ -f "$ROOT/$W" ] || continue
    V=$(sed -n '/^#/!q;p' "$ROOT/$W" | grep -oE '[A-Z][A-Z0-9_]*_TEST_CASE' | head -1)
    [ -n "$V" ] && [ -z "${!V+x}" ] && [[ " $* " != *" $V="* ]] || continue
    echo "red-proof: $W runs one case with $V=<text in the case name>; a whole run of it repeats every case three times. Set it: $V='<case>' bash $W" >&2
    return 2
  done
}

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

# No stdin: in a batch it is the list, and a test that read it would swallow the proofs after it.
run_test() { (cd "$WT" && "$@") < /dev/null > "$BOX/out" 2>&1; }
show() { tail -n 15 "$BOX/out" | sed 's/^/  | /'; }
# break_line -- write the break into the scratch copy's file.
# Through ENVIRON, not -v: awk -v rewrites backslash escapes, so a replacement holding a regex would change.
break_line() { RP_NEW=$NEW awk -v n="$LINE" 'NR == n { print ENVIRON["RP_NEW"]; next } { print }' "$WT/$REL" > "$BOX/broken" \
  && cat "$BOX/broken" > "$WT/$REL"; }

if [ "$1" = --batch ]; then
  # One copy for every proof: the file is put back from the copy's own text after each break.
  scratch batch; WORST=0
  while IFS= read -r ROW || [ -n "$ROW" ]; do
    [ -n "$ROW" ] || continue
    # Split by hand: read with IFS=TAB merges two tabs, so an empty replacement would shift the test into its place.
    [[ $ROW == *$'\t'*$'\t'*$'\t'* ]] || { echo "red-proof: a batch line needs 4 tab-separated fields: $ROW"; WORST=2; continue; }
    F=${ROW%%$'\t'*} ROW=${ROW#*$'\t'}; L=${ROW%%$'\t'*} ROW=${ROW#*$'\t'}; N=${ROW%%$'\t'*} C=${ROW#*$'\t'}
    valid "$F" "$L" "$N" "$C" 2>&1 || { WORST=2; continue; }
    cp "$WT/$REL" "$BOX/keep"
    if ! run_test bash -c "$C"; then echo "red-proof: $REL:$LINE: NO PROOF: the test already fails without the break"; show; WORST=2; continue; fi
    break_line || exit 2
    if run_test bash -c "$C"; then
      cp "$BOX/keep" "$WT/$REL"; echo "red-proof: $REL:$LINE: NOT RED: the test passes with the break"; show
      [ "$WORST" = 2 ] || WORST=1; continue
    fi
    cp "$BOX/out" "$BOX/out-broken"; cp "$BOX/keep" "$WT/$REL"
    if ! run_test bash -c "$C"; then echo "red-proof: $REL:$LINE: NO PROOF: the test fails without the break when run again"; show; WORST=2; continue; fi
    cp "$BOX/out-broken" "$BOX/out"
    echo "red-proof: RED: the test passes as is and fails with $REL:$LINE replaced by: $NEW"; show
  done < "$2"
  exit "$WORST"
fi

FILE=$1; L=$2; N=$3; shift 4
valid "$FILE" "$L" "$N" "$@" || exit 2
scratch as-is
if ! run_test "$@"; then
  echo "red-proof: NO PROOF: the test already fails in the scratch copy without the break"; show; exit 2
fi
scratch broken
break_line || exit 2
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
