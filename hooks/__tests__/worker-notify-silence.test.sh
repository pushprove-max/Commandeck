#!/usr/bin/env bash
# worker-notify-silence.test.sh -- the worker Stop hooks' message cuts (part D). A NO-GO that ends a turn goes back to
# the Builder through its fix round, and a Claude turn whose worker_done Orca accepted (the run inbox holds one from
# this pane after the turn's prompt) has reported: main has nothing to act on in either. A question or refusal line
# is never silenced by either rule. Split from worker-notify.test.sh, which ran past the runner's per-file cap with
# these cases in it. Run directly: bash hooks/__tests__/worker-notify-silence.test.sh
set -u
SOURCE=$(git rev-parse --show-toplevel)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
mkdir -p "$T/bin" "$T/sc"
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$T/p" worktree add -q "$T/ws/u1" -b u1
echo run_t > "$T/sc/current-run"
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  # refuse: Orca takes no send (the request is recorded all the same).
  "orchestration send") printf '%s\n' "\$*" | tr '\n' ' ' >> "$T/sends"; echo >> "$T/sends"
    [ ! -e "$T/refuse" ] || { echo '{"ok":false,"error":{"message":"refused by the stub"}}'; exit 1; }; echo '{"ok":true}' ;;
  "orchestration inbox") cat "$T/inbox.json" 2>/dev/null || echo '{"ok":true,"result":{"messages":[]}}' ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
