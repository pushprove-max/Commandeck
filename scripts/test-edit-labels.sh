#!/usr/bin/env bash
# test-edit-labels.sh <path> <base> [<head>] -- issue 504: which tests of an existing test file lose a line. Prints one row
# per label, in file order, for the lines <base> holds and <head> (default: the index) does not, blank ones left out.
# Exit 0: `<label><TAB><lost lines>`. Exit 2: those rows, and `(line)<TAB><line number><TAB><exact old text>` for each refused line.
# A label is one test: a `check "<label>"` in a `.sh` file that starts its line, with its backslash continuations, or an `it(`
# or `test(` in a JS or TS file that starts its line, has a string label and closes on its line or at a line of equal indent.
# Two tests of one label are `<label> #1`, `<label> #2`. A test whose lines hold a second test gives no label, nor does a label
# that could pose as a row (`(file)`, `(line)`, ` #<n>`) or is not plain text. Any other line of a code file is refused,
# comments and helpers too: the reader does not judge code, so a helper that registers a test cannot pass as harmless, and each
# refused line needs its own `line:` approval (). A line of a `.json`, `.txt`, `.md`, `.yml`
# or `.yaml` file is `(file)`. A failure of git or of this reader exits 3, so it never reads as no edits.
set -uo pipefail
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
P=${1:?usage: test-edit-labels.sh <path> <base> [<head>]} EB=${2:?usage: test-edit-labels.sh <path> <base> [<head>]} EH=${3-} SPAN=()
[ -n "$EH" ] && SPAN=("$EB" "$EH") || SPAN=(--cached "$EB")
OLD=$(git --literal-pathspecs show "$EB:$P") || { echo "test-edit-labels: cannot read $P at $EB" >&2; exit 3; }
D=$(git --literal-pathspecs diff --text --no-color --no-renames --no-ext-diff --no-textconv -U0 "${SPAN[@]}" -- "$P") \
  || { echo "test-edit-labels: git diff failed for $P" >&2; exit 3; }
# The old line number of each lost non-blank line: a hunk header `-a[,b]` starts at a, and each `-` line takes the next number.
LOST=$(LC_ALL=C awk '/^@@/ { s = $2; sub(/^-/, "", s); sub(/,.*/, "", s); cur = s + 0; on = 1; next }
  on && /^-/ { if (substr($0, 2) ~ /[^ \t]/) print cur; cur++ }' <<<"$D") \
  || { echo "test-edit-labels: cannot read the diff of $P" >&2; exit 3; }
[ -n "$LOST" ] || exit 0
KIND=code
case $P in
  *.json|*.txt|*.md|*.yml|*.yaml) printf '(file)\t%s\n' "$(wc -l <<<"$LOST" | tr -d ' ')"; exit 0 ;;
  *.sh) KIND=sh ;;
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.mts|*.cts) KIND=js ;;
esac
OUT=$(LC_ALL=C awk -v kind="$KIND" -v path="$P" '
  function plain(l) { return l != "" && l != "(file)" && l != "(line)" && l !~ /[$`\\\t]/ && l !~ / #[0-9]+$/ }
  function indent(t) { match(t, /^[ \t]*/); return RLENGTH }
  # Each test word of the text, as a test of this kind starts: a second one on a test makes its label name two tests.
  function second(t) {
    if (kind == "sh") return t ~ /(^|[;&|({])[ \t]*check[ \t]/
    return t ~ /(^|[^A-Za-z0-9_.$])(it|test)(\.[A-Za-z]+)*[(`]/
  }
  FILENAME == ARGV[1] { lost[++nl] = $1 + 0; next }
  { line[FNR] = $0; n = FNR }
  END {
    i = 1
    while (i <= n) {
      s = line[i]; label = ""; j = i
      if (kind == "sh" && match(s, /^[ \t]*check[ \t]+"[^"]+"/)) {
        label = substr(s, RSTART, RLENGTH); sub(/^[ \t]*check[ \t]+"/, "", label); sub(/"$/, "", label)
        if (second(substr(s, RSTART + RLENGTH))) label = ""
        while (line[j] ~ /\\$/ && j < n) { j++; if (second(line[j])) label = "" }
      } else if (kind == "js" && match(s, "^[ \t]*(it|test)\\([ \t]*[\"\047`]")) {
        qc = substr(s, RLENGTH, 1)
        rest = substr(s, RLENGTH + 1); e = index(rest, qc)
        if (e > 0 && !second(substr(rest, e + 1))) label = substr(rest, 1, e - 1)
        if (label != "" && s !~ /\)[;,]?[ \t]*$/) {
          ind = indent(s); j = 0
          for (k = i + 1; k <= n; k++) {
            if (line[k] !~ /[^ \t]/) continue
            w = indent(line[k])
            if (w < ind) break
            if (w == ind && substr(line[k], w + 1, 1) ~ /[})]/) { j = k; break }
            if (second(line[k])) break
          }
          if (j == 0) { label = ""; j = i }
        }
      }
      if (!plain(label)) { i++; continue }
      nth[i] = ++tests[label]
      for (k = i; k <= j; k++) { lab[k] = label; top[k] = i }
      i = j + 1
    }
    for (x = 1; x <= nl; x++) {
      m = lost[x]; l = lab[m]
      if (l == "") {
        printf "(line)\t%d\t%s\n", m, line[m]
        printf "test-edit-labels: %s:%d is no test this reader can name; it needs its own line approval\n", path, m > "/dev/stderr"
        bad = 1
        continue
      }
      if (tests[l] > 1) l = l " #" nth[top[m]]
      if (!(l in cnt)) order[++no] = l
      cnt[l]++
    }
    for (x = 1; x <= no; x++) printf "%s\t%d\n", order[x], cnt[order[x]]
    exit (bad ? 4 : 0)
  }' <(printf '%s\n' "$LOST") <(printf '%s\n' "$OLD"))
RC=$?
# awk itself fails with 2, so a refusal is 4 in there: only a run that ended on its own says so.
case $RC in
  0|4) [ -z "$OUT" ] || printf '%s\n' "$OUT" ;;
  *) echo "test-edit-labels: the reader failed on $P (exit $RC)" >&2; exit 3 ;;
esac
[ "$RC" = 0 ] || exit 2
