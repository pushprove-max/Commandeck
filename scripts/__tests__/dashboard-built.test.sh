#!/usr/bin/env bash
# dashboard-built.test.sh -- a Builder's card says how many of its issues are built, read from its evidence file.
# Builders record each issue's status in a table (Issue and Status columns), most under a "## Per issue" heading,
# so a count that read only "## #<n>" headings said 1 built for builds that had built most of their issues, and
# the owner would chase work that was done. What this pins, on copies of two real evidence files (taken
# 2026-10-16; issue numbers carry a leading 1 so the leak check passes): a row whose status starts "built" counts,
# under "## Per issue" or under the title; a "partly built" row does not, even with a heading of its own.
# A Builder also carries its live context, from its session log, beside the clear line setup recorded for it.
# Also: each review stage carries its round; the home project is collected unless the registry lists none; and the
# WARM/QUIET signals and the session record readers. The fixture is fixtures/dashboard-built-setup.sh.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"
dash

check "every issue the Per issue table marks built counts as built" \
  '[[12639,12640,12641,12642,12643,12644,12645,12646,12647,12648,12649,12650,12651,12652,12653,12654,12655,12656]]' "$(built help-email-batch-2026-10-16)"
check "a table under the title counts too, and a partly built issue does not, though a heading names it" \
  '[[12556,12617,11775]]' "$(built api-batch-2026-10-16)"
check "a Builder carries the verdict of every round file by its own round, and the newest report's beside it" \
  '[{"1":"VERDICT: NO-GO","2":"VERDICT: GO"},"VERDICT: GO",2]' \
  "$(jq -c 'first(.[]) | .units.inFlight[]? | select(.unit == "u-verdicts") | [.builder.verdicts, .builder.verdict, .builder.verdictRound]' "$T/out/run/project.json" 2>&1)"
check "a Builder's live context from its session log, beside the clear line setup recorded" '[150012,"160000"]' \
  "$(jq -c 'first(.[]) | .units.inFlight[]? | select(.unit == "u-verdicts") | [.builder.context, .builder.clearLine]' "$T/out/run/project.json" 2>&1)"
check "one with no session log has no context to show" '[null]' "$(jq -c 'first(.[]) | [.units.inFlight[]? | select(.unit == "api-batch-2026-10-16") | .builder.context]' "$T/out/run/project.json" 2>&1)"
check "a raised Builder carries the effort main raised it to and why; one launched at the default carries none" '[{"effort":"high","reason":"touches billing"},null]' \
  "$(jq -c 'first(.[]) | [.units.inFlight[]? | select(.unit == "u-verdicts" or .unit == "api-batch-2026-10-16")] | sort_by(.unit) | reverse | map(.builder.raised)' "$T/out/run/project.json" 2>&1)"
# The stage list names each pass by its round, from the Builder's own log.
printf '%s\n' '{"event":"tool-start","ts":"2026-10-10T12:00:00Z","tool":"Read","use":"t1"}' '{"event":"tool-end","ts":"2026-10-10T12:00:01Z","use":"t1"}' \
  '{"event":"codex-start","ts":"2026-10-10T12:30:00Z","pass":"adversarial","round":1}' '{"event":"codex-end","ts":"2026-10-10T12:40:00Z","pass":"adversarial","round":1,"rc":0}' \
  '{"event":"codex-start","ts":"2026-10-10T12:50:00Z","pass":"review","round":2}' > "$T/log.jsonl"
check "each review stage carries its pass's round; building and fixing carry none" '[["building",null],["review",1],["fixing",null],["review",2]]' \
  "$(jq -s --argjson now 0 -f "$SOURCE/scripts/dashboard_builders.jq" "$T/log.jsonl" | jq -c '[.stageHistory[] | [.stage, .round]]')"

# A round run again after a failed try: the retry starts in the second the failed one ended. Each start pairs with the
# first end after it in the log, so the review time is 60 s + 300 s, not the first end counted twice.
printf '%s\n' '{"event":"tool-start","ts":"2026-10-10T11:59:00Z","tool":"Read","use":"t1"}' '{"event":"tool-end","ts":"2026-10-10T11:59:01Z","use":"t1"}' \
  '{"event":"codex-start","ts":"2026-10-10T12:00:00Z","pass":"review","round":2}' '{"event":"codex-end","ts":"2026-10-10T12:01:00Z","pass":"review","round":2,"rc":1}' \
  '{"event":"codex-start","ts":"2026-10-10T12:01:00Z","pass":"review","round":2}' '{"event":"codex-end","ts":"2026-10-10T12:06:00Z","pass":"review","round":2,"rc":0}' > "$T/retry.jsonl"
check "a retried pass of the same round keeps both tries in the review time" 360 \
  "$(jq -s --argjson now 0 -f "$SOURCE/scripts/dashboard_builders.jq" "$T/retry.jsonl" | jq -c '.reviewSec')"

