#!/usr/bin/env bash
# port-list.sh <source repo> [<last release ref>] -- what to port into the
# plugin next. Every tooling brief in the source repository carries one line,
# `plugin: port`, `plugin: no` or `plugin: n/a`, and the commit that lands the
# brief repeats it. This lists the commits since <last release ref> (all of
# them without one) that touch a brief and say `plugin: port`, oldest first.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
[ $# -ge 1 ] && [ $# -le 2 ] || { echo "usage: port-list.sh <source repo> [<last release ref>]" >&2; exit 2; }
git -C "$1" log --reverse --date=short --format='%h %ad %s' --grep='^plugin: port' ${2:+"$2.."} -- .claude/briefs
