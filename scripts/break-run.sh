#!/usr/bin/env bash
# break-run.sh <plan> <k> -- run the test of the plan's k-th Break line and record the break run (issue 472).
# A Break line is `Break: <test file> -- <check label> -- <site>`; k counts them as builder-codex-pass.sh's break gate
# does: a line inside a fence or `Break: none` is not one. The Builder removes the condition first; this script then runs
# the test file (`bash` for a .test.sh, the .test.sh beside a .test.mjs, else the project's testCommand with the file as
# one argument) and needs a non-zero exit AND a failure record of the named check: a line that is `FAIL <label>` or
# opens `FAIL <label> (`, or opens `✖ <label> (`. Another check failing, or `ok <label>`, is no break run.
# On a break run it prints the row for the evidence file's `## Break runs`: `- <test file> -- <label> -- red: <command>`.
# Exit 0 a break run, 1 not one (the reason on stderr), 2 a bad line, plan or file.
# Self-test: bash scripts/__tests__/break-run.test.sh
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -9; exit 0 ;; esac
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/fence.sh"
die() { echo "break-run: $*" >&2; exit "${2:-2}"; }
[ $# -eq 2 ] || die "usage: break-run.sh <plan> <k>"
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
OUT=$(run 2>&1); RC=$?
[ "$RC" != 0 ] || { echo "break-run: not a break run: $CMD exits 0" >&2; exit 1; }
# The label goes in through the environment and is compared as text, never as a pattern or a shell word.
RECORD=$(printf '%s\n' "$OUT" | BR_LABEL=$LABEL awk '{ sub(/^[ \t]+/, "") }
  { l = ENVIRON["BR_LABEL"] }
  $0 == "FAIL " l || index($0, "FAIL " l " (") == 1 || index($0, "✖ " l " (") == 1 { n++ }
  END { print n + 0 }')
[ "$RECORD" != 0 ] || { echo "break-run: not a break run: $CMD fails (exit $RC), but with no failure record of '$LABEL'" >&2; exit 1; }
echo "- $FILE -- $LABEL -- red: $CMD"
