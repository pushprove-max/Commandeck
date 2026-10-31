#!/usr/bin/env bash
# review-pass-report.test.sh -- review-pass-report.sh (issue 514) tells main whether a later review pass is worth its
# cost: how often each pass after the first found something (a P0, P1 or P2 line), by the kind of unit (the plan's
# Tier word). What this pins: a P2 counts as found; rows split by tier; a row from before `passes` shows verdicts only
# and says so, never a count of 0.
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P)
PASS=0 FAIL=0
trap 'rm -rf "$T"' EXIT
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

unset "${!UNIT_LEDGER_@}"
export HOME=$T/home COMMANDECK_MAIN=$T/proj COMMANDECK_WORKSPACES=$T/ws COMMANDECK_SCRATCH=$T/scratch
mkdir -p "$HOME" "$T/ws" "$T/proj/.claude/metrics" "$T/proj/.claude/plans"
git init -q -b main "$T/proj"
LEDGER=$T/proj/.claude/metrics/unit-ledger.jsonl
report() { (cd "$T/proj" && bash "$SOURCE/scripts/review-pass-report.sh" "$@" 2>&1); }
plan() { printf '# %s\n\nTier: %s; LOCAL merge only.\n' "$1" "$2" > "$T/proj/.claude/plans/$1.md"; } # <unit> <tier>
# row <unit> <passes json>: a ledger row; passes "" leaves the key out, as a row from before it.
row() { jq -cn --arg u "$1" --arg p "$2" '{unit: $u, mergeSha: "abc", verdict: "CONVERGED-GO", rounds: 2, goRounds: 1, noGoRounds: 1}
  + (if $p == "" then {} else {passes: ($p | fromjson)} end)' >> "$LEDGER"; }

# Catches: a report that counts only P0 and P1 lines, or counts the first pass, reads a P2 on a later pass as nothing.
plan lat Standard
row lat '[{"n":1,"kind":"adversarial","verdict":"NO-GO","p0":0,"p1":0,"p2":1,"p3":0},{"n":2,"kind":"final","verdict":"GO","p0":0,"p1":0,"p2":1,"p3":0}]'
OUT=$(report)
P2OUT=$OUT

# Catches: a P3-only later pass counted as a find.
plan nit Standard
row nit '[{"n":1,"kind":"adversarial","verdict":"NO-GO","p0":1,"p1":0,"p2":0,"p3":0},{"n":2,"kind":"final","verdict":"GO","p0":0,"p1":0,"p2":0,"p3":3}]'
OUT=$(report)
check "a later pass that found a P2 counts" "1|1" "$(grep -c 'Standard.*later passes 1, found something 1' <<<"$P2OUT")|$(grep -c 'Standard.*later passes 2, found something 1' <<<"$OUT")"

# Catches: one table for every unit, so a Heavy unit's passes hide in Standard's rate.
plan big Heavy
row big '[{"n":1,"kind":"adversarial","verdict":"GO","p0":0,"p1":0,"p2":0,"p3":0},{"n":2,"kind":"final","verdict":"GO","p0":0,"p1":0,"p2":0,"p3":0}]'
rm -f "$T/proj/.claude/plans/lat.md"
OUT=$(report)
check "rows split by tier" "1 1 1" \
  "$(grep -c '^Standard ' <<<"$OUT") $(grep -c '^Heavy .*later passes 1, found something 0' <<<"$OUT") $(grep -c '^unknown .*later passes 1, found something 1' <<<"$OUT")"

# Catches: a row with no passes key counted as 0 finds, which would read as passes that found nothing.
row old ''
OUT=$(report)
check "an old row shows verdicts only" "1 1 0" \
  "$(grep -c '^old: CONVERGED-GO, 1 GO / 1 NO-GO, no pass data' <<<"$OUT") $(grep -c '^unknown (1 units): later passes 1, found something 1' <<<"$OUT") $(grep -c 'old.*found something' <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
