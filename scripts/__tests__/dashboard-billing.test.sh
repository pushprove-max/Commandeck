#!/usr/bin/env bash
# The limit card picks its panel from billing(): a machine that reaches Claude through an API base URL (a
# proxy) has no subscription usage windows, so empty 5-hour and 7-day tiles there read as "not measured"
# forever (#97). The proxy is found in the environment or in ~/.claude/settings.json's env block, the two
# places Claude Code reads it from; billing.json's own word still wins.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.claude" "$T/dash/cache"
# mode [VAR=value...] -> billing()'s answer for the dashboard folder $T/dash
mode() { (cd "$ROOT/scripts" && env -u ANTHROPIC_BASE_URL HOME="$T/home" "$@" python3 -c '
import sys, dashboard_limit as d; print(*d.billing(sys.argv[1]))' "$T/dash/cache" 2>&1); }
check "no proxy, no billing.json: the subscription panel" "subscription None" "$(mode)"
check "a base URL in the environment: the API panel" "api None" "$(mode ANTHROPIC_BASE_URL=http://127.0.0.1:4141)"
echo '{"env": {"ANTHROPIC_BASE_URL": "http://127.0.0.1:4141"}}' > "$T/home/.claude/settings.json"
check "a base URL in Claude's settings: the API panel" "api None" "$(mode)"
echo '{"billing": "subscription"}' > "$T/dash/billing.json"
check "billing.json's own word wins over a proxy" "subscription None" "$(mode)"
echo '{"billing": "api", "weeklyLimitUsd": 1000}' > "$T/dash/billing.json"; rm "$T/home/.claude/settings.json"
check "billing.json alone still sets the API panel and its limit" "api 1000" "$(mode)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
