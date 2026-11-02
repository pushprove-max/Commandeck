#!/usr/bin/env bash
# covers: hooks/units-elements.ts dashboard/app.js
# Drift guard (issue 583): the dashboard page shows 12-hour times (app.js hm), so no units view formats a 24-hour clock
# time beside it. A formatter that prints 24-hour time is named by its call: toTimeString, toLocaleTimeString, hour12: false,
# hourCycle, HH:mm, getUTCHours. Data and log timestamps stay ISO and are not formatted by these. The detector is shown
# to catch a planted one, so the guard is not vacuous.
# Run: bash scripts/__tests__/twelve-hour-clock.guard.test.sh
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
PAT='toTimeString|toLocaleTimeString|hour12: *false|hourCycle|HH:mm|getUTCHours'

printf 'const c = (t) => new Date(t).toTimeString().slice(0, 5)\n' > "$T/planted.ts"
if grep -Eq "$PAT" "$T/planted.ts"; then ok "the detector catches a planted 24-hour formatter"; else bad "the detector misses a planted 24-hour formatter"; fi

# Every units view (hooks/units*.ts and .tsx, tests excluded) and the page's script.
FILES=$(find "$ROOT/hooks" -maxdepth 1 \( -name 'units*.ts' -o -name 'units*.tsx' \) ! -name '*.test.*'; echo "$ROOT/dashboard/app.js")
[ "$(grep -c . <<<"$FILES")" -ge 4 ] && ok "the guard reads the units views and app.js" || bad "the guard found too few files: $FILES"
HITS=$(grep -nE "$PAT" $FILES 2>/dev/null || true)
if [ -z "$HITS" ]; then ok "no view formats a 24-hour clock time"; else bad "no view formats a 24-hour clock time: $HITS"; fi
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
