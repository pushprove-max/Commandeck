#!/usr/bin/env bash
# drift-guard-example.sh <file-a> <file-b> -- the worked example of a drift guard (templates/rules-details.md).
# The fact is the `Retry limit:` line. Each file holds one copy; the guard fails, naming both files, when the
# copies differ, and exits 2 when a file has no copy to compare. Copy it, change `fact`, name it for what it guards.
set -uo pipefail
[ $# = 2 ] || { echo "usage: drift-guard-example.sh <file-a> <file-b>" >&2; exit 2; }
fact() { sed -n 's/^Retry limit: *//p' "$1" 2>/dev/null | head -1; }
A=$(fact "$1") B=$(fact "$2")
[ -n "$A" ] && [ -n "$B" ] || { echo "drift guard: no 'Retry limit:' line in $1 or $2" >&2; exit 2; }
[ "$A" = "$B" ] || { echo "drift: $1 says '$A', $2 says '$B'" >&2; exit 1; }
echo "ok: $1 and $2 agree on Retry limit: $B"
