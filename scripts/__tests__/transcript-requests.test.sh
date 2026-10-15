#!/usr/bin/env bash
# transcript-requests.test.sh -- one API request is counted and priced once, by
# every reader of Claude Code's transcripts. Behind a proxy a line may carry only
# requestId or only message.id: a request whose lines name it both ways was
# priced twice (#51), and a cache written under the old one-id key kept the old
# row beside the new one (#52). Claude Code 2.1.300 writes api-request,
# api-request-blob and api-request-shape rows, a third or more of a long log's
# bytes: no reader may count or price them, nor spend time parsing them, so one
# still half-written breaks no read (#71).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

# row <requestId> <message.id> -- one Haiku request of 100000 input tokens ($0.01); an empty id is left out.
row() { jq -cn --arg r "$1" --arg m "$2" '{type: "assistant", timestamp: "2026-10-10T12:00:00Z", cwd: "/proj", uuid: "u-\($r)-\($m)",
  message: ({model: "claude-haiku-5-5", usage: {input_tokens: 100000, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0}}
    + if $m == "" then {} else {id: $m} end)} + if $r == "" then {} else {requestId: $r} end'; }
# requests <dir> -- "<count> <dollars>" of what the dashboard's reader finds in <dir>/projects, through <dir>/cache.json.
requests() { (cd "$ROOT/scripts" && python3 -c '
import sys, dashboard_limit as d
rows = d.requests(sys.argv[1] + "/projects", sys.argv[1] + "/cache.json", 0, d.epoch("2026-10-10T13:00:00Z"))
print(len(rows), round(sum(d.price(r) for r in rows), 6))' "$1" 2>&1); }
fresh() { rm -rf "$T/$1"; mkdir -p "$T/$1/projects/p"; echo "$T/$1/projects/p/s.jsonl"; }

# --- #51: lines that share either id are one request ---
L=$(fresh one); { row r1 ""; row "" m1; row r1 m1; } > "$L"
check "requestId only, message.id only and both: one request, priced once" "1 0.01" "$(requests "$T/one")"
L=$(fresh later); { row r1 ""; row "" m1; } > "$L"; requests "$T/later" >/dev/null; row r1 m1 >> "$L"
check "a line read later that names both ids joins the two cached rows" "1 0.01" "$(requests "$T/later")"
L=$(fresh before); row r1 m1 > "$L"; requests "$T/before" >/dev/null; { row r1 ""; row "" m1; } >> "$L"
check "lines read later under either id join the cached request" "1 0.01" "$(requests "$T/before")"

# --- #52: a cache from before the ids were joined is read again, not trusted ---
L=$(fresh upgrade); row r1 "" > "$L"
jq -cn --arg p "$L" --argjson off "$(wc -c < "$L")" \
  '{version: 5, offsets: {($p): $off}, requests: {r1: [1791633600, "claude-haiku-5-5", 100000, 0, 0, 0, 0]}, cwd: {r1: "/proj"}}' > "$T/upgrade/cache.json"
row r1 m1 >> "$L"
check "a version-5 cache holding r1, then a line with r1 and m1: one request" "1 0.01" "$(requests "$T/upgrade")"

# --- #71: a 2.1.300 log, its assistant rows among the new api-request rows ---
# The new rows' shapes are those a 2.1.300 session writes, with short contents.
mkdir -p "$T/v300/projects/p" "$T/old/projects/p"
TORN='{"type":"api-request-shape","sessionId":"s","shapeHash":"h2","shape":{"system":[{"type":"te'
{
  printf '{"parentUuid":null,"type":"user","timestamp":"2026-10-10T11:59:00Z","cwd":"/proj","message":{"role":"user","content":"price the week"}}\n'
  printf '{"type":"api-request-shape","sessionId":"s","shapeHash":"h1","timestamp":"2026-10-10T11:59:01Z","version":"2.1.300","shape":{"system":[{"type":"text","text":"You are Claude Code."}],"tools":[{"name":"Bash","input_schema":{"type":"object","properties":{"command":{"type":"string"}}}}]}}\n'
  printf '{"type":"api-request-blob","sessionId":"s","hash":"b1","message":{"role":"user","content":[{"type":"text","text":"price the week"}]}}\n'
  printf '{"type":"api-request","sessionId":"s","id":"a1","timestamp":"2026-10-10T11:59:02Z","version":"2.1.300","querySource":"sdk","shapeHash":"h1","params":{"model":"claude-haiku-5-5","max_tokens":64000},"keep":0,"tail":["b1"],"requestDigest":"d1"}\n'
  # One request streamed as two lines, then a second request: $0.01 and $0.02.
  row r1 m1; row r1 m1
  printf '{"type":"api-request-blob","sessionId":"s","hash":"b2","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}\n'
  printf '{"type":"api-request","sessionId":"s","id":"a2","timestamp":"2026-10-10T12:00:03Z","version":"2.1.300","querySource":"sdk","shapeHash":"h1","params":{"model":"claude-opus-5-5","max_tokens":64000},"keep":0,"tail":["b2"],"requestDigest":"d2"}\n'
  printf '{"type":"assistant","timestamp":"2026-10-10T12:00:04Z","cwd":"/proj","uuid":"u2","requestId":"r2","message":{"id":"m2","model":"claude-opus-5-5","usage":{"input_tokens":0,"output_tokens":1000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"done"}]}}\n'
  # A log read while Claude Code writes its next request: the shape row is half-written.
  printf %s "$TORN"
} > "$T/v300/projects/p/s.jsonl"
grep -v '^{"type":"api-request' "$T/v300/projects/p/s.jsonl" > "$T/old/projects/p/s.jsonl"
check "the dashboard counts and prices the 2.1.300 log's assistant rows alone" "2 0.03" "$(requests "$T/v300")"

usage() { bash "$ROOT/scripts/seat-event.sh" --usage claude "$1" 2>&1; }
check "a seat's tokens from a 2.1.300 log are its assistant rows' tokens" \
  '{"model":"claude-opus-5-5","tokens":{"input":100000,"cachedInput":0,"output":1000}}' "$(usage "$T/v300/projects/p/s.jsonl")"

# unit-cost.sh reads a unit's folder under the workspaces root's slug.
cost() { HOME=$T/home-$1 COMMANDECK_WORKSPACES=$T/ws bash "$ROOT/scripts/unit-cost.sh" u '2000-01-01 00:00' 2>/dev/null | grep '^TOTAL'; }
for k in v300 old; do
  D=$T/home-$k/.claude/projects/$(printf %s "$T/ws" | tr -c 'A-Za-z0-9' '-')-u; mkdir -p "$D"; cp "$T/$k/projects/p/s.jsonl" "$D/"
done
check "unit-cost.sh's turns and tokens on a 2.1.300 log are its assistant rows'" "$(cost old)" "$(cost v300)"
check "and that is two turns" 1 "$(cost v300 | grep -c '^TOTAL      2 turns')"

# jq keeps a repeated key's last value, so parsed, this row would read as a turn of 7 tokens.
{ row r1 m1; printf '{"type":"api-request","sessionId":"s","type":"assistant","message":{"id":"m9","model":"claude-opus-5-5","usage":{"input_tokens":7}}}\n'; } > "$T/dup.jsonl"
check "a seat's tokens skip an api-request row unparsed" \
  '{"model":"claude-haiku-5-5","tokens":{"input":100000,"cachedInput":0,"output":0}}' "$(usage "$T/dup.jsonl")"

# read-verdict.sh and builder-cache-check.sh find a worktree's logs under $HOME's projects folder.
plog() { local d; d=$T/home-rv/.claude/projects/$(printf %s "$T/$1" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$T/$1" "$d/s/subagents"; echo "$d/s.jsonl"; }
L=$(plog seat)
{ printf '{"type":"user","timestamp":"2026-10-10T11:59:00Z","message":{"role":"user","content":"do task T-71"}}\n'
  printf '{"type":"assistant","timestamp":"2026-10-10T11:59:05Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}\n'
  printf %s "$TORN"; } > "$L"
check "a seat mid-turn, its next request half-written: running, not a partial record" "state=running" \
  "$(HOME=$T/home-rv bash "$ROOT/scripts/read-verdict.sh" --state --worktree "$T/seat" --agent claude --task T-71 2>&1 | grep '^state=')"
L=$(plog review)
{ printf '{"type":"user","timestamp":"2026-10-10T11:59:00Z","message":{"role":"user","content":"review it"}}\n'
  printf '{"type":"assistant","timestamp":"2026-10-10T11:59:05Z","message":{"role":"assistant","content":[{"type":"text","text":"VERDICT: GO"}]}}\n'
  printf %s "$TORN"; } > "$L"
check "a reviewer's verdict is read with its next request half-written" "VERDICT: GO" \
  "$(cd "$ROOT" && HOME=$T/home-rv COMMANDECK_SCRATCH=$T/scratch bash scripts/read-verdict.sh h-71 5 "$T/review" claude "" "" 0 1 2>&1 | grep -m1 '^VERDICT:')"
L=$(plog builder)
{ printf '{"type":"assistant","message":{"usage":{"cache_creation":{"ephemeral_1h_input_tokens":10}}}}\n'; printf %s "$TORN"; } > "$L"
printf '{"type":"assistant","message":{"usage":{"cache_creation":{"ephemeral_5m_input_tokens":10}}}}\n' > "${L%.jsonl}/subagents/agent-a.jsonl"
check "the cache check reads a live Builder log, its next request half-written" \
  "s.jsonl: main thread 1h=10 5m=0; 1 subagent transcript(s) 1h=0 5m=10" \
  "$(cd "$ROOT" && HOME=$T/home-rv bash scripts/builder-cache-check.sh "$T/builder" 2>&1)"

prompts() { python3 "$ROOT/scripts/checkpoint-context.py" messages "$1" 10000 2>&1 | tail -n +3; }
check "a restart carries the 2.1.300 log's one prompt, and no blob as a prompt" \
  "$(printf '<<< prompt 1 of 1\nprice the week\n>>> end prompt 1')" "$(prompts "$T/v300/projects/p/s.jsonl")"

# Speed: a reader that parses every line skips the new rows before parsing them.
# parsed <python that reads $1> -- how many api-request rows it handed to json.loads.
parsed() { (cd "$ROOT/scripts" && python3 -c '
import importlib.util, json, sys
seen, loads = [], json.loads
json.loads = lambda s, *a, **k: (seen.append(bytes(s, "utf-8") if isinstance(s, str) else s), loads(s, *a, **k))[1]
def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), name + ".py")
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
exec(sys.argv[1])
print(sum(s.startswith(b"{\"type\":\"api-request") for s in seen))' "$1" "$T" 2>&1); }
check "the dashboard parses none of the new rows" 0 "$(parsed 'load("dashboard_limit").requests(sys.argv[2] + "/v300/projects", sys.argv[2] + "/parse.json", 0, 1791640000)')"
check "the restart's prompt reader parses none of the new rows" 0 "$(parsed 'load("checkpoint-context").prompt_block(sys.argv[2] + "/v300/projects/p/s.jsonl", 10000)')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
