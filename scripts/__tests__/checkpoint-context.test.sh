#!/usr/bin/env bash
# checkpoint-context.py carry: a restart may not drop an open item it inherited (issue 252). An item counts as
# kept only where the new checkpoint's own text restates it or closes it; its "Carries open items of:" line is
# for recovery and keeps nothing, so a reworded item is reported, not carried silently.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
carry() { python3 "$REAL/scripts/checkpoint-context.py" carry "$1" "$2"; }

printf '## Queue\n- Plugin merge, then plugin second unit.\n' > "$TMP/base.md"
printf '## Queue\n- Plugin on owner answer.\n\n## Carried by reference\nCarries open items of: %s\n\n## Closed since last checkpoint\n- none\n' "$TMP/base.md" > "$TMP/new.md"
OUT=$(carry "$TMP/base.md" "$TMP/new.md"); RC=$?
check "a reworded item is dropped though the new checkpoint carries its file by reference" 1 "$RC"
check "and the dropped item is named" "- Plugin merge, then plugin second unit." "$OUT"

# The template's fresh-start "none" names no file: a base that says it, followed by one that restates its item, passes.
printf '## Queue\n- Plugin merge, then plugin second unit.\n\n## Carried by reference\nCarries open items of: none\n' > "$TMP/fresh.md"
check "Carries open items of: none is no reference" 0 "$(carry "$TMP/fresh.md" "$TMP/base.md" >/dev/null 2>&1; echo $?)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
