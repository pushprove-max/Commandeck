#!/usr/bin/env bash
# transcript-requests.test.sh -- one API request is counted and priced once, by
# every reader of Claude Code's transcripts. Behind a proxy a line may carry only
# requestId or only message.id: a request whose lines name it both ways was
# priced twice (#51), and a cache written under the old one-id key kept the old
# row beside the new one (#52). Claude Code 2.1.300 writes api-request,
# api-request-blob and api-request-shape rows, a third or more of a long log's
# bytes: no reader may count or price them, nor spend time parsing them, so one
# still half-written breaks no read (#71). Each request keeps the transcript it came from, so a planning seat's spend
# is told from its session's file; a cache from before is read again.
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

# --- each request keeps the transcript it came from, so a planning seat's spend is told from its session's file ---
# A cache from before (Claude's version 6, Codex's version 3) holds no file for a request: it is read again.
L=$(fresh files); row r1 m1 > "$L"
jq -cn --arg p "$L" --argjson off "$(wc -c < "$L")" \
  '{version: 6, offsets: {($p): $off}, requests: {r1: [1791633600, "claude-haiku-5-5", 100000, 0, 0, 0, 0]}, cwd: {r1: "/proj"}, alias: {r1: "r1", m1: "r1"}}' > "$T/files/cache.json"
check "a version-6 cache is read again, and each row carries its folder and its transcript" "1 /proj $L" \
  "$(cd "$ROOT/scripts" && python3 -c '
import sys, dashboard_limit as d
rows = d.requests(sys.argv[1] + "/projects", sys.argv[1] + "/cache.json", 0, d.epoch("2026-10-10T13:00:00Z"), True)
print(len(rows), *[x for t in rows for x in t[1:]])' "$T/files" 2>&1)"
X=$T/cx/sessions/2026/10/10/rollout-a.jsonl; mkdir -p "${X%/*}"
printf '%s\n' '{"type":"session_meta","timestamp":"2026-10-10T12:00:00Z","payload":{"cwd":"/ws/pu-plan"}}' \
  '{"type":"token_usage_record","timestamp":"2026-10-10T12:00:05Z","payload":{"response_id":"x1","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":1}}}' > "$X"
jq -cn --arg p "$X" --argjson off "$(wc -c < "$X")" \
  '{version: 3, files: {($p): [$off, null, null, "/ws/pu-plan"]}, requests: {x1: [1791633605, "unknown Codex model", 10, null, 0, 0, 1]}, cwd: {x1: "/ws/pu-plan"}}' > "$T/cx/cache.json"
check "a version-3 Codex cache is read again, and each row carries its folder and its rollout" "1 /ws/pu-plan $X" \
  "$(cd "$ROOT/scripts" && python3 -c '
import sys, dashboard_limit as d
rows = d.codex_requests(sys.argv[1] + "/sessions", sys.argv[1] + "/cache.json", 0, d.epoch("2026-10-10T13:00:00Z"), None, True)
print(len(rows), *[x for t in rows for x in t[1:]])' "$T/cx" 2>&1)"

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
{ printf '{"type":"assistant","message":{"usage":{"cache_creation":{"ephemeral_5m_input_tokens":10}}}}\n'; printf %s "$TORN"; } > "$L"
printf '{"type":"assistant","message":{"usage":{"cache_creation":{"ephemeral_5m_input_tokens":10}}}}\n' > "${L%.jsonl}/subagents/agent-a.jsonl"
check "the cache check reads a live Builder log, its next request half-written" \
  "s.jsonl: main thread 1h=0 5m=10; 1 subagent transcript(s) 1h=0 5m=10" \
  "$(cd "$ROOT" && HOME=$T/home-rv bash scripts/builder-cache-check.sh "$T/builder" 2>&1)"
