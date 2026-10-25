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
  --argjson se '[]' --argjson parts "[{\"host\": $1, \"projects\": {}}]" --argjson srcs '[]' --argjson preva '[{}]'; }
OUT=$(alerts '{"cpus": 8, "load": [50, 40, 30], "swap": {"totalMb": 1000, "usedMb": 900}}')
check "a load far over the core count raises no alert" 0 "$(jq '[.alerts[] | select(.id | startswith("host-load-"))] | length' <<<"$OUT")"
check "swap over 75% still raises one" 1 "$(jq '[.alerts[] | select(.id | startswith("host-swap-"))] | length' <<<"$OUT")"
check "a host with no load average is not reported as not measured" 0 \
  "$(alerts '{"swap": {"totalMb": 1000, "usedMb": 10}}' | jq '[.missing[] | select(. == "host load")] | length')"
# A Builder writes no seat rows, so the 24 h cache rate never saw it: its own session's usage is the rate.
units() { jq -nc -f "$REAL/scripts/dashboard_alerts.jq" --argjson now "$(date +%s)" --arg s7 2026-10-08 --argjson hasSe false \
  --argjson se '[]' --argjson parts "[{\"projects\": {\"p\": {\"units\": {\"inFlight\": $1}}}}]" --argjson srcs '[]' --argjson preva '[{}]'; }
# A new Builder writes its whole prompt prefix to cache first, so its early 24 h rate is low by construction:
# under the warm-up input that is normal operation, not an alert.
OUT=$(units '[{"unit": "low", "builder": {"cache24h": {"input": 4000000, "cachedInput": 3200000}}},
  {"unit": "warming", "builder": {"cache24h": {"input": 1000000, "cachedInput": 800000}}},
  {"unit": "high", "builder": {"cache24h": {"input": 4000000, "cachedInput": 3880000}}}, {"unit": "unread", "builder": {"cache24h": null}}]')
check "a warmed-up Builder under 95% cached raises a warning naming it and its action; a warming one or one over does not" \
  '["p: Builder low cache hit rate over the last 24 h is 80%, under 95%. Action: read the Builder'"'"'s session for a changed prefix or restarts"]' \
  "$(jq -c '[.alerts[] | select(.id | startswith("cache-builder-")) | .text]' <<<"$OUT")"
