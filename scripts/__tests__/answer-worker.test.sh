#!/usr/bin/env bash
# Self-test for answer-worker.sh. Main answered a Builder's question
# twice and neither answer arrived: an Orca reply to a pane that had ended its
# turn was never read, and typed text was refused because Orca still called
# the pane working. What must hold: the answer goes the way the pane can
# receive it, and it counts as delivered only when the pane's session log
# holds it.
set -uo pipefail
SCRIPT=$(cd "$(dirname "$0")/.." && pwd)/answer-worker.sh
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi; }

WT=$BOX/wt; mkdir -p "$WT" "$BOX/bin"
export HOME=$BOX/home
PROJ=$HOME/.claude/projects/$(printf '%s' "$WT" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$PROJ"
LOG=$PROJ/pane.jsonl
# The stub Orca: one Claude pane, alone in its worktree, that Orca calls
# working. With DELIVER=1 a send lands in the pane's session log, as a real
# pane's next prompt does.
cat > "$BOX/bin/orca-ide" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$BOX/calls"
case "\$1 \$2" in
  "terminal list") echo '{"ok":true,"result":{"terminals":[{"handle":"term_w","tabId":"t1","leafId":"l1"}]}}' ;;
  "worktree ps") jq -nc --arg p "$WT" '{ok:true,result:{worktrees:[{path:\$p,agents:[{paneKey:"t1:l1",state:"working",agentType:(env.KIND // "claude")}]}]}}' ;;
  "terminal send"|"orchestration send")
    # ENDS_UNREAD=1: the pane never reads the inbox message and ends its turn.
    if [ "\$1" = orchestration ] && [ "\${ENDS_UNREAD:-0}" = 1 ]; then
      jq -nc --arg ts "\$(jq -nr 'now | strftime("%Y-%m-%dT%H:%M:%S.000Z")')" \
        '{type:"assistant",timestamp:\$ts,message:{role:"assistant",stop_reason:"end_turn",content:[{type:"text",text:"Done."}]}}, {type:"system",subtype:"turn_duration",timestamp:\$ts}' >> "$LOG"
      exit 0
    fi
    [ "\${DELIVER:-0}" = 1 ] && jq -nc --arg t "\$*" --arg ts "\$(jq -nr 'now | strftime("%Y-%m-%dT%H:%M:%S.000Z")')" \
      '{type:"user",timestamp:\$ts,message:{role:"user",content:\$t}}' >> "$LOG"
    exit "\${SEND_RC:-0}" ;;
esac
EOF
chmod +x "$BOX/bin/orca-ide"
export PATH="$BOX/bin:$PATH" ANSWER_WORKER_WAIT=2
rows() { local ts; ts=$(jq -nr 'now | strftime("%Y-%m-%dT%H:%M:%S.000Z")'); printf '%s\n' "$@" | jq -c --arg ts "$ts" '. + {timestamp:$ts}' > "$LOG"; }
ASKED='{"type":"user","message":{"role":"user","content":"build it"}}'
SAID='{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"A question for main."}]}}'
ENDED='{"type":"system","subtype":"turn_duration"}'
answer() { : > "$BOX/calls"; bash "$SCRIPT" term_w "Ruling 4: drop the last item" >"$BOX/out" 2>"$BOX/err"; echo $?; }

rows "$ASKED" "$SAID" "$ENDED"
check "a pane whose turn has ended gets the answer typed in, and it is confirmed" "0 1 0" \
  "$(DELIVER=1 answer) $(grep -c '^terminal send --terminal term_w .*Ruling 4: drop the last item.* --enter' "$BOX/calls") $(grep -c '^orchestration send' "$BOX/calls")"
check "the confirmation names the way and the tag" 1 "$(grep -c 'delivered to term_w (typed into the pane), tag answer-' "$BOX/out")"

rows "$ASKED" "$SAID" "$ENDED"
check "text that never reaches the session log exits non-zero" 1 "$(answer)"
check "and says the answer was not delivered" 1 "$(grep -c 'NOT delivered' "$BOX/err")"

rows "$ASKED"
check "a pane that is mid-turn gets an inbox message, never typed text" "0 0 1" \
  "$(DELIVER=1 answer) $(grep -c '^terminal send' "$BOX/calls") $(grep -c '^orchestration send --to term_w --type status' "$BOX/calls")"

