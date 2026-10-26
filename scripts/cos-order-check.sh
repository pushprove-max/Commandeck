#!/usr/bin/env bash
# cos-order-check.sh <file> -- the Chief of Staff runs this on an order file (templates/cos-order.md) before it sends the
# file to main (issue 360). Exit 0: the first section is "## The owner's words" and the only other section is
# "## Chief of Staff additions -- NOT ordered". Exit 1, one line per fault: text before the first section, a first
# section that is not the owner's words, or any other section, which would pass an addition to main as the owner's words.
case ${1-} in -h|--help|"") sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -4; [ -n "${1-}" ]; exit ;; esac
set -u
[ -r "$1" ] || { echo "cos-order-check: cannot read $1" >&2; exit 2; }
WORDS="## The owner's words" ADD="## Chief of Staff additions -- NOT ordered"
awk -v words="$WORDS" -v add="$ADD" '
  { sub(/[ \t\r]+$/, "") }
  /^## / { n++; if (n == 1 && $0 != words) bad = bad "the first section is \"" $0 "\", not \"" words "\"\n"
           if ($0 == words && seen++) bad = bad "line " NR ": a second \"" words "\" section\n"
           else if ($0 != words && $0 != add) bad = bad "line " NR ": \"" $0 "\" is outside \"" add "\"\n"; next }
  NF && !n && !pre { pre = 1; bad = bad "line " NR ": text before the first section\n" }
  END { if (!n) bad = bad "no section: the file must start with \"" words "\"\n"; printf "%s", bad; exit bad != "" }
' "$1"
