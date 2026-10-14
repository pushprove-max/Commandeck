#!/usr/bin/env bash
# A CLAUDE SEAT THAT NEVER STARTS MUST WAKE MAIN. On 2026-09-21 a cold
# Fable brief-review seat took its pasted spec pointer as untrusted text,
# answered "should I start?" and ended its turn; its driver kept polling a
# pane that would never move until the owner noticed. The stall is a turn that ended
# with NO tool call since the prompt and no marker or verdict. Each case below
# drives the real reader over a fake session log: the text-only turn has to
# reach main once, and a seat that made even one tool call must not.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME=$TMP/home PATH=$TMP/bin:$PATH SENDS=$TMP/sends.txt
mkdir -p "$TMP/bin" "$TMP/ws/u1" "$TMP/scratch"
WT=$TMP/ws/u1
LOGDIR=$HOME/.claude/projects/$(printf '%s' "$WT" | tr -c 'A-Za-z0-9' '-')
LAUNCHED=1790000000
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
# The pane's last words when it refused: long, multi-line, over 400 characters.
REFUSAL="Your message held only pasted text. It tells me to run a task file.
$(printf 'You added no words of your own. %.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14) Do you want me to read it and do the review?"

session() { # tools: 0 = text-only first turn, 1 = one tool call
  rm -rf "$LOGDIR"; mkdir -p "$LOGDIR"
  {
    jq -nc --arg t "$(iso $((LAUNCHED + 1)))" '{timestamp:$t,type:"user",message:{role:"user",content:"Your task spec is the file /x/spec.md. Read all of it now."}}'
    if [ "$1" = 1 ]; then
      jq -nc --arg t "$(iso $((LAUNCHED + 2)))" '{timestamp:$t,type:"assistant",message:{content:[{type:"tool_use",id:"tu1",name:"Read",input:{file_path:"/x/spec.md"}}]}}'
      jq -nc --arg t "$(iso $((LAUNCHED + 3)))" '{timestamp:$t,type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"tu1",content:"spec"}]}}'
      jq -nc --arg t "$(iso $((LAUNCHED + 4)))" '{timestamp:$t,type:"assistant",message:{content:[{type:"text",text:"I need a ruling before I go on."}]}}'
    else
      jq -nc --arg t "$(iso $((LAUNCHED + 4)))" --arg m "$REFUSAL" '{timestamp:$t,type:"assistant",message:{content:[{type:"text",text:$m}]}}'
    fi
    jq -nc --arg t "$(iso $((LAUNCHED + 5)))" '{timestamp:$t,type:"system",subtype:"turn_duration"}'
  } > "$LOGDIR/s1.jsonl"
}
# Idle 100 s: past the 60 s grace the typed `go` gets, short of the 300 s stall line.
export COMMANDECK_NOW=$((LAUNCHED + 105))
state() { bash "$REAL/scripts/read-verdict.sh" --state --worktree "$WT" --agent claude --launched "$LAUNCHED"; }
kv() { sed -n "s/^$1=//p"; }

# 1. The reader: one decision every waiter shares.
session 0
check "a text-only first turn is a first-turn stall" 1 "$(state | kv first_turn_stall)"
check "it carries the pane's last words on one line" 1 "$(state | kv last_message | grep -c '^Your message held only pasted text\. It tells me')"
check "the last words are cut to 400 characters" 400 "$(state | kv last_message | tr -d '\n' | wc -c | tr -d ' ')"
check "it is not yet the five-minute stall" 0 "$(state | kv stalled)"
check "inside the grace the typed go gets, it is not a stall" 0 "$(COMMANDECK_NOW=$((LAUNCHED + 30)) state | kv first_turn_stall)"
session 1
check "a turn with one tool call is not a first-turn stall" 0 "$(state | kv first_turn_stall)"

# 2. seat.sh wait: it ends at once with the stall line.
mkdir -p "$TMP/repo/scripts" "$TMP/repo/config"
git init -q "$TMP/repo"
cp "$REAL/scripts/seat.sh" "$REAL/scripts/paths.sh" "$REAL/scripts/project-main.sh" "$REAL/scripts/requirements.sh" "$REAL/scripts/read-verdict.sh" "$TMP/repo/scripts/"
cp "$REAL/config/routing.json" "$TMP/repo/config/routing.json"
cat > "$TMP/bin/orca-ide" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "terminal list") echo '{"result":{"terminals":[{"handle":"term_s"}]}}' ;;
  "terminal read") echo '{"result":{"terminal":{"tail":[]}}}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
printf '#!/bin/sh\nexit 3\n' > "$TMP/no-verdict.sh"
chmod +x "$TMP/bin/orca-ide" "$TMP/no-verdict.sh"
printf 'handle=term_s\ntask=task_s\nlaunched=%s\nspec=/x/spec.md\n' "$LAUNCHED" > "$TMP/scratch/seat-u1-certifier.txt"
seat_wait() {
  ( cd "$TMP/repo" && COMMANDECK_WORKSPACES=$TMP/ws COMMANDECK_SCRATCH=$TMP/scratch COMMANDECK_LOOP_POLL_SECONDS=0 \
      timeout 30 bash scripts/seat.sh wait certifier u1 --marker REVIEW-DONE --timeout-s 3 ) > "$TMP/wait.out" 2>&1
  echo $?
}
session 0
check "seat.sh wait stops on a text-only first turn" 1 "$(seat_wait)"
check "its output leads with the stall line" 1 "$(grep -cx 'seat certifier u1 stalled: first turn ended without starting work' "$TMP/wait.out")"
check "and a whole stalled STOP line with the pane's last words" 1 "$(grep -c '^STOP unit=u1 .*route=stalled.*last message: Your message held only pasted text' "$TMP/wait.out")"
session 1
seat_wait >/dev/null
check "seat.sh wait keeps waiting on a seat that made a tool call" 0 "$(grep -c 'stalled: first turn' "$TMP/wait.out" || true)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