# A pane that was mid-turn and then ended its turn without a look at its inbox
# never reads the message: main typed four answers in by hand on 2026-10-13.
rows "$ASKED"
check "a pane that ends its turn with the inbox message unread gets the answer typed in then, and it is confirmed" "0 1 1 1" \
  "$(DELIVER=1 ENDS_UNREAD=1 answer) $(grep -c '^orchestration send --to term_w' "$BOX/calls") $(grep -c '^terminal send --terminal term_w .* --enter' "$BOX/calls") $(grep -c 'typed into the pane once its turn ended' "$BOX/out")"
# A restarted pane leaves its old session's log beside the new one: the answer
# goes by the current session's state and is confirmed in the current log.
printf '%s\n' "$ASKED" "$SAID" "$ENDED" | jq -c '. + {timestamp:"2026-01-01T00:00:00.000Z"}' > "$PROJ/an-old-session.jsonl"
touch -d '2026-01-01' "$PROJ/an-old-session.jsonl"
rows "$ASKED"
check "beside an old finished session, a mid-turn pane still gets an inbox message, confirmed in its current log" "0 0 1" \
  "$(DELIVER=1 answer) $(grep -c '^terminal send' "$BOX/calls") $(grep -c '^orchestration send --to term_w --type status' "$BOX/calls")"
rm -f "$PROJ/an-old-session.jsonl"

# A Builder's finished Codex reviewer leaves a newer log in the same worktree.
# The answer is looked for in the Builder's own log, a Claude one, not in that.
CX=$HOME/.codex/sessions/2026/10/12; mkdir -p "$CX"
rows "$ASKED"; touch -d '1 minute ago' "$LOG"
{ jq -nc --arg cwd "$WT" '{type:"session_meta",payload:{id:"rev",cwd:$cwd}}'
  jq -nc '{type:"response_item",payload:{type:"message",role:"user",content:[{type:"input_text",text:"Reviewer 1 of 3, round 1."}]}}'
  jq -nc '{type:"event_msg",payload:{type:"task_complete",last_agent_message:"VERDICT: GO"}}'
} | jq -c --arg ts "$(jq -nr 'now | strftime("%Y-%m-%dT%H:%M:%S.000Z")')" '. + {timestamp:$ts}' > "$CX/rollout-2026-10-12T00-00-00-rev.jsonl"
check "beside a newer finished Codex reviewer log, a mid-turn Builder gets an inbox message, confirmed in its own log" "0 0 1" \
  "$(DELIVER=1 answer) $(grep -c '^terminal send' "$BOX/calls") $(grep -c '^orchestration send --to term_w --type status' "$BOX/calls")"
rm -rf "$HOME/.codex"
# The Claude-only profile's reviewer is a headless Claude session in the same
# worktree: its finished log is newer than the Builder's and is not the pane's.
rows "$ASKED"; touch -d '1 minute ago' "$LOG"
{ jq -nc '{type:"user",message:{role:"user",content:"Review input. Reviewer 1 of 3, round 1."}}'; printf '%s\n' "$SAID" "$ENDED"; } \
  | jq -c --arg ts "$(jq -nr 'now | strftime("%Y-%m-%dT%H:%M:%S.000Z")')" '. + {timestamp:$ts}' > "$PROJ/a-claude-reviewer.jsonl"
check "beside a newer finished Claude reviewer log, a mid-turn Builder gets an inbox message, confirmed in its own log" "0 0 1" \
  "$(DELIVER=1 answer) $(grep -c '^terminal send' "$BOX/calls") $(grep -c '^orchestration send --to term_w --type status' "$BOX/calls")"
rm -f "$PROJ/a-claude-reviewer.jsonl"
check "a pane whose kind Orca does not give is a failure and nothing is sent" "1 0 1" \
  "$(KIND= answer) $(grep -c ' send ' "$BOX/calls") $(grep -c 'does not say whether term_w is a Claude or a Codex pane' "$BOX/err")"

rows "$ASKED" "$SAID" "$ENDED"
check "a send Orca refuses is a failure, with no wait" "1 1" "$(SEND_RC=1 answer) $(grep -c 'terminal send to term_w failed' "$BOX/err")"
check "an unknown pane is a failure and nothing is sent" "1 0" \
  "$(: > "$BOX/calls"; bash "$SCRIPT" term_other hello >/dev/null 2>&1; echo $?) $(grep -c ' send ' "$BOX/calls")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
