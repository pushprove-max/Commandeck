#!/usr/bin/env bash
# Seat-routing and review-class rules were set on token estimates because no
# seat row carried its tokens. seat.sh collect now sums them from the pane's own
# session log. This pins the sums for both log shapes, the null-with-reason row
# when no log is found (a completion is never held back for tokens), and the
# per-unit and per-role summary that reads them.
set -euo pipefail

SOURCE=$(git rev-parse --show-toplevel)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0
check() { [ "$2" = "$3" ] || { echo "FAIL $1 (expected [$2], got [$3])" >&2; exit 1; }; PASS=$((PASS + 1)); }

ROOT=$TMP/repo WS=$TMP/ws HOME_DIR=$TMP/home
git init -q "$ROOT"
mkdir -p "$ROOT/scripts" "$ROOT/config" "$WS/u1" "$WS/u2" "$TMP/bin" "$TMP/scratch"
cp "$SOURCE/scripts/seat.sh" "$SOURCE/scripts/paths.sh" "$SOURCE/scripts/project-main.sh" "$SOURCE/scripts/requirements.sh" "$SOURCE/scripts/read-verdict.sh" "$SOURCE/scripts/seat-tokens.sh" "$SOURCE/scripts/seat-event.sh" "$ROOT/scripts/"
printf '#!/bin/sh\nexit 0\n' > "$ROOT/scripts/run-bound.sh"
jq '.roles["claude-seat"] = {agent: "claude", model: "claude-opus-5-5", effort: "high", unboxed: true, edits: true}
  | .roles["codex-seat"] = {agent: "codex", model: "gpt-6-astra", effort: "high", unboxed: true, edits: true}
  | .["review-limits"] += {calls: 3, diffLines: 3000}' "$SOURCE/config/routing.json" > "$ROOT/config/routing.json"
cat > "$TMP/bin/orca-ide" <<'EOF'
#!/bin/sh
if [ "$1 $2" = "terminal read" ]; then echo '{"result":{"terminal":{"tail":["VERDICT: GO"]}}}'; else echo '{"ok":true}'; fi
EOF
chmod +x "$TMP/bin/orca-ide"

LAUNCHED=$(( $(date +%s) - 60 ))
NOW=$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')
record() { # unit role
  printf 'handle=h-%s-%s\ntask=task_%s_%s\nrole=%s\nunit=%s\nlaunched=%s\nspec=x\n' "$1" "$2" "$1" "$2" "$2" "$1" "$LAUNCHED" > "$TMP/scratch/seat-$1-$2.txt"
}

# Claude: one reply streamed as two lines sharing a message id, then a second reply.
CLAUDE_LOG=$HOME_DIR/.claude/projects/$(printf '%s' "$WS/u1" | tr -c 'A-Za-z0-9' '-')/session.jsonl
mkdir -p "$(dirname "$CLAUDE_LOG")"
usage() { printf '{"timestamp":"%s","type":"assistant","message":{"id":"%s","model":"claude-opus-5-5","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' "$NOW" "$@"; }
{
  printf '{"timestamp":"%s","type":"user","message":{"content":"spec"}}\n' "$NOW"
  usage msg_a 10 100 1000 5
  usage msg_a 10 100 1000 5
  usage msg_b 1 0 2000 7
} > "$CLAUDE_LOG"

# Codex: token_count carries running totals; only the last one is the session's.
CODEX_LOG=$HOME_DIR/.codex-review/sessions/2026/09/17/rollout.jsonl
mkdir -p "$(dirname "$CODEX_LOG")"
{
  printf '{"timestamp":"%s","type":"session_meta","payload":{"type":"session_meta","cwd":"%s"}}\n' "$NOW" "$WS/u1"
  printf '{"timestamp":"%s","type":"turn_context","payload":{"model":"gpt-6-astra"}}\n' "$NOW"
  printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":40}}}}\n' "$NOW"
  printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5000,"cached_input_tokens":4000,"output_tokens":300}}}}\n' "$NOW"
} > "$CODEX_LOG"

EVENTS=$ROOT/.claude/metrics/seat-events.jsonl
mkdir -p "$(dirname "$EVENTS")"
# A row from before tokens were recorded: the summary must skip it, not choke.
printf '{"event":"worker_done","unit":"u1","role":"claude-seat","taskId":"old","launchedAt":"x","completedAt":"x"}\n' > "$EVENTS"

collect() { # unit role
  record "$1" "$2"
  (cd "$ROOT" && env -u CODEX_HOME HOME="$HOME_DIR" PATH="$TMP/bin:$PATH" COMMANDECK_WORKSPACES="$WS" \
    COMMANDECK_SCRATCH="$TMP/scratch" COMMANDECK_RUN=run_test bash scripts/seat.sh collect "$2" "$1") > "$TMP/collect-$1-$2.out" 2>&1 \
    || { cat "$TMP/collect-$1-$2.out" >&2; echo "FAIL collect $1 $2" >&2; exit 1; }
}
row() { jq -c --arg t "task_$1_$2" 'select(.taskId == $t) | '"$3" "$EVENTS"; }