# The order of 2026-10-18 replaced the Builder's 1h pin: a main thread still writing 1h cache must fail the check.
printf '{"type":"assistant","message":{"usage":{"cache_creation":{"ephemeral_1h_input_tokens":10}}}}\n' > "$L"
HOME=$T/home-rv bash "$ROOT/scripts/builder-cache-check.sh" "$T/builder" >/dev/null 2>&1
check "the cache check fails a Builder whose main thread wrote 1h cache" 1 "$?"

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

# --- #96: a proxy's form of a model id is priced at its PRICES row; an unknown id stays unpriced ---
# One million input tokens each, so the price is the row's input rate (Haiku's over-100K one).
priced() { (cd "$ROOT/scripts" && python3 -c '
import sys, dashboard_limit as d
for m in sys.argv[1:]:
    r = d.request_row({"type": "assistant", "timestamp": "2026-10-10T12:00:00Z", "message": {"model": m, "usage": {"input_tokens": 1000000,
        "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0}}})
    print(r[1], d.price(r), ",".join(d.unpriced_models([r])) or "-")' "$@" 2>&1 | paste -sd' ' -); }
check "dotted and prefixed ids price at the 5-5 rates" "claude-haiku-5-5 0.5 - claude-sonnet-5-5 2.0 - claude-opus-5-5 4.0 - claude-opus-5-5 4.0 -" \
  "$(priced claude-haiku-5.5 claude-sonnet-5.5 anthropic/claude-opus-5.5 claude-opus-5-5-20261001)"
check "an unknown id is still unpriced, by its own name" "claude-mystery-9-9 None claude-mystery-9-9 claude-3-sonnet None claude-3-sonnet" \
  "$(priced claude-mystery-9.9 claude-3-sonnet)"

# --- #94: a Builder's cost by stage, from its worktree's own transcripts (helpers' included) ---
# Building 12:00-12:30, a review pass to 12:40, fixing since; now is 12:50. Haiku rows are $0.01 each.
WT=$T/uc/ws/u1; D=$T/uc/projects/$(printf %s "$WT" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$WT" "$D/s/subagents" "$T/uc/sessions"
urow() { row "$1" "" | jq -c --arg t "$2" --arg m "${3:-claude-haiku-5-5}" --arg w "$WT" '.timestamp = $t | .cwd = $w | .message.model = $m'; }
{ urow a1 2026-10-10T12:05:00Z; urow a2 2026-10-10T12:35:00Z claude-mystery-9-9; urow a3 2026-10-10T12:45:00Z; } > "$D/s.jsonl"
urow h1 2026-10-10T12:10:00Z > "$D/s/subagents/agent-h1.jsonl"
# The stages are the ones dashboard_builders.jq reads from the Builder's event log: its first row, a pass, a fix.
printf '%s\n' '{"event":"tool-start","ts":"2026-10-10T12:00:00Z","tool":"Read","use":"t1"}' '{"event":"tool-end","ts":"2026-10-10T12:00:01Z","use":"t1"}' \
  '{"event":"codex-start","ts":"2026-10-10T12:30:00Z","pass":"adversarial","round":1}' '{"event":"codex-end","ts":"2026-10-10T12:40:00Z","pass":"adversarial","round":1,"rc":0}' > "$T/uc/log.jsonl"
ucost() { jq -s --argjson now 0 -f "$ROOT/scripts/dashboard_builders.jq" "$T/uc/log.jsonl" | jq -c --arg w "$WT" '[{unit: "u1", worktree: $w, stages: .stageHistory}]' \
  | python3 "$ROOT/scripts/dashboard_limit.py" units "$(jq -n '"2026-10-10T12:50:00Z" | fromdate')" "$T/uc" "$T/uc/projects" "$T/uc/sessions" 2>&1 \
  | jq -r '.u1 | (.stages[] | "\(.stage) \(.sec) \(.calls) \(.usd) \(.partial) \(.unpriced | join(","))"), "total \(.total.sec) \(.total.calls) \(.total.usd) \(.total.partial) \(.total.unpriced | join(","))"' 2>&1 | paste -sd'|' -; }
check "each stage holds the requests made in it, a helper's included, and the total holds all of them" \
  "building 1800 2 0.02 false |review 600 1 0 true claude-mystery-9-9|fixing 600 1 0.01 false |total 3000 4 0.03 true claude-mystery-9-9" "$(ucost)"
# An install that runs Claude only has no Codex sessions folder: no Codex review ran, so its cost is none, not unknown.
rmdir "$T/uc/sessions"
check "with no Codex sessions folder, the Claude costs still count" "total 3000 4 0.03 true claude-mystery-9-9" "$(ucost | tr '|' '\n' | tail -1)"

# The build's total split between Claude and Codex: an agent with an unpriced call reads "not priced" (null),
# never $0 or a guess, and an agent with no call at all is $0.
check "the total's Claude part is unpriced and its Codex part, with no Codex call, is 0" "null 0" \
  "$(jq -s --argjson now 0 -f "$ROOT/scripts/dashboard_builders.jq" "$T/uc/log.jsonl" | jq -c --arg w "$WT" '[{unit: "u1", worktree: $w, stages: .stageHistory}]' \
  | python3 "$ROOT/scripts/dashboard_limit.py" units "$(jq -n '"2026-10-10T12:50:00Z" | fromdate')" "$T/uc" "$T/uc/projects" "$T/uc/sessions" 2>&1 | jq -r '.u1.total.byAgent | "\(.claude) \(.codex)"')"
split() { (cd "$ROOT/scripts" && python3 -c '
import dashboard_limit as d
row = lambda m: d.request_row({"type": "assistant", "timestamp": "2026-10-10T12:00:00Z", "message": {"model": m, "usage": {"input_tokens": 1000000,
    "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0}}})
b = d.by_agent([row("claude-haiku-5-5"), row("claude-haiku-5-5")], [row("claude-sonnet-5-5")])
u = d.by_agent([row("claude-haiku-5-5")], [row("claude-mystery-9-9")])
print(b["claude"], b["codex"], u["claude"], u["codex"])' 2>&1); }
check "a mixed build's parts add up to its total; an unpriced Codex call leaves the Codex part unpriced" "1.0 2.0 0.5 None" "$(split)"

# Two judges launched in one second share a planning worktree: each seat's ledger row names the log its own launch's
# tag was handed in, never the first log after the launch, or one log is charged to both seats.
SE=$T/home-se; SWT=$T/se-plan; SX=$SE/.codex/sessions/2026/10/17; mkdir -p "$SX" "$SWT"; git init -q "$T/se-main"
L0=$(( $(date +%s) - 60 ))
jrow() { printf '%s\n' "{\"type\":\"session_meta\",\"timestamp\":\"$(date -u -d "@$2" +%Y-%m-%dT%H:%M:%SZ)\",\"payload\":{\"cwd\":\"$SWT\"}}" \
  "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"Judge it. Seat tag $1.\"}]}}"; }
jrow seat-sol-1 $((L0 + 1)) > "$SX/rollout-sol.jsonl"; jrow seat-astra-1 $((L0 + 2)) > "$SX/rollout-astra.jsonl"
for s in sol astra; do
  HOME=$SE COMMANDECK_MAIN=$T/se-main COMMANDECK_SEAT_EVENTS=$T/se.jsonl SEAT_EVENT_WORKTREE=$SWT SEAT_EVENT_AGENT=codex SEAT_EVENT_SPEC=seat-$s-1 \
    bash "$ROOT/scripts/seat-event.sh" pu "plan-judge-$s" "task_$s" "$L0" >/dev/null 2>&1
done
check "each judge's ledger row names its own log" "rollout-sol.jsonl rollout-astra.jsonl" "$(jq -r '.session // "null" | split("/") | last' "$T/se.jsonl" 2>&1 | paste -sd' ' -)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
