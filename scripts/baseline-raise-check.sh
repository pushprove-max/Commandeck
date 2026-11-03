#!/usr/bin/env bash
# baseline-raise-check.sh <base> [<head>] -- print one line per file-size cap
# <head> (default HEAD) loosens against <base>, and exit 1 if any. A ratchet
# only holds while nobody raises its cap in the same diff as the code that
# needed the room, so merge-unit-local.sh refuses such a unit without a reason
# (--baseline-raise "<reason>").
# Watched: every `CAP=<number>` in hooks/file-size-cop.sh, compared in file
# order. A raised value loosens; lowering passes. A file missing on either side
# is skipped. Run inside the repo holding both refs; exit 2 on a usage error.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "${0}"; exit 0 ;; esac
set -uo pipefail
BASE=${1:?usage: baseline-raise-check.sh <base> [<head>]}
HEAD_REF=${2:-HEAD}
for ref in "$BASE" "$HEAD_REF"; do
  git rev-parse -q --verify "$ref^{commit}" >/dev/null || { echo "not a commit: $ref" >&2; exit 2; }
done
FILE=hooks/file-size-cop.sh VAR=CAP
values() { grep -oE "(^|[^A-Za-z0-9_])$2=[0-9]+" <<<"$1" | sed 's/.*=//'; }
old=$(git show "$BASE:$FILE" 2>/dev/null) && new=$(git show "$HEAD_REF:$FILE" 2>/dev/null) || exit 0
out=$(paste -d' ' <(values "$old" "$VAR") <(values "$new" "$VAR") \
  | awk -v v="$VAR" 'NF == 2 && $2 > $1 { printf "%s #%d: %s -> %s\n", v, NR, $1, $2 }')
[ -z "$out" ] || { sed "s#^#LOOSENED $FILE #" <<<"$out"; exit 1; }
exit 0