collect u1 claude-seat
check 'claude tokens sum each message id once' '{"input":3111,"cachedInput":3000,"output":12}' "$(row u1 claude-seat .tokens)"
check 'claude row names the model' '"claude-opus-5-5"' "$(row u1 claude-seat .model)"
check 'a counted row carries no reason' 'null' "$(row u1 claude-seat .tokensReason)"
# seat.sh launch refuses a rerun of a spec whose record holds a verdict.
check 'collect records the verdict in the seat record' 1 "$(grep -c '^verdict=VERDICT: GO' "$TMP/scratch/seat-u1-claude-seat.txt")"

collect u1 codex-seat
check 'codex tokens are the last running total' '{"input":5000,"cachedInput":4000,"output":300}' "$(row u1 codex-seat .tokens)"
check 'codex row names the model' '"gpt-6-astra"' "$(row u1 codex-seat .model)"

collect u2 claude-seat
check 'no session log still writes the row' 'null' "$(row u2 claude-seat .tokens)"
check 'the null row says why' 'true' "$(row u2 claude-seat '.tokensReason | startswith("no session log")')"

SUMMARY=$(bash "$ROOT/scripts/seat-tokens.sh" "$EVENTS")
check 'summary: one line per unit, then per role; tokenless rows skipped' \
  'unit=u1 seats=2 input=8111 cachedInput=7000 output=312
role=claude-seat seats=1 input=3111 cachedInput=3000 output=12
role=codex-seat seats=1 input=5000 cachedInput=4000 output=300' "$SUMMARY"

# Rollout mode: Codex seats ran one tool call per turn. The counts must
# tell a batched exec script (two tools.* calls, one turn) from a lone look, and
# count a function_call (wait) as a call carrying no tools.* inside.
ROLLOUT=$TMP/rollout.jsonl
tc() { printf '{"type":"event_msg","payload":{"type":"token_count","info":null}}\n'; }
{
  printf '{"type":"session_meta","payload":{"type":"session_meta","cwd":"/x"}}\n'
  printf '%s\n' '{"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"const [a, b] = await Promise.all([tools.exec_command({cmd:\"rg x f\"}), tools.mcp__serena__find_symbol({name_path:\"y\"})]);"}}'
  tc
  printf '%s\n' '{"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"const r = await tools.exec_command({cmd:\"sed -n 1,5p f\"});"}}'
  tc
  printf '%s\n' '{"type":"response_item","payload":{"type":"function_call","name":"wait","arguments":"{\"cell_id\":\"5\"}"}}'
  tc
  tc
} > "$ROLLOUT"
# The call budget is the configured review-limits.calls: Codex has no
# hard stop, so a session over it is flagged here. The fixture's budget is 3,
# so this 4-turn session is over it and the empty one below is not.
rollout() { COMMANDECK_ROUTING="$ROOT/config/routing.json" bash "$ROOT/scripts/seat-tokens.sh" --rollout "$@"; }
check 'rollout: turns, calls, tools.* inside scripts, per-turn ratios, and over the call budget' \
  "turns=4 toolCalls=3 toolsCalls=3 callsPerTurn=0.75 toolsPerTurn=0.75 budget=3 overBudget=true file=$ROLLOUT" \
  "$(rollout "$ROLLOUT")"
# Codex now writes one token_usage_record a model call, at the top level, and
# no token_count: counted as no turns, a session was never over its budget.
tur() { printf '{"type":"token_usage_record","payload":{"total_token_usage":{"input_tokens":1}}}\n'; }
{ sed -n 2p "$ROLLOUT"; tur; tur; tur; tur; } > "$TMP/rollout-now.jsonl"
check 'rollout: the current token_usage_record is a turn' \
  "turns=4 toolCalls=1 toolsCalls=2 callsPerTurn=0.25 toolsPerTurn=0.5 budget=3 overBudget=true file=$TMP/rollout-now.jsonl" \
  "$(rollout "$TMP/rollout-now.jsonl")"
printf '{"type":"session_meta","payload":{"type":"session_meta"}}\n' > "$TMP/empty.jsonl"
check 'rollout: a session with no turns divides by nothing' \
  "turns=0 toolCalls=0 toolsCalls=0 callsPerTurn=0 toolsPerTurn=0 budget=3 overBudget=false file=$TMP/empty.jsonl" \
  "$(rollout "$TMP/empty.jsonl")"

echo "PASS: seat-tokens.test.sh ($PASS assertions)"
