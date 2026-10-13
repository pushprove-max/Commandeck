#!/usr/bin/env bash
# dashboard-builders-retry.test.sh -- a review round can be run twice (the
# first try died, or was refused). What this pins: the second try is open
# until ITS end row, so the card says "review" and main is not told the
# Builder went quiet while a pass is running.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
NOW=1790000000
iso() { date -u -d "@$((NOW - $1))" +%Y-%m-%dT%H:%M:%SZ; }
card() { jq -cs --argjson now "$NOW" -f "$ROOT/scripts/dashboard_builders.jq" | jq -c "$1"; }
START1=$(printf '{"ts":"%s","event":"codex-start","pass":"review","round":2}' "$(iso 900)")
END1=$(printf '{"ts":"%s","event":"codex-end","pass":"review","round":2,"rc":1}' "$(iso 800)")
START2=$(printf '{"ts":"%s","event":"codex-start","pass":"review","round":2}' "$(iso 400)")
END2=$(printf '{"ts":"%s","event":"codex-end","pass":"review","round":2,"rc":0}' "$(iso 350)")

check "a round run again is in review until its own end" '"review"' "$(printf '%s\n' "$START1" "$END1" "$START2" | card .stage)"
check "and is not called quiet" 0 "$(printf '%s\n' "$START1" "$END1" "$START2" | card '[.signals[] | select(.kind == "quiet")] | length')"
check "each try shows its own end" '[null,1]' "$(printf '%s\n' "$START1" "$END1" "$START2" | card '[.steps[] | .rc]')"
check "once the second try ends the round is done" '"fixing" [0,1]' \
  "$(printf '%s\n' "$START1" "$END1" "$START2" "$END2" | card .stage) $(printf '%s\n' "$START1" "$END1" "$START2" "$END2" | card '[.steps[] | .rc]')"
check "a try that died with no end row is closed by the next try's end" '"fixing"' "$(printf '%s\n' "$START1" "$START2" "$END2" | card .stage)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
