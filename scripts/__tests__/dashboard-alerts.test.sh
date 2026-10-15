#!/usr/bin/env bash
# dashboard_alerts.jq decides what wakes the Chief of Staff. A load average over
# the core count is a normal build machine, not an alert: the host-load rule
# fired on every busy build and was removed, and with it the "host load" input,
# so a host that reports no load average is not "not measured" either. The swap
# rule beside it must still fire.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
# alerts <host json> -> the rules' output
alerts() { jq -nc -f "$REAL/scripts/dashboard_alerts.jq" --argjson now "$(date +%s)" --arg s7 2026-10-08 --argjson hasSe false \
  --argjson se '[]' --argjson parts "[{\"host\": $1, \"projects\": {}}]" --argjson srcs '[]' --argjson prev '{}'; }
OUT=$(alerts '{"cpus": 8, "load": [50, 40, 30], "swap": {"totalMb": 1000, "usedMb": 900}}')
check "a load far over the core count raises no alert" 0 "$(jq '[.alerts[] | select(.id | startswith("host-load-"))] | length' <<<"$OUT")"
check "swap over 75% still raises one" 1 "$(jq '[.alerts[] | select(.id | startswith("host-swap-"))] | length' <<<"$OUT")"
check "a host with no load average is not reported as not measured" 0 \
  "$(alerts '{"swap": {"totalMb": 1000, "usedMb": 10}}' | jq '[.missing[] | select(. == "host load")] | length')"
# A Builder writes no seat rows, so the 24 h cache rate never saw it: its own session's usage is the rate.
units() { jq -nc -f "$REAL/scripts/dashboard_alerts.jq" --argjson now "$(date +%s)" --arg s7 2026-10-08 --argjson hasSe false \
  --argjson se '[]' --argjson parts "[{\"projects\": {\"p\": {\"units\": {\"inFlight\": $1}}}}]" --argjson srcs '[]' --argjson prev '{}'; }
OUT=$(units '[{"unit": "low", "builder": {"cache24h": {"input": 1000, "cachedInput": 800}}},
  {"unit": "high", "builder": {"cache24h": {"input": 1000, "cachedInput": 970}}}, {"unit": "unread", "builder": {"cache24h": null}}]')
check "a Builder under 95% cached over 24 h raises a warning naming it; one over does not" '["p: Builder low cache hit rate over the last 24 h is 80%, under 95%"]' \
  "$(jq -c '[.alerts[] | select(.id | startswith("cache-builder-")) | .text]' <<<"$OUT")"
check "a Builder whose session log failed to read is not measured" 1 "$(jq '[.missing[] | select(. == "p: Builder unread 24 h cache hit rate")] | length' <<<"$OUT")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
