#!/usr/bin/env bash
# worker-notify.test.sh -- the worker Stop hooks, claude-worker-notify.sh and codex-notify.sh (issues 320, 321).
# Run directly: bash hooks/__tests__/worker-notify.test.sh
#
# Every worker turn end used to message main, and a seat's finish reached main up to three times. Pinned: a pane with
# no seat record sends its marker once; a QUESTION:/BLOCKED: line sends exactly one message from any pane, however
# long the reply after it; a plain or markerless ending sends nothing, yet the hook still writes its local fire-log
# row; and a plan seat whose plan is committed since launch but whose turn has no PLAN-DONE is blocked once with the
# marker line. A seat pane's own marker turn is pinned beside the path that reports it (see the loop below).
# The `orca-ide` stub logs every send, one line each.
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

# A seat pane's marker turn sends nothing: main-watch-nudge.test.sh runs these hooks on a judge seat's pane and shows
# main-watch's one post of that finish, and builder-codex-pass-fresh-round.test.sh shows a Builder's pane silent while
# the pass hands the Builder its verdict.
LONG=$(printf 'x%.0s' $(seq 700))
for h in claude codex; do
  : > "$T/sends"
  $h term_free $'QUESTION: Which branch should I use?\n'"$LONG" >/dev/null
  check "$h: a question followed by 700 characters still sends one message, the question line in its body" '1:1' \
    "$(sends "$h turn complete: QUESTION (u1)"):$(sends 'QUESTION: Which branch should I use?')"
  # Every ask line of a reply reaches main, not the first alone: the crop to the last 600 characters loses all but the tail.
  : > "$T/sends"; $h term_free $'QUESTION: Which branch should I use?\nBLOCKED: Required rollback is missing.\n'"$LONG" >/dev/null
  check "$h: two ask lines followed by 700 characters: one message holding both lines" '1:1:1' \
    "$(sends "$h turn complete: QUESTION (u1)"):$(sends 'QUESTION: Which branch should I use?'):$(sends 'BLOCKED: Required rollback is missing.')"
  : > "$T/sends"; $h term_judge "BLOCKED: access was refused. $LONG" >/dev/null
  check "$h: a 700-character refusal line still sends one message, from a seat pane too" 1 "$(sends "$h turn complete: BLOCKED (u1)")"
  : > "$T/sends"
  $h term_free $'Done.\nVERDICT: GO' fixed >/dev/null; $h term_free $'Done.\nVERDICT: GO' fixed >/dev/null
  check "$h: a pane with no seat record: a marker turn sends exactly one message, a re-fire sends none" 1 "$(sends "$h turn complete: VERDICT: GO (u1)")"
  for p in term_judge term_free; do
    : > "$T/sends"
    $h $p $'I need a ruling.\nQUESTION: Which branch should I use?' "q$p" >/dev/null; $h $p $'I need a ruling.\nQUESTION: Which branch should I use?' "q$p" >/dev/null
    check "$h: a question sends exactly one message, a re-fire sends none ($p)" 1 "$(sends "$h turn complete: QUESTION (u1)")"
    : > "$T/sends"; $h $p '**BLOCKED: I cannot continue: access was refused.**' >/dev/null
    check "$h: a refusal sends exactly one message ($p)" 1 "$(sends "$h turn complete: BLOCKED (u1)")"
  done
  : > "$T/sends"; : > "$T/fires.jsonl"
  $h term_free 'Reading the files now.' >/dev/null; $h term_free 'Which branch should I use?' >/dev/null
  check "$h: a plain mid-work ending sends no message, nor does a question with no QUESTION: line" 0 "$(sends)"
  check "$h: and each silent turn end still writes its local fire-log row" 2 "$(grep -c . "$T/fires.jsonl")"
  # A question or refusal line quoted in a fence or a blockquote is an example, not an ask; a fence left open quotes nothing.
  : > "$T/sends"; $h term_free $'Regression fixture:\n```text\nQUESTION: Which branch should I use?\n```\nVERDICT: GO' >/dev/null
  check "$h: a question quoted in a closed fence sends no question, only the verdict" '0:1' "$(sends "$h turn complete: QUESTION"):$(sends "$h turn complete: VERDICT: GO (u1)")"
  : > "$T/sends"; $h term_free $'As the log said:\n> BLOCKED: access was refused.\nCarrying on.' >/dev/null; $h term_free $'Fixture:\n~~~\nBLOCKED: access was refused.\n~~~\nCarrying on.' >/dev/null
  check "$h: a refusal quoted in a blockquote or a tilde fence sends nothing" 0 "$(sends)"
  : > "$T/sends"; $h term_free $'Let me show it:\n```\nQUESTION: Which branch should I use?' >/dev/null
  check "$h: a question after a fence that never closes still sends one message" 1 "$(sends "$h turn complete: QUESTION (u1)")"
  # The fence rules are paths.sh's own (PP_AWK_FENCE): a longer or other-character outer fence is not closed by an inner delimiter.
  : > "$T/sends"; $h term_free $'Fixture:\n````text\n```\nQUESTION: Which branch should I use?\n```\n````\nVERDICT: GO' >/dev/null
  $h term_free $'Fixture:\n```text\n~~~\nQUESTION: Which branch should I use?\n~~~\n```\nVERDICT: GO' >/dev/null
  check "$h: a question inside an outer fence that holds shorter or other delimiters sends no question" '0:2' "$(sends "$h turn complete: QUESTION"):$(sends "$h turn complete: VERDICT: GO (u1)")"
