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
# --- a Codex price comes from the parts of the model's name, never from a guess ---
# The owner ruled out one price row per Codex id: the rule reads the version and the tier
# the name states, then the mode and the prompt size. A new version of a known tier takes
# the tier's price (#36, the owner's ruling) and says so; a name with no known tier stays
# unpriced and the total partial, never a guessed number.
cx() { (cd "$ROOT/scripts" && python3 -c '
import sys, dashboard_limit as d
def usd(model, inp, out=1000):
    p = d.price([0, model, inp, 0, 0, 0, out])
    return None if p is None else round(p, 6)
print(eval(sys.argv[1]))' "$1" 2>&1); }
check "a published Codex id is priced by the rule: \$2 and \$10 per million" 0.41 "$(cx 'usd("gpt-6.1-sol", 200_000)')"
check "its long-prompt rate past 272K comes from the same rule" 1.215 "$(cx 'usd("gpt-6.1-sol", 300_000)')"
check "and its fast mode, Codex's priority tier, too" 0.82 "$(cx 'usd("gpt-6.1-sol:fast", 200_000)')"
check "the other published id, normal and fast, long and short" "[2.05, 6.075, 4.1, 12.15]" \
  "$(cx '[usd(m, n) for m in ("gpt-6-astra", "gpt-6-astra:fast") for n in (200_000, 300_000)]')"
# luna is published (#47, list prices read 2026-10-14): $0.10 in, $0.50 out, $0.20 and $0.75 past 272K, fast doubles the short rate.
check "gpt-6-luna is priced from its published rows: short, long, fast, fast long" "[0.0205, 0.06075, 0.041, 0.1215]" \
  "$(cx '[usd(m, n) for m in ("gpt-6-luna", "gpt-6-luna:fast") for n in (200_000, 300_000)]')"
check "a new version of luna takes luna's price, by tier" "[0.0205, True, False]" \
  "$(cx '[usd("gpt-6.1-luna", 200_000), d.by_tier([0, "gpt-6.1-luna", 1, 0, 0, 0, 1]), d.by_tier([0, "gpt-6-luna", 1, 0, 0, 0, 1])]')"
check "no Codex id has a row of its own in the price tables" "[]" "$(cx '[m for m in (*d.PRICES, *d.LONG_PRICES) if m.startswith("gpt-")]')"
check "a new version of a known tier takes the tier's price, every mode and prompt size" \
  "[0.41, 1.215, 0.82, 0.41, 2.05, 12.15]" \
  "$(cx '[usd("gpt-6.2-sol", 200_000), usd("gpt-6.2-sol", 300_000), usd("gpt-6.2-sol:fast", 200_000), usd("gpt-7-sol", 200_000), usd("gpt-6.1-astra", 200_000), usd("gpt-7-astra:fast", 300_000)]')"
check "a tier-priced figure says it is by tier, and a published id's price does not" "[True, True, True, False, False, False, False]" \
  "$(cx '[d.by_tier([0, m, 1, 0, 0, 0, 1]) for m in ("gpt-6.2-sol", "gpt-6.2-sol:fast", "gpt-6.1-astra", "gpt-6.1-sol", "gpt-6-astra:fast", "gpt-9-nova", "claude-opus-5-5")]')"
check "a name with no known tier, or any part the rule does not know, stays unpriced" "[None, None, None, None, None, None, None]" \
  "$(cx '[usd(m, 1000) for m in ("gpt-6.1-sol-mini", "gpt-6-lunar", "gpt-9-nova", "gpt-6.1-sol-2026-10-01", "gpt-6.1-sol:flex", "xgpt-6.1-sol", "gpt-6.1-sol ")]')"
check "and it is named as left out of the total" "['gpt-9-nova', 'gpt-6.1-sol-mini']" \
  "$(cx 'd.unpriced_models([[0, "gpt-9-nova", 1, 0, 0, 0, 1], [0, "gpt-6.2-sol", 1, 0, 0, 0, 1], [0, "gpt-6.1-sol-mini", 1, 0, 0, 0, 1]])[::-1]')"
check "the week and the day carry the tier-priced dollars, and an unknown tier leaves the total partial" "[0.41, 0.82, False, ['gpt-9-nova']]" \
  "$(cx '[round(w[k], 6) if isinstance(w[k], float) else w[k] for w in [d.api_week(None, [], 1e9, [[1e9, "gpt-6.2-sol", 200_000, 0, 0, 0, 1000], [1e9, "gpt-6.1-sol", 200_000, 0, 0, 0, 1000], [1e9, "gpt-9-nova", 1, 0, 0, 0, 1]])] for k in ("tierUsd", "codexUsd", "complete", "unpricedModels")]')"
check "a rule-priced Codex fast mode is a published price, not an estimate" False "$(cx 'd.estimated([0, "gpt-6.1-sol:fast", 1, 0, 0, 0, 1])')"
# Every Claude row exactly as it was before the rule: the rule is for Codex names only.
check "every Claude price row is unchanged" True "$(cx '{m: p for m, p in d.PRICES.items() if m.startswith("claude-")} == {
    "claude-fable-5-1": (10.0, 50.0, 0.25), "claude-opus-5-5": (4.0, 20.0, 0.20), "claude-opus-4-8": (5.0, 25.0, 0.50),
    "claude-sonnet-5-5": (2.0, 10.0, 0.10), "claude-haiku-5-5": (0.10, 0.50, 0.01), "claude-opus-5-5:fast": (8.0, 40.0, 0.40),
    "claude-opus-4-8:fast": (10.0, 50.0, 1.00)} and {m: p for m, p in d.LONG_PRICES.items() if m.startswith("claude-")} == {
    "claude-haiku-5-5": (0.50, 2.50, 0.05), "claude-haiku-5-5:fast": (1.0, 5.0, 0.1)}')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
