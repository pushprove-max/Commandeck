#!/usr/bin/env bash
# break-run.sh <plan> <k> -- run the test of the plan's k-th Break line and record the break run (issue 472).
# A Break line is `Break: <test file> -- <check label> -- <site>`; k counts them as builder-codex-pass.sh's break gate
# does: a line inside a fence or `Break: none` is not one. The Builder removes the condition first; this script then runs
# the test file (`bash` for a .test.sh, the .test.sh beside a .test.mjs, else the project's testCommand with the file as
# one argument) and needs a non-zero exit AND a failure record of the named check: a line that is `FAIL <label>` or
# opens `FAIL <label> (`, or opens `✖ <label> (`. Another check failing, or `ok <label>`, is no break run.
# On a break run it prints the row for the evidence file's `## Break runs`: `- <test file> -- <label> -- red: <command>`.
# Exit 0 a break run, 1 not one (the reason on stderr), 2 a bad line, plan or file.
# break-run.sh <plan> <k> <code file> <line> [<replacement>] (issue 542) breaks the line itself, on the uncommitted tree:
# it runs the test clean first and refuses (2) one that already fails or already prints `FAIL <label>`, then writes the
# replacement (none: an empty line) over the code file's line, runs the test, and puts the file back from a byte copy at
# <git-dir>/break-run.bak on exit, INT and TERM. A missing or unchanged line, or a restore that differs, is exit 2. A
# SIGKILL runs no trap: the copy stays, and the next run of either form refuses naming the `cp` that restores the file.
# One break run per git directory at a time (pass 4): a run holds flock on <git-dir>/break-run.lock from before its
# backup check until it exits, so two runs never share break-run.bak, .path, .copy or .new, and a plain run never tests a
# file another run has broken. A second run is refused (2) naming the holder's pid; the kernel frees the lock when the
# holder dies, even by SIGKILL. The test itself runs without the lock's descriptor, so a test left running does not hold it.
# Self-test: bash scripts/__tests__/break-run.test.sh
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -18; exit 0 ;; esac
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/fence.sh"
die() { echo "break-run: $*" >&2; exit "${2:-2}"; }
case $# in 2|4|5) ;; *) die "usage: break-run.sh <plan> <k> [<code file> <line> [<replacement>]]" ;; esac
PLAN=$1 K=$2
case $K in ''|*[!0-9]*|0) die "k is a Break line number from 1, not '$K'" ;; esac
[ -r "$PLAN" ] || die "cannot read the plan $PLAN"
LINE=$(awk "$PP_AWK_FENCE"'fence($0) || flen { next } tolower($0) ~ /^break:[[:space:]]*none([[:space:]]|[[:punct:]]|$)/ { next } /^Break: / { sub(/^Break: /, ""); print }' "$PLAN" | sed -n "${K}p")
[ -n "$LINE" ] || die "$PLAN has no Break line $K"
[[ $LINE == *' -- '*' -- '* ]] || die "Break line $K is not '<test file> -- <check label> -- <site>': $LINE"
FILE=${LINE%% -- *} LABEL=${LINE#* -- }; LABEL=${LABEL% -- *}
[ -f "$FILE" ] || die "no test file $FILE"
case $FILE in
  *.test.sh) CMD="bash $FILE"; run() { bash "$FILE"; } ;;
  *.test.mjs) W=${FILE%.mjs}.sh; [ -f "$W" ] || die "no $W to run $FILE"; CMD="bash $W"; run() { bash "$W"; } ;;
  *) . "$HERE/paths.sh"
    TC=$(jq -er '.testCommand // empty' "$PP_MAIN/.claude/commandeck.json" 2>/dev/null) || die "no testCommand in $PP_MAIN/.claude/commandeck.json to run $FILE"
    CMD="$TC $FILE"; run() { bash -c "$TC \"\$1\"" _ "$FILE"; } ;;
