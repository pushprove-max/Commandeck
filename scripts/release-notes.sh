#!/usr/bin/env bash
# release-notes.sh <version> -- print that version's section of CHANGELOG.md (its "## <version> -- <date>" heading
# and the lines under it): the text update.sh shows for the newest, and the body of a published release.
# Exit 1 with a message when the changelog has no such section.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[ $# -eq 1 ] || { echo "usage: release-notes.sh <version>" >&2; exit 1; }
OUT=$(awk -v v="$1" '/^## / { p = ($2 == v) } p' "$ROOT/CHANGELOG.md")
[ -n "$OUT" ] || { echo "release-notes: $ROOT/CHANGELOG.md has no section for version $1" >&2; exit 1; }
printf '%s\n' "$OUT"