done

# Issue 320: the plan is committed after the seat launched, and the turn ended without the marker.
mkdir -p "$T/ws/u1/.claude/plans"; echo 'old plan' > "$T/ws/u1/.claude/plans/u1.md"
git -C "$T/ws/u1" add .claude/plans/u1.md && GIT_COMMITTER_DATE="@$((NOW - 500)) +0000" git -C "$T/ws/u1" -c user.name=t -c user.email=t@t commit -qm old
OLD=$(git -C "$T/ws/u1" rev-parse HEAD:.claude/plans/u1.md)
rec term_plan plan-author "$OLD"
# The seat's session log as a real Stop reads it: no turn_duration yet, as Claude Code writes it after the Stop hooks.
SL=$T/home/.claude/projects/$(printf '%s' "$T/ws/u1" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$SL"
jq -nc --arg p "$(jq -rn --argjson t $((NOW - 90)) '$t | todate')" '
  {type: "user", timestamp: $p, message: {role: "user", content: "Plan the unit."}},
  {type: "assistant", timestamp: $p, message: {content: [{type: "text", text: "Plan revised and committed."}]}}' > "$SL/s1.jsonl"
: > "$T/sends"; OUT=$(claude term_plan 'Plan revised and committed.')
check "plan seat, no plan commit since launch: no block" '' "$OUT"
echo 'new plan' > "$T/ws/u1/.claude/plans/u1.md"; git -C "$T/ws/u1" -c user.name=t -c user.email=t@t commit -qam new
OUT=$(claude term_plan 'Plan revised and committed.')
check "plan seat, plan committed after launch, turn without PLAN-DONE: the hook blocks with the marker line, no send" \
  "block|Your plan .claude/plans/u1.md is committed since this seat started, but your turn ended without its marker. Print this line alone as your last line, with nothing after it: PLAN-DONE|0" \
  "$(jq -r '"\(.decision)|\(.reason)"' <<<"$OUT" 2>&1)|$(sends)"
check "stop_hook_active true: no block" '' "$(claude term_plan 'Plan revised and committed.' '' true)"
# A failure the seat reported by message, or an inbox that does not answer, is the seat's word too: no block asks for PLAN-DONE
# over it. Each piece of state goes between two Stops and the next Stop blocks again.
for body in PLAN-BLOCKED '**VERDICT:  NO-GO**'; do
  jq -nc --arg b "$body" --argjson at "$((NOW - 30))" '{ok: true, result: {messages: [{from_handle: "term_plan", to_handle: "run:run_t", type: "worker_done", subject: "Plan revised: rollback pending", body: $b, read: 0, created_at: ($at | todate)}]}}' > "$T/inbox.json"
  check "plan seat, plan committed, a 'Plan revised' message with the body '$body': no block" '' "$(claude term_plan 'See my status message.')"
done
echo '{"ok":false}' > "$T/inbox.json"
check "plan seat, plan committed, the inbox not answering: no block" '' "$(claude term_plan 'See my status message.')"
rm -f "$T/inbox.json"
check "and with the failure message gone and the inbox answering, the next Stop blocks" block "$(claude term_plan 'See my status message.' | jq -r .decision 2>&1)"
# An explicit failure ending is kept: the seat said it could not finish, so the hook does not ask it for PLAN-DONE.
check "plan seat, plan committed, turn ending PLAN-BLOCKED: no block" '' "$(claude term_plan $'Cannot finish the rollback section.\nPLAN-BLOCKED')"
check "plan seat, plan committed, turn ending on a verdict line (any spelling): no block" ':' \
  "$(claude term_plan $'Revision rejected.\nVERDICT: NO-GO'):$(claude term_plan $'Revision rejected.\n**VERDICT:NO-GO**')"
check "a turn that ends on PLAN-DONE: no block, and a seat pane sends nothing" ':0' "$(claude term_plan $'Plan revised.\nPLAN-DONE'):$(sends)"
# No readable session log: the hook cannot tell the turn left nothing running, so it asks for nothing.
mv "$SL/s1.jsonl" "$T/s1.jsonl"; check "plan seat, plan committed, no session log found: no block" '' "$(claude term_plan 'Plan revised and committed.')"
mv "$T/s1.jsonl" "$SL/s1.jsonl"
# A turn that left its background command running is not finished: no block asks for its marker. The seat's session
# log names the command; its .output is held by a child of a stand-in claude (a copy of bash), as read-verdict.sh
# requires of a live background command. With the holder gone, the block is back.
jq -nc --arg p "$(jq -rn --argjson t $((NOW - 90)) '$t | todate')" --arg o "$T/b1.output" '
  {type: "user", timestamp: $p, message: {role: "user", content: "Plan the unit."}},
  {type: "user", timestamp: $p, toolUseResult: {stdout: "", backgroundTaskId: "b1"},
   message: {role: "user", content: [{type: "tool_result", tool_use_id: "t1", content: "Output is being written to: \($o)"}]}},
  {type: "assistant", timestamp: $p, message: {content: [{type: "text", text: "Plan revised and committed."}]}},
  {type: "system", subtype: "turn_duration", timestamp: $p}' > "$SL/s1.jsonl"
cp "$(command -v bash)" "$T/claude"; ( "$T/claude" -c 'sleep 60 3>>"$1"; :' _ "$T/b1.output" </dev/null >/dev/null 2>&1 & echo $! > "$T/bgpid" ); sleep 0.3
check "plan seat, plan committed, its background command still held: no block" '' "$(claude term_plan 'Plan revised and committed.')"
pkill -P "$(cat "$T/bgpid")"; kill "$(cat "$T/bgpid")" 2>/dev/null; sleep 0.3
check "and once the command's holder is gone, the hook blocks" block "$(claude term_plan 'Plan revised and committed.' | jq -r .decision 2>&1)"
# When neither lsof nor fuser answers, the reader cannot tell a live background command from a dead one: no block.
# Nothing is kept between two Stops: the next one, with the tools answering, blocks.
mkdir -p "$T/noholders"; printf '#!/usr/bin/env bash\necho "$0: refused" >&2; exit 2\n' > "$T/noholders/lsof"
cp "$T/noholders/lsof" "$T/noholders/fuser"; chmod +x "$T/noholders/lsof" "$T/noholders/fuser"
check "plan seat, plan committed, neither lsof nor fuser answers for its background command: no block" '' \
  "$(PATH="$T/noholders:$PATH" claude term_plan 'Plan revised and committed.')"
check "and the next Stop, the tools answering, blocks" block "$(claude term_plan 'Plan revised and committed.' | jq -r .decision 2>&1)"
# A committed draft with later uncommitted plan edits is unfinished: no block asks for PLAN-DONE over it.
echo 'TODO: finish rollback' >> "$T/ws/u1/.claude/plans/u1.md"
check "plan seat, plan committed, later uncommitted plan edits: no block" '' "$(claude term_plan 'Plan revised and committed.')"
git -C "$T/ws/u1" checkout -q HEAD -- .claude/plans/u1.md
# An index flag hides that edit from git's own diff; nothing is kept: the next Stop, the file the commit, blocks.
for f in assume-unchanged skip-worktree; do
  git -C "$T/ws/u1" update-index --$f .claude/plans/u1.md; echo 'TODO: finish rollback' >> "$T/ws/u1/.claude/plans/u1.md"
  check "plan seat, plan committed, a later edit hidden by --$f: no block" '' "$(claude term_plan 'Plan revised and committed.')"
  git -C "$T/ws/u1" show HEAD:.claude/plans/u1.md > "$T/ws/u1/.claude/plans/u1.md"
  check "and the next Stop, the file the commit, the flag still set, blocks" block \
    "$(claude term_plan 'Plan revised and committed.' | jq -r .decision 2>&1)"
  git -C "$T/ws/u1" update-index --no-$f .claude/plans/u1.md
done
# A clean filter that maps the edited bytes back to the committed blob hides the edit the same way.
A=$(git -C "$T/ws/u1" rev-parse --path-format=absolute --git-path info/attributes); mkdir -p "${A%/*}"
echo '*.md filter=drop' > "$A"; git -C "$T/ws/u1" config filter.drop.clean 'grep -v TODO'
echo 'TODO: finish rollback' >> "$T/ws/u1/.claude/plans/u1.md"
check "plan seat, plan committed, a later edit a clean filter drops: no block" '' "$(claude term_plan 'Plan revised and committed.')"
git -C "$T/ws/u1" show HEAD:.claude/plans/u1.md > "$T/ws/u1/.claude/plans/u1.md"
check "and the next Stop, the file the commit, the filter still set, blocks" block \
  "$(claude term_plan 'Plan revised and committed.' | jq -r .decision 2>&1)"
rm -f "$A"; git -C "$T/ws/u1" config --unset filter.drop.clean

# Issue 321: a Claude reply's text blocks, in one record or one record each under the same message id, are one reply:
# a question in an earlier block still sends. A question in an earlier reply (another message id) is history.
raw() { printf '%s\n' "$@" > "$T/tr.jsonl"; jq -n --arg p "$T/tr.jsonl" '{transcript_path: $p, stop_hook_active: false, hook_event_name: "Stop"}' \
  | run term_free bash "$SOURCE/hooks/claude-worker-notify.sh" >/dev/null; }
Q='{"type":"text","text":"QUESTION: Which branch should I use?"}' A='{"type":"text","text":"I need that answer before proceeding."}'
: > "$T/sends"; raw '{"type":"assistant","uuid":"q1","message":{"content":['"$Q,$A"']}}'
check "claude: a question in the first of a record's two text blocks sends one message" 1 "$(sends 'claude turn complete: QUESTION (u1)')"
: > "$T/sends"; raw '{"type":"assistant","uuid":"q2","message":{"id":"m2","content":['"$Q"']}}' '{"type":"assistant","uuid":"q3","message":{"id":"m2","content":['"$A"']}}'
check "claude: a question in its own record, the reply's next block in another of the same message: one message" 1 "$(sends 'claude turn complete: QUESTION (u1)')"
: > "$T/sends"; raw '{"type":"assistant","uuid":"q4","message":{"id":"m4","content":['"$Q"']}}' '{"type":"assistant","uuid":"q5","message":{"id":"m5","content":['"$A"']}}'
check "claude: a question in an earlier reply, the latest without one: nothing sent" 0 "$(sends)"

# Issue 331: a turn-complete report Orca takes writes one sent line to main's run; a refused one writes one refused line.
WLJ=$T/sc/wake-log.jsonl
logged() { jq -rs 'map("\(.from):\(.to):\(.result)") | join(",")' "$WLJ" 2>/dev/null; }
for h in claude:worker-notify codex:codex-notify; do
  n=${h%%:*} from=${h#*:}
  rm -f "$WLJ" "$T/refuse"; : > "$T/sends"; $n term_free $'QUESTION: Which branch should I use?\n' >/dev/null
  check "$n: a report Orca takes writes one sent line to main's run" "$from:run:run_t:sent" "$(logged)"
  rm -f "$WLJ"; touch "$T/refuse"; $n term_free $'QUESTION: Which branch is it?\n' >/dev/null
  check "$n: a refused report writes one refused line carrying Orca's reason" "$from:run:run_t:refused:1" \
    "$(logged):$(grep -c 'refused by the stub' "$WLJ")"
done
rm -f "$T/refuse"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
