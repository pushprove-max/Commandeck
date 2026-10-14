#!/usr/bin/env bash
# dashboard-usage.test.sh -- on a fresh install the dashboard showed the weekly
# limit, the cost of the day and the token ledger all as "not measured" at once.
# What this pins: a refused usage check says how long the service asked it to
# wait, in seconds or as a date, and nothing when the service named no wait; one
# model with no price leaves the day's total standing as a partial one, with the
# count and the name of what is left out; and the day's cost does not need the
# refused usage reading at all. No call leaves this machine: the service is a
# stand-in inside the test.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

# refused <Retry-After value, or none> -- what the usage check says on stderr when the service answers 429.
refused() { (cd "$ROOT/scripts" && python3 -c '
import sys, email.message, urllib.error, urllib.request, dashboard_limit as d
from email.utils import formatdate
import time
h = email.message.Message()
if sys.argv[1] == "date": h["Retry-After"] = formatdate(time.time() + 600, usegmt=True)
elif sys.argv[1] != "none": h["Retry-After"] = sys.argv[1]
def no(*a, **k): raise urllib.error.HTTPError("u", 429, "Too Many Requests", h, None)
d.token = lambda: "t"; urllib.request.urlopen = no
sys.exit(d.fetch())' "$1" 2>&1 >/dev/null); }
check "a 429 with Retry-After in seconds names the wait" "rate limited (429); retry after 120 s" "$(refused 120)"
check "a 429 with Retry-After as a date names the same wait in seconds" 1 "$(refused date | grep -cE '^rate limited \(429\); retry after (59[0-9]|600) s$')"
check "a 429 with no Retry-After names no wait: the collector backs off on its own" "rate limited (429)" "$(refused none)"
check "a Retry-After that is neither is not turned into a wait" "rate limited (429)" "$(refused soon)"

# --- one unpriced model, and the usage reading refused ---
mkdir -p "$T/projects/a" "$T/cache"
row() { printf '{"type":"assistant","requestId":"%s","timestamp":"2026-10-10T12:00:00Z","cwd":"/proj","message":{"model":"%s","usage":{"input_tokens":1000000,"output_tokens":1000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0}}}}\n' "$1" "$2"; }
{ row r1 claude-haiku-5-5; row r2 mystery-1; row r3 mystery-1; } > "$T/projects/a/s.jsonl"
built() { (cd "$ROOT/scripts" && TZ=UTC python3 -c '
import sys, json, io, contextlib, dashboard_limit as d
now = d.epoch("2026-10-10T13:00:00Z")
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    d.build("not-measured", sys.argv[1] + "/none", now, sys.argv[1] + "/cache", sys.argv[1] + "/projects", None, {"demo": ["/proj"]})
out = json.loads(buf.getvalue())
one = d.price(d.request_row(json.loads(open(sys.argv[1] + "/projects/a/s.jsonl").readline())))
out["one"] = one
print(json.dumps(out))' "$T" 2>&1); }
OUT=$(built)
j() { jq -c "$1" <<<"$OUT" 2>&1; }
check "the priced request has a price at all" true "$(j '.one > 0')"
check "the day's total for the project stands, as the sum of what has a price" true "$(j '.today.demo.spentUsd == .one')"
check "it is marked incomplete, with the count left out" '[false,2]' "$(j '[.today.demo.complete, .today.demo.unpricedRequests]')"
check "and the model left out is named" '["mystery-1"]' "$(j '.today.demo.unpricedModels')"
# The limit panel's cost of the day hung on the usage reading: refused, the panel showed no cost at all.
check "with the usage reading refused the panel still has the day's cost, partial" true "$(j '.cost.today == .one')"
check "with its own count and model left out" '[2,["mystery-1"]]' "$(j '[.cost.todayUnpriced, .cost.unpricedModels]')"
check "and no week figure is made up without the reading" '[null,null,null]' "$(j '[.cost.week, .cost.projected, .usedPct]')"
check "the Codex models this plugin launches have a price, fast and normal" 4 "$(cd "$ROOT/scripts" && python3 -c '
import dashboard_limit as d
print(sum(m in d.PRICES for m in ("gpt-6.1-sol", "gpt-6.1-sol:fast", "gpt-6-astra", "gpt-6-astra:fast")))')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
