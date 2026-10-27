#!/usr/bin/env bash
# unit-hold.sh <unit> hold|release '<one-line reason>' -- records that a unit is parked on purpose, so the build
# review (collect.py holds_for) cuts the parked time instead of counting it as stage time.
# Rows go to .claude/metrics/unit-holds.jsonl in the primary checkout; COMMANDECK_UNIT_HOLDS overrides the path.
# A missing folder (a fresh project has no .claude/metrics) is made first.
# One >> append of one line under 4 KB is atomic on a local file system, so concurrent writers need no lock.
# Pairing is the reader's: no read here beyond the file's last byte, and no retry (the caller re-runs).
set -uo pipefail
usage() { echo "usage: unit-hold.sh <unit> hold|release '<one-line reason>'" >&2; exit 2; }
case "${1:-}" in --help|-h) (usage) 2>&1; exit 0 ;; esac
[ $# -eq 3 ] || usage
unit=$1 event=$2 reason=$3
[[ $unit =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage
case $event in hold|release) ;; *) usage ;; esac
[ -n "$reason" ] && [[ $reason != *$'\n'* ]] || usage
file=${COMMANDECK_UNIT_HOLDS:-}
if [ -z "$file" ]; then
  # shellcheck disable=SC1091
  . "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
  file=$PP_MAIN/.claude/metrics/unit-holds.jsonl
fi
row=$(jq -nc --arg unit "$unit" --arg event "$event" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg reason "$reason" \
  '{unit: $unit, event: $event, at: $at, reason: $reason}') || { echo "unit-hold.sh: could not build the row" >&2; exit 1; }
[ "${#row}" -lt 4000 ] || { echo "unit-hold.sh: reason too long; one line under 4 KB keeps the append atomic" >&2; exit 2; }
# An append cut off before its newline would swallow this row into one unreadable line; start a fresh line after it.
lead=
[ -s "$file" ] && [ -n "$(tail -c1 "$file" 2>/dev/null)" ] && lead=$'\n'
{ mkdir -p "$(dirname "$file")" && printf '%s%s\n' "$lead" "$row" >> "$file"; } 2>/dev/null || { echo "unit-hold.sh: could not append to $file; no hold recorded" >&2; exit 1; }
echo "unit-hold.sh: $unit $event recorded in $file"