esac
# record <output> -- how many lines of it are a failure record of the label. The label goes in through the environment
# and is compared as text, never as a pattern or a shell word.
record() {
  printf '%s\n' "$1" | BR_LABEL=$LABEL awk '{ sub(/^[ \t]+/, "") }
    { l = ENVIRON["BR_LABEL"] }
    $0 == "FAIL " l || index($0, "FAIL " l " (") == 1 || index($0, "✖ " l " (") == 1 { n++ }
    END { print n + 0 }'
}
# lock <git dir> -- take this run's lock or refuse naming the run that holds it; then, under the lock, refuse while a
# killed run's backup is left (either form: a plain run would test the file that run left broken).
lock() {
  exec 9>>"$1/break-run.lock" || die "cannot open $1/break-run.lock"
  flock -n 9 || die "another break run (pid $(tr -cd 0-9 < "$1/break-run.lock")) holds $1/break-run.lock; run this one when it ends"
  printf '%s\n' "$$" > "$1/break-run.lock"
  if [ -e "$1/break-run.bak" ]; then
    die "a leftover backup from a killed run is at $1/break-run.bak; restore with: cp $(printf %q "$1/break-run.bak") $(printf %q "$(cat "$1/break-run.path" 2>/dev/null)") && rm -f $(printf %q "$1/break-run.bak") $(printf %q "$1/break-run.path")"
  fi
}
ROW=
if [ $# -eq 2 ]; then
  ! GD=$(git -C "$(dirname "$FILE")" rev-parse --absolute-git-dir 2>/dev/null) || lock "$GD"
  OUT=$(run 2>&1 9>&-); RC=$?
else
  CODE=$3 N=$4 REPL=${5-}
  case $N in ''|*[!0-9]*|0) die "line is a line number from 1, not '$N'" ;; esac
  [ -f "$CODE" ] || die "no code file $CODE"
  GD=$(git -C "$(dirname "$CODE")" rev-parse --absolute-git-dir 2>/dev/null) || die "$CODE is in no git repository"
  lock "$GD"
  BAK=$GD/break-run.bak BPATH=$GD/break-run.path
  LINES=$(awk 'END { print NR }' "$CODE")
  [ "$N" -le "$LINES" ] || die "line $N is past the end of $CODE ($LINES lines)"
  [ "$(sed -n "${N}p" "$CODE")" != "$REPL" ] || die "line $N of $CODE already reads that; the break changes no line"
  # The test runs in the background so a signal reaches the trap at once; the trap stops its tree.
  CHILD=
  kill_tree() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done; kill "$1" 2>/dev/null; return 0; }
  runwait() { local o; o=$(mktemp); run > "$o" 2>&1 9>&- & CHILD=$!; wait "$CHILD"; RC=$?; CHILD=; OUT=$(cat "$o"); rm -f "$o"; }
  restore() {
    local rc=$?
    [ -z "$CHILD" ] || kill_tree "$CHILD"
    if [ -e "$BAK" ]; then
      cat "$BAK" > "$CODE"
      if cmp -s "$BAK" "$CODE"; then rm -f "$BAK" "$BPATH"
      else echo "break-run: $CODE differs from its backup after the restore; restore with: cp $(printf %q "$BAK") $(printf %q "$CODE")" >&2; rc=2; fi
    fi
    [ "$rc" != 0 ] || [ -z "$ROW" ] || echo "$ROW"
    exit "$rc"
  }
  trap restore EXIT; trap 'exit 130' INT; trap 'exit 143' TERM
  runwait
  [ "$RC" = 0 ] && [ "$(record "$OUT")" = 0 ] || die "the test fails before the break (exit $RC, or it already prints 'FAIL $LABEL'): $CMD"
  # The exit trap restores whatever break-run.bak holds, so the copy is made beside it and becomes break-run.bak (one
  # rename) only once it is whole and matches the file; a failed or short copy is removed and the file is never touched.
  printf '%s\n' "$CODE" > "$BPATH" && cp -p "$CODE" "$GD/break-run.copy" && cmp -s "$CODE" "$GD/break-run.copy" \
    && mv -f "$GD/break-run.copy" "$BAK" || { rm -f "$GD/break-run.copy" "$BPATH"; die "cannot back up $CODE"; }
  BR_N=$N BR_REPL=$REPL awk 'NR == ENVIRON["BR_N"] + 0 { print ENVIRON["BR_REPL"]; next } { print }' "$BAK" > "$GD/break-run.new" \
    && cat "$GD/break-run.new" > "$CODE"; rm -f "$GD/break-run.new"
  runwait
  CMD="$CMD with $CODE:$N broken"
fi
[ "$RC" != 0 ] || { echo "break-run: not a break run: $CMD exits 0" >&2; exit 1; }
[ "$(record "$OUT")" != 0 ] || { echo "break-run: not a break run: $CMD fails (exit $RC), but with no failure record of '$LABEL'" >&2; exit 1; }
ROW="- $FILE -- $LABEL -- red: $CMD"
[ $# -eq 2 ] && echo "$ROW"
exit 0