EOF
# No driver owns the unit: the service list is empty.
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/systemctl"
chmod +x "$T/bin/orca-ide" "$T/bin/systemctl"
NOW=$(date +%s)
rec() { printf 'handle=%s\ntask=task_%s\nrole=%s\nunit=u1\nworktree=u1\nlaunched=%s\nplanref=%s\n' "$1" "$1" "$2" "$((NOW - 100))" "${3:-}" > "$T/sc/seat-u1-$2.txt"; }
rec term_judge plan-judge-sol
run() { # <handle> <hook> <stdin or arg>: the hook, run in the unit's worktree
  (cd "$T/ws/u1" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR -u COMMANDECK_BUILDER ORCA_TERMINAL_HANDLE="$1" ORCA_WORKTREE_ID="id::$T/ws/u1" \
    COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/sc" COMMANDECK_HOST_OS=Linux HOME="$T/home" \
    COMMANDECK_HOOK_FIRE_LOG="$T/fires.jsonl" PATH="$T/bin:$PATH" "${@:2}" 2>/dev/null)
}
claude() { # <handle> <text> [turn id] [stop_hook_active] -- one Stop of a Claude pane whose last turn ends on <text>
  jq -nc --arg t "$2" --arg u "${3:-u$RANDOM$RANDOM}" '{type: "assistant", uuid: $u, message: {content: [{type: "text", text: $t}]}}' > "$T/tr.jsonl"
  jq -n --arg p "$T/tr.jsonl" --argjson a "${4:-false}" '{transcript_path: $p, stop_hook_active: $a, hook_event_name: "Stop"}' \
    | run "$1" bash "$SOURCE/hooks/claude-worker-notify.sh"
}
codex() { # <handle> <text> [turn id] -- one notify of a Codex pane
  run "$1" bash "$SOURCE/hooks/codex-notify.sh" "$(jq -nc --arg t "$2" --arg u "${3:-c$RANDOM$RANDOM}" '{type: "agent-turn-complete", "turn-id": $u, "last-assistant-message": $t}')" </dev/null
}
sends() { grep -c -- "${1:-.}" "$T/sends" 2>/dev/null || true; }

# Message cuts: a NO-GO goes back to the Builder through its fix round, and a turn whose worker_done Orca accepted has
# reported, so main has nothing to act on in either. A question or refusal line is never silenced by either rule.
nogo() { # <hook> <text> -- a turn ending VERDICT: NO-GO, or whatever <text> ends on
  "$1" term_free "$2" "n$RANDOM$RANDOM" >/dev/null; }
for h in claude codex; do
  : > "$T/sends"; nogo $h $'Two findings remain.\nVERDICT: NO-GO'; nogo $h $'Two findings remain.\n  VERDICT: NO-GO  \n\n'
  check "$h: a turn ending VERDICT: NO-GO sends nothing" 0 "$(sends)"
  : > "$T/sends"; nogo $h $'QUESTION: Which rollback policy applies?\nVERDICT: NO-GO'
  check "$h: a QUESTION: line then VERDICT: NO-GO still sends, the question in the subject" 1 "$(sends "$h turn complete: QUESTION (u1)")"
  : > "$T/sends"; nogo $h $'BLOCKED: access was refused.\nVERDICT: NO-GO'
  check "$h: a BLOCKED: line then VERDICT: NO-GO still sends" 1 "$(sends "$h turn complete: BLOCKED (u1)")"
  : > "$T/sends"; nogo $h $'The earlier pass said VERDICT: NO-GO and is fixed.\nOPEN-ISSUES-DONE\nVERDICT: GO'
  check "$h: a NO-GO quoted earlier in a turn that ends on a GO still sends" 1 "$(sends "$h turn complete: VERDICT: GO (u1)")"
done
# The Claude hook reads Orca's run inbox for a worker_done from this pane made after the turn's prompt. The transcript
# holds the prompt (a user line with a text block) with its timestamp; a tool_result user line is not a prompt.
reported() { # <inbox lines as jq message objects> -- one Stop whose turn ended on a DONE marker after a prompt at NOW-60
  jq -nc --arg p "$(jq -rn --argjson t $((NOW - 60)) '$t | todate')" --arg u "d$RANDOM$RANDOM" --arg t "$2" '
    {type: "user", timestamp: $p, message: {role: "user", content: "Build the unit."}},
    {type: "assistant", uuid: $u, timestamp: $p, message: {content: [{type: "text", text: $t}]}}' > "$T/tr.jsonl"
  jq -n --arg p "$T/tr.jsonl" '{transcript_path: $p, stop_hook_active: false, hook_event_name: "Stop"}' | run term_free bash "$SOURCE/hooks/claude-worker-notify.sh" >/dev/null
}
wd() { # <from handle> <seconds before now> <type> -- an inbox holding one message
  jq -nc --arg h "$1" --arg ty "$3" --argjson at "$((NOW - $2))" '{ok: true, result: {messages: [{from_handle: $h, type: $ty, created_at: ($at | todate)}]}}' > "$T/inbox.json"; }
wd term_free 20 worker_done; : > "$T/sends"; reported x $'Built.\nBUILD-DONE'
check "claude: a turn whose worker_done Orca accepted sends nothing" 0 "$(sends)"
wd term_free 20 worker_done; : > "$T/sends"; reported x $'BLOCKED: the merge gate refused.\nBUILD-DONE'
check "claude: a BLOCKED: line in a turn whose worker_done Orca accepted still sends" 1 "$(sends 'claude turn complete: BLOCKED (u1)')"
rm -f "$T/inbox.json"; : > "$T/sends"; reported x $'Built.\nBUILD-DONE'
check "claude: a worker_done Orca refused (none in its inbox) still sends" 1 "$(sends 'claude turn complete (u1)')"
wd term_free 120 worker_done; : > "$T/sends"; reported x $'Built.\nBUILD-DONE'
check "claude: a worker_done from before this turn's prompt still sends" 1 "$(sends 'claude turn complete (u1)')"
wd term_other 20 worker_done; : > "$T/sends"; reported x $'Built.\nBUILD-DONE'
check "claude: another pane's worker_done proves nothing" 1 "$(sends 'claude turn complete (u1)')"
wd term_free 20 question; : > "$T/sends"; reported x $'Built.\nBUILD-DONE'
check "claude: a message of another type proves nothing" 1 "$(sends 'claude turn complete (u1)')"
echo '{"ok":false}' > "$T/inbox.json"; : > "$T/sends"; reported x $'Built.\nBUILD-DONE'
check "claude: an unreadable inbox keeps the echo" 1 "$(sends 'claude turn complete (u1)')"
rm -f "$T/inbox.json"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
