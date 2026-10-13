#!/usr/bin/env bash
# dashboard-limit-unreadable.test.sh -- the collector reads every Claude
# transcript on the machine. What this pins: one it cannot open (permissions,
# or deleted between the listing and the read) stops no card from refreshing.
# One that is there and cannot be read leaves the totals unknown: a count of
# the rest would be short, and the dashboard would show it as the whole.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'chmod -R u+rw "$T"; rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

mkdir -p "$T/projects/a"
ROW='{"type":"assistant","requestId":"r1","timestamp":"2026-10-10T12:00:00Z","message":{"model":"claude-haiku-5-5","usage":{"input_tokens":10,"output_tokens":5}}}'
echo "$ROW" > "$T/projects/a/good.jsonl"; echo "$ROW" > "$T/projects/a/locked.jsonl"; chmod 000 "$T/projects/a/locked.jsonl"
OUT=$(cd "$ROOT/scripts" && python3 -c '
import sys, dashboard_limit as d
now = d.epoch("2026-10-10T13:00:00Z")
rows = d.requests(sys.argv[1], sys.argv[2], now - 86400, now)
print(rows if rows is None else len(rows))' "$T/projects" "$T/cache.json" 2>&1)
count() { (cd "$ROOT/scripts" && python3 -c '
import sys, dashboard_limit as d
now = d.epoch("2026-10-10T13:00:00Z")
rows = d.requests(sys.argv[1], sys.argv[2], now - 86400, now)
print(rows if rows is None else len(rows))' "$T/projects" "$T/cache.json" 2>&1); }
check "with a transcript it cannot read, the total is unknown, not short" None "$OUT"
echo "${ROW/r1/r2}" > "$T/projects/a/locked2.jsonl"; chmod 644 "$T/projects/a/locked.jsonl"
check "once it can be read, every request is counted" 2 "$(count)"
rm "$T/projects/a/locked2.jsonl"
check "a transcript deleted since is no failed reading: its requests stay counted" 2 "$(count)"
# A folder it cannot list hides every transcript under it: the same unknown.
mkdir "$T/projects/b"; echo "${ROW/r1/r3}" > "$T/projects/b/hidden.jsonl"; chmod 000 "$T/projects/b"
check "with a transcript folder it cannot list, the total is unknown, not short" None "$(count)"
chmod 755 "$T/projects/b"
check "once it can be listed, every request is counted" 3 "$(count)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