check "a Builder whose session log failed to read is not measured" 1 "$(jq '[.missing[] | select(. == "p: Builder unread 24 h cache hit rate")] | length' <<<"$OUT")"
# Issue 292: a parked unit (worktree false, no stage, no builder) is read by every unit rule and trips none.
OUT=$(units '[{"unit": "pk", "worktree": false, "stage": null, "role": "builder", "task": "task_7"}]')
check "a parked unit raises no alert and adds no unmeasured input to the empty list's" "0 $(jq '.missing | length' <<<"$(units '[]')")" "$(jq -r '"\(.alerts | length) \(.missing | length)"' <<<"$OUT")"
# Every alert names what to do about it: one fixture fires every rule, so a new rule with no action fails here.
iso() { jq -nr --argjson d "$1" 'now - $d | floor | todate'; }
NOW=$(date +%s)
ALL=$(jq -nc -f "$REAL/scripts/dashboard_alerts.jq" --argjson now "$NOW" --arg s7 "$(iso 604800)" --argjson hasSe true \
  --argjson se "[{\"role\": \"rev\", \"completedAt\": \"$(iso 60)\", \"tokens\": {\"input\": 100, \"cachedInput\": 50}},
    {\"role\": \"rev\", \"completedAt\": \"$(iso 259200)\", \"tokens\": {\"input\": 100, \"cachedInput\": 100}}]" \
  --argjson parts "[{\"mcpDown\": [{\"server\": \"serena\", \"at\": $((NOW - 60))}], \"host\": {\"swap\": {\"totalMb\": 1000, \"usedMb\": 900}},
    \"limit\": {\"usedPct\": 80, \"goalPct\": 50, \"codex\": {\"usedPct\": 80, \"goalPct\": 50},
      \"api\": {\"limitUsd\": 100, \"spentUsd\": 80, \"goalUsd\": 50}, \"cacheWritePct24h\": 9},
    \"projects\": {\"p\": {\"guardBlocks\": {\"lastHour\": 40, \"perHour\": 1},
      \"units\": {\"inFlight\": [{\"unit\": \"u\", \"stage\": \"building\", \"stageSince\": \"$(iso 10800)\",
        \"builder\": {\"signals\": [{\"kind\": \"stalled\", \"since\": $NOW}], \"cache24h\": {\"input\": 4000000, \"cachedInput\": 3200000}}}]},
      \"needsOwner\": {\"decisions\": [{\"id\": \"q1\", \"askedAt\": \"$(iso 7200)\", \"question\": \"which?\"}],
        \"unsent\": [{\"id\": \"q0\", \"to\": \"main\", \"state\": \"gave-up\", \"reason\": \"its main folder /x is gone\", \"firstAt\": \"$(iso 60)\"}]},
      \"mainEvents\": {\"carried\": [{\"cp\": \"/x/m1.md\", \"at\": \"$(iso 600)\", \"items\": 2, \"restartedAt\": null}]},
      \"sources\": {\"builder-logs\": {\"status\": \"stale\", \"staleSince\": \"$(iso 600)\"}}}}}]" \
  --argjson srcs "[{\"projects\": {\"status\": \"stale\", \"staleSince\": \"$(iso 600)\"}}]" --argjson preva '[{}]')
check "the all-rules fixture fires each of the 17 rules, and every alert's text names its action" "17 17" \
  "$(jq '[.alerts[].id | sub("-[0-9]+$"; "")] | unique | length' <<<"$ALL") $(jq '[.alerts[] | select(.text | test("[.] Action: [a-z]"))] | length' <<<"$ALL")"
# Issue 295: an answer main never got is the owner's order lost. The host gave up on it, or it has failed for 10 min:
# a critical alert naming why. One failing for under 10 min is still the host's to retry, and raises none.
unsent() { jq -nc -f "$REAL/scripts/dashboard_alerts.jq" --argjson now "$NOW" --arg s7 "$(iso 604800)" --argjson hasSe false \
  --argjson se '[]' --argjson parts "[{\"projects\": {\"p\": {\"needsOwner\": {\"decisions\": [], \"unsent\": $1}}}}]" --argjson srcs '[]' --argjson preva '[{}]'; }
OUT=$(unsent "[{\"id\": \"a\", \"to\": \"main\", \"state\": \"gave-up\", \"reason\": \"not delivered in 1 h, last: boom\", \"firstAt\": \"$(iso 3700)\"},
  {\"id\": \"b\", \"to\": \"relay\", \"state\": \"pending\", \"lastError\": \"no route\", \"firstAt\": \"$(iso 660)\"},
  {\"id\": \"c\", \"to\": \"main\", \"state\": \"pending\", \"lastError\": \"no route\", \"firstAt\": \"$(iso 60)\"}]")
check "issue 295: a gave-up answer and one failing 10 min raise critical alerts with the reason; a newer failure none" \
  '["crit p: the answer to a is not sent to main and the host gave up: not delivered in 1 h, last: boom","crit p: the answer to b is not sent to the relay: no route"]' \
  "$(jq -c '[.alerts[] | select(.id | startswith("answer-p-")) | "\(.severity) \(.text | sub("[.] Action:.*"; ""))"]' <<<"$OUT")"
# Issue 274: an alert that cleared was gone from the card with no trace. One raised in a run and not in the next is
# resolved, with when it began and when it cleared, and its text. The kept starts written before this were bare numbers.
held() { jq -nc -f "$REAL/scripts/dashboard_alerts.jq" --argjson now "$NOW" --arg s7 "$(iso 604800)" --argjson hasSe false \
  --argjson se '[]' --argjson parts "[{\"host\": $1, \"projects\": {}}]" --argjson srcs '[]' --argjson preva "[$2]"; }
HOT='{"swap": {"totalMb": 1000, "usedMb": 900}}' COOL='{"swap": {"totalMb": 1000, "usedMb": 10}}'
OUT=$(held "$HOT" '{"host-swap": 900000000}')
check "issue 274: a start kept as a bare number still dates the alert" '["host-swap-900000000"]' "$(jq -c '[.alerts[].id]' <<<"$OUT")"
check "issue 274: an alert still raised is not resolved" '[]' "$(jq -c .resolved <<<"$OUT")"
OUT=$(held "$COOL" "$(jq -c .since <<<"$OUT")")
check "issue 274: an alert gone in the next run is resolved with its start, clear time and text, and is not open" \
  "[] host-swap 1998-07-09T16:00:00Z $(jq -nr --argjson n "$NOW" '$n | todate') true" \
  "$(jq -r '"\(.alerts) \(.resolved[0].key) \(.resolved[0].since) \(.resolved[0].resolvedAt) \(.resolved[0].text | startswith("Host swap 90% used"))"' <<<"$OUT")"
# Host issue 3147: a stamp (pane-budget-gate.sh) under 10 min old raises one alert naming the server and what to do; an old one none.
mcpdown() { jq -nc -f "$REAL/scripts/dashboard_alerts.jq" --argjson now "$NOW" --arg s7 "$(iso 604800)" --argjson hasSe false \
  --argjson se '[]' --argjson parts "[{\"mcpDown\": $1, \"projects\": {}}]" --argjson srcs '[]' --argjson preva '[{}]'; }
check "a fresh mcp-down stamp raises one alert; an old one, or none, raises none" "1 0 0" \
  "$(mcpdown "[{\"server\": \"serena\", \"at\": $((NOW - 60))}]" | jq '[.alerts[] | select(.id | startswith("mcp-down-serena-"))] | length') $(mcpdown "[{\"server\": \"serena\", \"at\": $((NOW - 700))}]" | jq '[.alerts[] | select(.id | startswith("mcp-down-"))] | length') $(mcpdown '[]' | jq '[.alerts[] | select(.id | startswith("mcp-down-"))] | length')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