# The dashboard off for every project (the registry exists and lists none) collects no home project either; a job
# installed before any registration (no registry yet) keeps collecting it.
off() { rm -rf "$T/out2"; mkdir -p "$T/out2"; case ${1:-} in "") ;; EMPTY) : > "$T/out2/projects" ;; *) printf '%s\n' "$1" > "$T/out2/projects" ;; esac
  env -u COMMANDECK_SCRATCH -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_WORKSPACES="$WS" COMMANDECK_DASHBOARD_DIR="$T/out2" COMMANDECK_MAIN="$MAIN" \
    DASH_NOW="$(date +%s)" bash "$SOURCE/scripts/dashboard.sh" >"$T/out2.log" 2>&1
  sed 's/^window.DASH = //; s/;$//' "$T/out2/data.js" | jq -c '.projects | keys'; }
check "an empty registry: the home project is not collected" '[]' "$(off EMPTY)"
check "no registry yet: the home project is collected, as before" '["demo"]' "$(off)"
check "a registry listing the home project: it is collected" '["demo"]' "$(off "$MAIN")"

# Issue 203: a 5-minute Builder at its prompt, waiting on something open, gets a keep-alive WARM just before its own
# cache lapses (225-300 s after its last request, on a 60 s tick), while a ping costs less than the rewrite it saves; a
# Builder idle on its own background job is waiting, not QUIET; and QUIET comes at 225 s on a 5-minute cache, while the
# cache is still warm. dashboard.sh passes no cache or tick, so the dashboard shows what it did before.
BJQ=$SOURCE/scripts/dashboard_builders.jq; N=2000000000
at() { jq -nr --argjson t "$((N - $1))" '$t | todate'; }
ts_() { printf '{"ts":"%s","event":"tool-start","use":"%s","tool":"Bash","kind":"%s","call":"c%s"}\n' "$(at "$1")" "$2" "$3" "$2"; }
te_() { printf '{"ts":"%s","event":"tool-end","use":"%s","ok":true}\n' "$(at "$1")" "$2"; }
sig() { jq -sc --argjson now "$N" ${1:+--argjson bgOpen "$1"} ${2:+--argjson cache "$2"} ${3:+--argjson tick "$3"} -f "$BJQ"; }
kinds() { sig "$@" | jq -c '[.signals[] | [.kind, .limitSec]]'; }
warm() { sig "$@" | jq -c '[.signals[] | select(.kind == "warm")]'; }
WC() { printf '{"ttl":%s,"ctx":%s,"at":%s,"ended":%s}' "${1:-300}" "${2:-100000}" "$((N - ${3:-230}))" "${4:-true}"; }
OWN() { ts_ 400 u1 shell; te_ 399 u1; }
check "warm: idle 230 s with a job open on a 100k context is one warm signal from the request, anchored on the parent's row, 11 pings" \
  "[{\"kind\":\"warm\",\"since\":$((N - 230)),\"anchor\":$((N - 400)),\"limitSec\":300,\"maxPings\":11}]" "$(OWN | warm 1 "$(WC)" 60)"
check "warm: none at 200 s or 310 s idle, on a 1-hour cache at 3530 s, mid-turn, with nothing open, or with no cache" "[] [] [] [] [] []" \
  "$(OWN | warm 1 "$(WC 300 100000 200)" 60) $(OWN | warm 1 "$(WC 300 100000 310)" 60) $(OWN | warm 1 "$(WC 3600 100000 3530)" 60) $(OWN | warm 1 "$(WC 300 100000 230 false)" 60) $(OWN | warm 0 "$(WC)" 60) $(OWN | warm 1 '' 60)"
check "warm: a 1000-token context buys 2 pings (a ping costs 450, a saved rewrite 1150)" 2 "$(OWN | warm 1 "$(WC 300 1000)" 60 | jq -c '.[0].maxPings')"
HELP=$(printf '{"ts":"%s","event":"tool-start","use":"h2","tool":"Grep","kind":"tool","agent":"a1","call":"g"}\n{"ts":"%s","event":"tool-end","use":"h2","ok":true}\n{"ts":"%s","event":"batch-end","uses":["h2"]}\n' "$(at 100)" "$(at 99)" "$(at 98)")
check "warm: a helper's rows after the parent's do not move the anchor; the parent's own subagent-request does" "$((N - 400)) $((N - 40))" \
  "$({ OWN; printf '%s\n' "$HELP"; } | warm 1 "$(WC)" 60 | jq -c '.[0].anchor') $({ OWN; printf '%s\n' "$HELP"; printf '{"ts":"%s","event":"subagent-request","type":"Explore"}\n' "$(at 40)"; } | warm 1 "$(WC)" 60 | jq -c '.[0].anchor')"
