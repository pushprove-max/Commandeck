#!/usr/bin/env bash
# dashboard-proxy-keys.test.sh -- behind an API proxy (#47) Claude session lines carry no
# requestId, and the day's cost showed $0.00. What this pins: a line with no requestId is
# counted, keyed on message.id (a streamed request writes several lines with one message.id
# and different uuids), else on uuid; a repeat of any line counts once; and a log whose lines
# all carry a requestId totals what it did before. Prices are Haiku's: $0.10 per 1M input, the short-prompt rate (a prompt past 100K is priced higher).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

# line <ids as json members, trailing comma included> <input tokens>
line() { printf '{"type":"assistant",%s"timestamp":"2026-10-10T12:00:00Z","cwd":"/proj","message":{%s"model":"claude-haiku-5-5","usage":{"input_tokens":%s,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0}}}}\n' "$1" "$2" "$3"; }
spent() { # spent <dir>: the day's dollars, requests and unpriced requests for the log in <dir>/projects
  (cd "$ROOT/scripts" && TZ=UTC python3 -c '
import sys, json, io, contextlib, dashboard_limit as d
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    d.build("not-measured", sys.argv[1] + "/none", d.epoch("2026-10-10T13:00:00Z"), sys.argv[1] + "/cache", sys.argv[1] + "/projects", None, {"demo": ["/proj"]})
o = json.loads(buf.getvalue())["today"]["demo"]
print(round(o["spentUsd"], 6), o["requests"], o["unpricedRequests"])' "$1" 2>&1); }

mkdir -p "$T"/{a,b,c}/{projects/p,cache}
# a: proxied. m1 streamed on three lines (the last holds the final usage) and the last repeated;
# m2 once; a line with only a uuid, repeated.
{ line '"uuid":"u1",' '"id":"m1",' 10000
  line '"uuid":"u2",' '"id":"m1",' 20000
  line '"uuid":"u3",' '"id":"m1",' 100000
  line '"uuid":"u3",' '"id":"m1",' 100000
  line '"uuid":"u4",' '"id":"m2",' 100000
  line '"uuid":"u5",' '' 100000
  line '"uuid":"u5",' '' 100000; } > "$T/a/projects/p/s.jsonl"
check "proxied lines count: three requests, each once, the streamed one at its last line" "0.03 3 0" "$(spent "$T/a")"
# b: every line has a requestId and its request one message.id (one to one in real logs); uuid differs per line.
{ line '"requestId":"r1","uuid":"u1",' '"id":"m1",' 100000
  line '"requestId":"r1","uuid":"u2",' '"id":"m1",' 100000
  line '"requestId":"r2","uuid":"u3",' '"id":"m2",' 100000; } > "$T/b/projects/p/s.jsonl"
check "a log where every line has a requestId totals as before: two requests" "0.02 2 0" "$(spent "$T/b")"
# c: one request written with a requestId on one line and without on another keeps both: two keys.
{ line '"requestId":"r1","uuid":"u1",' '"id":"m1",' 100000
  line '"uuid":"u2",' '"id":"m2",' 100000
  line '' '' 100000; } > "$T/c/projects/p/s.jsonl"
check "a line with no id at all is skipped, not guessed" "0.02 2 0" "$(spent "$T/c")"
# d: a JSON array holding "usage" in the log must not stop the read.
mkdir -p "$T"/d/{projects/p,cache}
{ line '"requestId":"r1","uuid":"u1",' '"id":"m1",' 100000
  echo '["usage"]'; } > "$T/d/projects/p/s.jsonl"
check "a non-object line is skipped and the request still counts" "0.01 1 0" "$(spent "$T/d")"
# e: a cache from before message.id keys (version 4, keyed on requestId) is read again, not added to.
mkdir -p "$T"/e/{projects/p,cache}
line '"requestId":"r1","uuid":"u1",' '"id":"m1",' 100000 > "$T/e/projects/p/s.jsonl"
echo '{"version": 4, "offsets": {}, "requests": {"r1": [1, "claude-haiku-5-5", 1, 0, 0, 0, 1]}, "cwd": {}}' > "$T/e/cache/limit-requests.json"
check "an old cache is dropped and read again" "0.01 1 0" "$(spent "$T/e")"
echo "dashboard-proxy-keys: $PASS passed, $FAIL failed"; [ "$FAIL" = 0 ]
