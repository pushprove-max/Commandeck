#!/usr/bin/env bash
# test-inputs.sh <commit> <test file>... -- whether a test file's inputs changed since <commit> (host issue 336).
# test-inputs.sh --list <test file>... -- each file's inputs, one line per file: `<file>` and its inputs, tab-separated,
# or `<file>` and `?` when they are uncertain (issue 667: run-shell-tests.sh keys a file's pass on them).
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
# The maps below need Bash 4: on a Mac this restarts under Homebrew's Bash, as the test runner does.
. "$(dirname "$0")/requirements.sh"
[ $# -ge 2 ] || { echo "usage: test-inputs.sh <commit>|--list <test file>..." >&2; exit 2; }
commit=$1; shift
all=$(find hooks scripts -type f 2>/dev/null | LC_ALL=C sort)
names=$(sed 's#.*/##' <<<"$all" | LC_ALL=C sort -u)
# BYNAME: basename -> its paths. SRC: a scanned .sh file -> the paths its source lines name, or `?` when one names no
# literal basename. Both are filled once per call, so a library many tests share is read once (issue 667: the runner
# asks for every test file of a run). A jq line `. as $x` inside a script is not a source line.
declare -A BYNAME=() SRC=()
while IFS= read -r p; do [ -n "$p" ] && BYNAME[${p##*/}]+="$p"$'\n'; done <<<"$all"
src_of() {
  local x=$1 line toks t out=
  [ -z "${SRC[$x]+set}" ] || return 0
  while IFS= read -r line; do
    toks=$(grep -oE '[A-Za-z0-9_][A-Za-z0-9_.-]*\.(sh|py|jq|mjs|js|json)' <<<"$line" || true)
    if [ -z "$toks" ]; then SRC[$x]='?'; return 0; fi
    while IFS= read -r t; do out+=${BYNAME[$t]-}; done <<<"$toks"
  done < <(grep -E '^[[:space:]]*(\.|source)[[:space:]]+' "$x" | grep -vE '^[[:space:]]*\.[[:space:]]+as[[:space:]]' || true)
  SRC[$x]=$out
}

# NAMED: test file -> the basenames it holds, from one grep over every file named (one process, not one per file).
declare -A NAMED=()
while IFS= read -r hit; do NAMED[${hit%%:*}]+=${hit#*:}$'\n'; done < <(
  for f in "$@"; do [ -f "$f" ] && printf '%s\0' "$f"; done | xargs -0 -r grep -oHF -f <(printf '%s\n' "$names") /dev/null 2>/dev/null)

for f in "$@"; do
  if [ ! -f "$f" ]; then if [ "$commit" = --list ]; then printf '%s\t?\n' "$f"; else echo "changed $f"; fi; continue; fi
  uncertain=0
  declare -A seen=()
  inputs=$f$'\n'
  while IFS= read -r n; do [ -z "$n" ] || inputs+=${BYNAME[$n]-}; done <<<"${NAMED[$f]-}"
  todo=$inputs
  while [ -n "$todo" ]; do
    next=
    while IFS= read -r x; do
      [ -n "$x" ] && [ -z "${seen[$x]+set}" ] || continue
      seen[$x]=1
      case $x in *.sh) ;; *) continue ;; esac
      src_of "$x"
      if [ "${SRC[$x]}" = '?' ]; then uncertain=1; continue; fi
      next+=${SRC[$x]}
    done <<<"$todo"
    todo=$next
  done
  inputs=$(printf '%s\n' "${!seen[@]}" | LC_ALL=C sort -u)
  unset seen
  if [ "$commit" = --list ]; then
    if [ "$uncertain" = 1 ]; then printf '%s\t?\n' "$f"; else printf '%s\t%s\n' "$f" "$(paste -sd '\t' - <<<"$inputs")"; fi
    continue
  fi
  if [ "$uncertain" = 1 ]; then echo "changed $f"; continue; fi
  # shellcheck disable=SC2086
  if git diff --quiet "$commit" HEAD -- $inputs 2>/dev/null; then echo "unchanged $f"; else echo "changed $f"; fi
done