check "quiet: 226 s idle is QUIET at 225 s on a 5-minute cache and a 60 s tick, and nothing without a cache" '[["quiet",225]] []' \
  "$({ ts_ 400 u1 shell; te_ 226 u1; } | kinds '' "$(WC)" 60) $({ ts_ 400 u1 shell; te_ 226 u1; } | kinds)"
check "quiet: 301 s idle with a background job open is no signal; with none, or an unreadable log, it is QUIET" '[] [["quiet",300]] [["quiet",300]]' \
  "$({ ts_ 400 u1 shell; te_ 301 u1; } | kinds 1) $({ ts_ 400 u1 shell; te_ 301 u1; } | kinds 0) $({ ts_ 400 u1 shell; te_ 301 u1; } | kinds null)"
# pp_session_bg_open and pp_session_cache read the newest session record of a worktree, on its real row shapes.
CW=$T/cwt; CL=$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$CW"); mkdir -p "$CW" "$CL"
pp() { (. "$SOURCE/scripts/paths.sh" && "$1" "$CW" | jq -c .); }
{ printf '{"type":"user","toolUseResult":{"stdout":"","backgroundTaskId":"bAAA1"}}\n{"type":"user","toolUseResult":{"backgroundTaskId":"bBBB2"}}\n'
  printf '{"type":"user","toolUseResult":"a result that quotes backgroundTaskId bZZZ9"}\n'
  printf '{"type":"queue-operation","content":"<task-notification>\\n<task-id>bAAA1</task-id>\\n<status>completed</status>\\n</task-notification>"}\n'; } > "$CL/s1.jsonl"
check "bg_open: two jobs started and one notified is 1 open, a quoted id not counted" 1 "$(pp pp_session_bg_open)"
# A TaskStop sends no notification; its successful result is the job's end, else the job holds QUIET off for good.
printf '{"type":"user","toolUseResult":{"task_id":"bBBB2"},"message":{"content":[{"type":"tool_result","content":"Successfully stopped task: bBBB2"}]}}\n' >> "$CL/s1.jsonl"
check "bg_open: a job TaskStop stopped is closed" 0 "$(pp pp_session_bg_open)"
printf '{"type":"user","toolUseResult":{"backgroundTaskId":"bCCC3"}}\n{"type":"user","toolUseResult":{"task_id":"bCCC3"},"message":{"content":"Error: no task bCCC3"}}\n' >> "$CL/s1.jsonl"
check "bg_open: a TaskStop that failed closes nothing" 1 "$(pp pp_session_bg_open)"
crow() { printf '{"type":"assistant","isSidechain":%s,"timestamp":"%s","message":{"stop_reason":"%s","usage":{"input_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"cache_creation":{"ephemeral_1h_input_tokens":%s,"ephemeral_5m_input_tokens":%s}}}}\n' "${7:-false}" "$1" "$2" "$3" "$4" "$5" "${6%/*}" "${6#*/}"; }
urow() { printf '{"type":"user","isSidechain":false,"timestamp":"%s","message":{}}\n' "$1"; }
E1=$(jq -n '"2026-10-18T10:00:00Z" | fromdateiso8601'); E2=$(jq -n '"2026-10-18T10:00:30Z" | fromdateiso8601')
{ urow 2026-10-18T09:59:58Z; crow 2026-10-18T10:00:00Z tool_use 10 90000 5000 0/5000; urow 2026-10-18T10:00:30Z; crow 2026-10-18T10:00:45Z end_turn 12 95000 0 0/0; } > "$CL/s1.jsonl"
check "session_cache: a 5m write, then an end_turn reply: ttl 300, ctx of the newest reply, at its request, ended" "{\"ttl\":300,\"ctx\":95012,\"at\":$E2,\"ended\":true}" "$(pp pp_session_cache)"
{ urow 2026-10-18T10:00:00Z; crow 2026-10-18T10:00:00Z tool_use 10 90000 5000 5000/0; } > "$CL/s1.jsonl"
check "session_cache: a 1h write is ttl 3600, and a tool_use reply newest is not ended" '[3600,false]' "$(pp pp_session_cache | jq -c '[.ttl, .ended]')"
{ urow 2026-10-18T10:00:00Z; crow 2026-10-18T10:00:00Z tool_use 10 90000 5000 0/5000; crow 2026-10-18T10:00:30Z end_turn 12 95000 0 0/0 true; } > "$CL/s1.jsonl"
check "session_cache: a newer isSidechain row is skipped" "[95010,$E1,false]" "$(pp pp_session_cache | jq -c '[.ctx, .at, .ended]')"
{ crow 2026-10-18T10:00:00Z end_turn 10 90000 0 0/0; } > "$CL/s1.jsonl"
check "session_cache: no reply that wrote cache is null" null "$(pp pp_session_cache)"
rm -rf "$CL"
check "bg_open and session_cache: no session record is null" "null null" "$(pp pp_session_bg_open) $(pp pp_session_cache)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
