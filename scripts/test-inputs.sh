#!/usr/bin/env bash
# test-inputs.sh <commit> <test file>... -- whether a test file's inputs changed since <commit> (host issue 336).
# Run from a checkout root. Prints "unchanged <file>" or "changed <file>" per file. A file that passed at an earlier
# commit of a build, and prints "unchanged" here, is cited in the closing run instead of run again.
# A file's inputs: the file; every hooks/ or scripts/ file it names by basename (shell-tests-for.sh's relation, in
# reverse); and, to a fixed point, every file those inputs source (a `.` or `source` line whose path holds a literal
# basename found under hooks/ or scripts/). A source line with no literal basename (a variable path) leaves the
# coverage uncertain, so the file reads "changed" and runs.
# shortcut: inputs by basename and literal source lines; a file read some other way is not seen; upgrade to a traced
# run if one is missed.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -8; exit 0 ;; esac
set -uo pipefail
[ $# -ge 2 ] || { echo "usage: test-inputs.sh <commit> <test file>..." >&2; exit 2; }
commit=$1; shift
all=$(find hooks scripts -type f 2>/dev/null | LC_ALL=C sort)
names=$(sed 's#.*/##' <<<"$all" | LC_ALL=C sort -u)

for f in "$@"; do
  [ -f "$f" ] || { echo "changed $f"; continue; }
  uncertain=0
  inputs=$(printf '%s\n' "$f"; grep -ohF -f <(printf '%s\n' "$names") "$f" 2>/dev/null | LC_ALL=C sort -u | while IFS= read -r n; do
    awk -F/ -v t="$n" '$NF == t' <<<"$all"
  done)
  inputs=$(printf '%s\n' "$inputs" | grep . | LC_ALL=C sort -u)
  scanned=
  while :; do
    todo=$(comm -23 <(printf '%s\n' "$inputs") <(printf '%s\n' "$scanned" | grep . | LC_ALL=C sort -u))
    [ -n "$todo" ] || break
    scanned=$(printf '%s\n%s\n' "$scanned" "$todo")
    while IFS= read -r x; do
      case $x in *.sh) ;; *) continue ;; esac
      while IFS= read -r line; do
        toks=$(grep -oE '[A-Za-z0-9_][A-Za-z0-9_.-]*\.(sh|py|jq|mjs|js|json)' <<<"$line" || true)
        if [ -z "$toks" ]; then uncertain=1; continue; fi
        while IFS= read -r t; do
          inputs=$(printf '%s\n' "$inputs"; awk -F/ -v t="$t" '$NF == t' <<<"$all")
        done <<<"$toks"
      done < <(grep -E '^[[:space:]]*(\.|source)[[:space:]]+' "$x" || true)
    done <<<"$todo"
    inputs=$(printf '%s\n' "$inputs" | grep . | LC_ALL=C sort -u)
  done
  if [ "$uncertain" = 1 ]; then echo "changed $f"; continue; fi
  # shellcheck disable=SC2086
  if git diff --quiet "$commit" HEAD -- $inputs 2>/dev/null; then echo "unchanged $f"; else echo "changed $f"; fi
done
