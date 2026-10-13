#!/usr/bin/env bash
# A resolved word counts in a finding's title and reason, never in its last
# field: that field is the exact failing command, which can hold any word.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
HOME=$TMP/home COMMANDECK_MAIN=$TMP/main COMMANDECK_SCRATCH=$TMP/scratch
mkdir -p "$HOME" "$COMMANDECK_MAIN" "$COMMANDECK_SCRATCH"
export HOME COMMANDECK_MAIN COMMANDECK_SCRATCH
source "$REAL/scripts/paths.sh"
r=$TMP/report
fail=0
count() { printf '%s\n' "$1" 'VERDICT: GO' > "$r"; surviving_severity "$r" standing; }
[ "$(count '- [P2] title -- a.sh:1 -- reason -- grep -c fixed x')" = 1 ] || { echo "FAIL a resolved word in the command resolves the finding"; fail=1; }
[ "$(count '- [P2] fixed title -- a.sh:1 -- reason -- grep -c x y')" = 0 ] || { echo "FAIL a resolved word in the title no longer resolves"; fail=1; }
[ "$(count '- [P2] title -- a.sh:1 -- no longer reachable -- grep -c x y')" = 0 ] || { echo "FAIL a resolved word in the reason no longer resolves"; fail=1; }
[ "$(count '- [P2] title fixed -- a.sh:1')" = 0 ] || { echo "FAIL a line with no fourth field changed"; fail=1; }
exit $fail
