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
# Codex's 7-day tile is for a subscription login only: how Codex is signed in is
# read from auth.json in its home (the kind only, never a token). An unreadable
# file is unknown, which hides nothing: a failed read must not hide the tile.
cx() { (cd "$ROOT/scripts" && python3 -c 'import sys, dashboard_limit as d; print(d.codex_billing(sys.argv[1]))' "$T/codex/sessions" 2>&1); }
mkdir -p "$T/codex/sessions"
check "no Codex sign-in: none" none "$(cx)"
echo '{"auth_mode": "chatgpt", "OPENAI_API_KEY": null, "tokens": {"id_token": "x"}}' > "$T/codex/auth.json"
check "a ChatGPT login: subscription" subscription "$(cx)"
echo '{"OPENAI_API_KEY": null, "tokens": {"id_token": "x"}}' > "$T/codex/auth.json"
check "an older file with login tokens and no mode: subscription" subscription "$(cx)"
echo '{"auth_mode": "apikey", "OPENAI_API_KEY": "sk-x"}' > "$T/codex/auth.json"
check "an API key: api" api "$(cx)"
echo '{"OPENAI_API_KEY": "sk-x"}' > "$T/codex/auth.json"
check "an older file with only an API key: api" api "$(cx)"
echo '{"auth_mode": "chatgpt"' > "$T/codex/auth.json"
check "an unreadable file: unknown" None "$(cx)"
# Codex keeps its sign-in in the system keyring when its config.toml says so, and writes no auth.json then: with no
# auth.json that sign-in is unknown, so a failed usage read does not hide a keyring subscription's tile.
rm "$T/codex/auth.json"
for s in keyring auto ephemeral; do
  printf 'model = "gpt-5"\n[profiles.work]\ncli_auth_credentials_store = "%s"\n' "$s" > "$T/codex/config.toml"
  check "no auth.json, sign-in kept by Codex's $s store: unknown" None "$(cx)"
done
# Every TOML spelling of the key names the same store: quoted, dotted, or inside an inline table.
for k in '"cli_auth_credentials_store" = "keyring"' "'cli_auth_credentials_store' = 'keyring'" \
  'profiles.work.cli_auth_credentials_store = "keyring"' 'profiles."work".cli_auth_credentials_store="keyring"' \
  '[profiles]
work = { "cli_auth_credentials_store" = "keyring" }'; do
  printf 'model = "gpt-5"\n%s\n' "$k" > "$T/codex/config.toml"
  check "no auth.json, keyring store named as: $k" None "$(cx)"
done
printf 'cli_auth_credentials_store = "file"\n' > "$T/codex/config.toml"
check "no auth.json with the file store named: none" none "$(cx)"
printf 'cli_auth_credentials_store = "file"\n[\n' > "$T/codex/config.toml"
check "an unreadable config.toml: unknown" None "$(cx)"
# Codex reads no auth.json with its keyring or in-memory store: a file left from before says nothing; "auto" uses it.
echo '{"auth_mode": "apikey", "OPENAI_API_KEY": "sk-x"}' > "$T/codex/auth.json"
printf 'cli_auth_credentials_store = "keyring"\n' > "$T/codex/config.toml"
check "an old API-key auth.json beside the keyring store: unknown" None "$(cx)"
printf "cli_auth_credentials_store = 'auto'\n" > "$T/codex/config.toml"
check "an API-key auth.json with the auto store: api" api "$(cx)"
rm "$T/codex/config.toml" "$T/codex/auth.json"
# The sessions folder is optional to the collector: with none there is no Codex home to read, which is unknown,
# not a crash that loses the whole panel.
OUT=$(cd "$ROOT/scripts" && HOME="$T/home" python3 -B dashboard_limit.py build missing /nonexistent 0 "$T/dash/cache" /nonexistent 2>&1); RC=$?
check "no sessions folder given: the panel is still built, Codex's sign-in unknown" "0 null" "$RC $(jq -c .codexBilling <<<"$OUT" 2>&1)"
# A ChatGPT login kept in the system keyring writes no auth.json; its live 7-day reading still keeps the tile.
NOW=$(date +%s)
jq -cn --arg at "$(date -u -r $((NOW - 60)) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d @$((NOW - 60)) +%Y-%m-%dT%H:%M:%SZ)" --argjson r $((NOW + 86400)) \
  '{timestamp: $at, payload: {rate_limits: {secondary: {window_minutes: 10080, used_percent: 40, resets_at: $r}}}}' > "$T/codex/sessions/s.jsonl"
OUT=$(cd "$ROOT/scripts" && HOME="$T/home" python3 -B dashboard_limit.py build missing /nonexistent "$NOW" "$T/dash/cache" /nonexistent "$T/codex/sessions" 2>&1)
check "no auth.json but a live Codex 7-day reading: unknown, so the tile shows" "40 null" "$(jq -r '"\(.codex.usedPct) \(.codexBilling)"' <<<"$OUT" 2>&1)"
# The Codex limit alert follows how Codex is billed (codexBilling), not Claude's: a machine can pay Claude by API and Codex
# by subscription, or the other way round.
limit_ids() { jq -nc -f "$ROOT/scripts/dashboard_alerts.jq" --argjson now "$(date +%s)" --arg s7 2026-10-08 --argjson hasSe false \
  --argjson se '[]' --argjson parts "[{\"limit\": $1}]" --argjson srcs '[]' --argjson prev '{}' | jq -c '[.alerts[].id | sub("-[0-9]+$"; "")]'; }
check "Claude on API, Codex on a subscription and over its pace: the Codex alert is raised" '["limit-codex"]' \
  "$(limit_ids '{"billing": "api", "codexBilling": "subscription", "codex": {"usedPct": 95, "goalPct": 50}}')"
check "Claude on a subscription, Codex on API and over its pace: no Codex alert" '[]' \
  "$(limit_ids '{"billing": "subscription", "codexBilling": "api", "codex": {"usedPct": 95, "goalPct": 50}}')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
