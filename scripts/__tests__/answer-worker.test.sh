#!/usr/bin/env bash
# Main answers a Builder with answer-worker.sh. Every answer sent while the
# Builder was mid-turn printed "NOT delivered", yet the Builder read it at its
# next check: main could not tell a late read from a lost answer, and sent it
# again. Pinned: an answer left in a mid-turn pane's inbox reports queued, not
# read yet, is checked on, and ends NOT acknowledged (exit 1) only after the acknowledgement limit; an answer to a Builder past its
# done marker is typed in even while Orca still calls it working (it never
# reads its inbox again); an answer typed into an idle pane
# whose log shows it is delivered (exit 0); a pane that is gone, or an idle
# pane whose log never shows it, is NOT delivered (exit 1).
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ws/u1/.claude/briefs"; : > "$T/ws/u1/.claude/briefs/u1.md"
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
LOG=$T/home/.claude/projects/$(printf '%s' "$T/ws/u1" | tr -c 'A-Za-z0-9' '-')/s1.jsonl
mkdir -p "$(dirname "$LOG")"
echo '{"type":"user","message":{"role":"user","content":"build it"},"timestamp":"2026-10-15T10:00:00Z","sessionId":"s1"}' > "$LOG"
# Orca: one Claude pane term_b in worktree wt (and a Codex reviewer beside it when $T/two exists), its state in $T/state; a typed text lands in the pane's log
# unless $T/deaf exists; an inbox send lands in $T/inbox.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "terminal list") jq -n '{result: {terminals: [{handle: "term_b", tabId: "t1", leafId: "l1", worktreePath: "$T/ws/u1"}]}}' ;;
  "worktree ps") jq -n --arg s "\$(cat "$T/state")" --argjson two "\$([ -e "$T/two" ] && echo true || echo false)" \
    '{result: {worktrees: [{path: "$T/ws/u1", agents: ([{paneKey: "t1:l1", agentType: "claude", state: \$s}] + if \$two then [{paneKey: "t1:l2", agentType: "codex", state: "working"}] else [] end)}]}}' ;;
  "terminal send") while [ \$# -gt 0 ]; do case \$1 in --text) t=\$2 ;; esac; shift; done
    echo typed >> "$T/typed"
    [ -e "$T/deaf" ] || jq -cn --arg t "\$t" '{type: "user", message: {role: "user", content: \$t}, timestamp: "2026-10-15T10:05:00Z", sessionId: "s1"}' >> "$LOG"
    echo '{"ok":true}' ;;
  "orchestration check") if [ -e "$T/asked" ]; then echo '{"ok":true,"result":{"messages":[]}}'; else touch "$T/asked"
    jq -n '{ok: true, result: {deliveryId: "d1", messages: [{id: "msg_q1", from_handle: "term_b", type: "question", subject: "question (u1)", body: "which option?"}]}}'; fi ;;
  "orchestration task-update") echo "\$*" >> "$T/updates"; echo '{"ok":true}' ;;
  # Issue 351: the pane's questions are $T/inbox.json (inbox-down: the read fails); a task's dispatch is ctx_<task>.
  "orchestration inbox") [ ! -e "$T/inbox-down" ] || exit 1; cat "$T/inbox.json" 2>/dev/null || echo '{"result":{"messages":[]}}' ;;
  "orchestration dispatch-show") while [ \$# -gt 0 ]; do case \$1 in --task) k=\$2 ;; esac; shift; done; jq -n --arg d "ctx_\${k#task_}" '{ok: true, result: {dispatch: {id: \$d}}}' ;;
  "orchestration send") while [ \$# -gt 0 ]; do case \$1 in --body) b=\$2 ;; esac; shift; done; printf '%s\n' "\$b" >> "$T/inbox"; echo '{"ok":true}' ;;
  "orchestration reply") while [ \$# -gt 0 ]; do case \$1 in --body) b=\$2 ;; --id) i=\$2 ;; esac; shift; done; printf '%s %s\n' "\$i" "\$b" >> "$T/replies"
    # a waiting ask reads its reply at once: the reply lands in the pane's log while $T/reads exists
    [ -e "$T/reads" ] && jq -cn --arg t "\$b" '{type: "user", message: {role: "user", content: \$t}, timestamp: "2026-10-15T10:05:00Z", sessionId: "s1"}' >> "$LOG"
    echo '{"ok":true}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
answer() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR COMMANDECK_FOREGROUND=1 HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" ANSWER_WORKER_WAIT=2 ANSWER_WORKER_ACK_WAIT=${AACK:-3} PATH="$T/bin:$PATH" bash "$REAL/scripts/answer-worker.sh" "$@" 2>&1); }

# A Builder's question, as main's wait shows it: recorded in the decisions ledger as waiting on main.
LED=$T/p/.claude/metrics/decisions.jsonl
(cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch" \
  PATH="$T/bin:$PATH" bash "$REAL/scripts/orca-wait.sh" >/dev/null 2>&1)
check "a Builder's question lands in the ledger, waiting on main" '{"answer":null,"id":"u1-msg_q1","question":"question (u1): which option?","source":"u1 asks","waitsOn":"main"}' \
  "$(jq -cS 'del(.askedAt, .answeredAt, .proposedDefault)' "$LED" 2>/dev/null)"
echo working > "$T/state"
OUT=$(answer term_b "use the second option"); RC=$?
check "main's answer closes it" '"use the second option"' "$(tail -1 "$LED" | jq -c 'select(.answeredAt != null) | .answer')"
check "an answer to a mid-turn pane that is never read says queued first, then ends NOT acknowledged (exit 1), not NOT delivered" "1:1:0:1" \
  "$RC:$(grep -c 'queued, not read yet' <<<"$OUT"):$(grep -c 'NOT delivered' <<<"$OUT"):$(grep -c 'NOT acknowledged' <<<"$OUT")"
check "and waits in its inbox for its next check" 1 "$(grep -c '\] use the second option$' "$T/inbox")"
# Issue 329: a Builder blocked in `orchestration ask` returns only on a reply to its question's id, never on a new send.
: > "$T/inbox"; : > "$T/replies"; : > "$T/typed"; touch "$T/reads"
OUT=$(answer term_b "pick two" u1-msg_q1); RC=$?
check "a mid-turn pane given u1-msg_q1 is answered by orchestration reply --id msg_q1, no send, no typing, and confirmed" "0:1:0:0:1" \
  "$RC:$(grep -c '^msg_q1 \[answer-.*\] pick two$' "$T/replies"):$(wc -l < "$T/inbox" | tr -d ' '):$(wc -l < "$T/typed" | tr -d ' '):$(grep -c "sent to the pane's inbox as a reply to msg_q1" <<<"$OUT")"
: > "$T/replies"
OUT=$(answer term_b "pick three" msg_q1); RC=$?
check "a bare msg_ id names the reply too" "0:1" "$RC:$(grep -c '^msg_q1 ' "$T/replies")"
# Issue 331: each answer leaves one line in the wake log, to the Builder's handle, so an answer that never reached it shows.
WLN=$(wc -l < "$T/scratch/wake-log.jsonl" 2>/dev/null | tr -d ' ')
OUT=$(answer term_b "pick two again" u1-msg_q1); RC=$?
check "an inbox reply writes one line to the Builder's handle" "1:answer-worker:term_b:sent" \
  "$(( $(wc -l < "$T/scratch/wake-log.jsonl" | tr -d ' ') - WLN )):$(tail -1 "$T/scratch/wake-log.jsonl" | jq -r '"\(.from):\(.to):\(.result)"')"
: > "$T/replies"
# Green pins: the fallback and the queued report the reply must not break.
: > "$T/replies"; : > "$T/inbox"
OUT=$(answer term_b "pick four"); RC=$?
check "a mid-turn pane given no id is sent the answer as before, with no reply and none named" "1:0:1:0" \
  "$RC:$(wc -l < "$T/replies" | tr -d ' '):$(wc -l < "$T/inbox" | tr -d ' '):$(grep -c 'as a reply' <<<"$OUT")"
rm "$T/reads"; : > "$T/replies"
OUT=$(answer term_b "pick five" u1-msg_q1); RC=$?
check "a reply to a pane still mid-turn after the wait is queued, then NOT acknowledged (exit 1), not NOT delivered" "1:1:0:1" \
  "$RC:$(grep -c 'queued, not read yet' <<<"$OUT"):$(grep -c 'NOT delivered' <<<"$OUT"):$(grep -c 'NOT acknowledged' <<<"$OUT")"
: > "$T/inbox"
# Two questions open from one unit: an answer closes only the one it names, never the other as answered.
for q in q2 q3; do (cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" \
  bash "$REAL/scripts/decision.sh" add "u1-msg_$q" "question $q" none 'u1 asks' --waits-on main >/dev/null); done
open() { jq -rs 'group_by(.id) | map(last | select(.answeredAt == null) | .id) | join(" ")' "$LED"; }
OUT=$(answer term_b "keep the fixture")
check "an answer naming no question, with two open, closes neither and names both" "u1-msg_q2 u1-msg_q3:1" \
  "$(open):$(grep -c 'u1-msg_q2.*u1-msg_q3' <<<"$OUT")"
answer term_b "yes, delete it" u1-msg_q3 >/dev/null
check "an answer naming its question closes that one only" "u1-msg_q2" "$(open)"
# The bare msg_ form names the reply, so it must close the ledger's <unit>-msg_ question too, or it stays on the dashboard.
OUT=$(answer term_b "keep it" msg_q2)
check "an answer naming a bare msg_ id closes the unit's <unit>-msg_ question" ":0" "$(open):$(grep -c 'no open question' <<<"$OUT")"

# Past its done marker, beside its reviewer, Orca still says working: the Builder's own log says its turn is over.
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"All built.\nU-DONE"}]},"timestamp":"2026-10-15T10:01:00Z","sessionId":"s1"}' \
  '{"type":"system","subtype":"turn_duration","timestamp":"2026-10-15T10:01:01Z","sessionId":"s1"}' >> "$LOG"
touch "$T/two"; : > "$T/inbox"
OUT=$(answer term_b "one more fix"); RC=$?
check "an answer after the done marker is typed in and read, though Orca says working" "0:1:0" \
  "$RC:$(grep -c 'delivered to term_b (typed into the pane)' <<<"$OUT"):$(wc -l < "$T/inbox" | tr -d ' ')"
rm "$T/two"

echo idle > "$T/state"
# Issue 227: main closed the main-watch item task of a question by hand once it was answered; the delivery does it.
mkdir -p "$T/scratch/main-watch"; : > "$T/updates"
printf 'posted=1\ntask=task_item_b\n' > "$T/scratch/main-watch/item-seat-term_b-task_b"; printf 'posted=1\ntask=task_item_o\n' > "$T/scratch/main-watch/item-seat-term_o-task_o"
OUT=$(answer term_b "go ahead"); RC=$?
check "an answer typed into an idle pane that shows it is delivered" "0:1" "$RC:$(grep -c 'delivered to term_b (typed into the pane)' <<<"$OUT")"
check "a delivered answer completes that pane's item task, and not another pane's" "1:0" \
  "$(grep -c -- '--id task_item_b --status completed' "$T/updates"):$(grep -c task_item_o "$T/updates")"
# Host issue 2998: given the question's id, a typed answer ends with a reply in that question's thread (the only answer
# pp_task_close counts), and only once the pane's log shows it.
: > "$T/replies"
OUT=$(answer term_b "go ahead, typed" u1-msg_q1); RC=$?
check "a typed answer given the question's id replies in its thread once it is delivered" "0:1" \
  "$RC:$(grep -c '^msg_q1 \[answer-.*\] go ahead, typed$' "$T/replies")"
touch "$T/deaf"; : > "$T/replies"
OUT=$(answer term_b "stop here"); RC=$?
check "an idle pane whose log never shows the answer: NOT delivered" "1:1:0" "$RC:$(grep -c 'NOT delivered' <<<"$OUT"):$(grep -c 'queued' <<<"$OUT")"
OUT=$(answer term_b "stop here too" u1-msg_q1); RC=$?
check "and an answer that never reached the log replies in no thread" "1:0" "$RC:$(wc -l < "$T/replies" | tr -d ' ')"
OUT=$(answer term_gone "hello"); RC=$?
check "a pane that is gone: nothing sent, and said" "1:1" "$RC:$(grep -c 'no agent pane term_gone' <<<"$OUT")"

# Two Claude planners share one <unit>-plan worktree. Planner A is mid-turn, planner B (newer log) is done: an answer
# to A must be read against A's own log (the launch binding), or B's finished turn types it into A's busy pane.
W2=$T/ws/u2-plan; P2=$T/home/.claude/projects/$(printf '%s' "$W2" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$W2" "$P2" "$T/scratch" "$T/bin2"
for x in a b; do
  printf 'handle=term_p%s\nrole=plan-author\nunit=u2\nlaunched=1760000000\ntag=SEAT-TAG-%s\n' "$x" "$x" > "$T/scratch/seat-u2-plan-$x.txt"
  jq -nc --arg p "Seat tag SEAT-TAG-$x: plan it." '{type: "user", message: {role: "user", content: $p}, timestamp: "2025-10-09T08:00:0'$([ $x = a ] && echo 1 || echo 5)'Z"}' > "$P2/$x.jsonl"
done
echo '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"Planned.\nPLAN-DONE"}]},"timestamp":"2025-10-09T08:01:00Z"}' >> "$P2/b.jsonl"
echo '{"type":"system","subtype":"turn_duration","timestamp":"2025-10-09T08:01:01Z"}' >> "$P2/b.jsonl"
cat > "$T/bin2/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "terminal list") jq -n '{result: {terminals: [{handle: "term_pa", tabId: "t2", leafId: "l1", worktreePath: "$W2"}, {handle: "term_pb", tabId: "t2", leafId: "l2", worktreePath: "$W2"}]}}' ;;
  "worktree ps") jq -n '{result: {worktrees: [{path: "$W2", agents: [{paneKey: "t2:l1", agentType: "claude", state: "working"}, {paneKey: "t2:l2", agentType: "claude", state: "idle"}]}]}}' ;;
  "terminal send") echo typed >> "$T/typed2"; echo '{"ok":true}' ;;
  "orchestration send") while [ \$# -gt 0 ]; do case \$1 in --body) b=\$2 ;; esac; shift; done; printf '%s\n' "\$b" >> "$T/inbox2"; echo '{"ok":true}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$T/bin2/orca-ide"
: > "$T/typed2"; : > "$T/inbox2"; touch -d '2 hours ago' "$P2/a.jsonl" # B's log is the newer one, as --current reads it
OUT=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR COMMANDECK_FOREGROUND=1 HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch" \
  ANSWER_WORKER_WAIT=2 ANSWER_WORKER_ACK_WAIT=3 PATH="$T/bin2:$PATH" bash "$REAL/scripts/answer-worker.sh" term_pa "take option two" 2>&1); RC=$?
check "an answer to planner A reads A's log: A is mid-turn, so it goes to A's inbox, not typed in" "1:1:0" \
  "$RC:$(wc -l < "$T/inbox2" | tr -d ' '):$(wc -l < "$T/typed2" | tr -d ' ')"

# Issue 340: in main's own foreground the answer is sent and the call returns at once; the wait for the tag in the log,
# its retry and the ledger closing run in a detached follower, and main hears only if the answer is NOT delivered.
rm -f "$T/deaf"; : > "$T/inbox"; : > "$T/typed"
fg() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR -u COMMANDECK_FOREGROUND CLAUDECODE=1 HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" ANSWER_WORKER_WAIT=${AWAIT:-2} ANSWER_WORKER_ACK_WAIT=${AACK:-3} PATH="$T/bin:$PATH" timeout 8 bash "$REAL/scripts/answer-worker.sh" "$@" </dev/null 2>&1); }
fgpid() { sed -n 's/.*(pid \([0-9]*\)).*/\1/p' <<<"$1"; }
echo working > "$T/state"
OUT=$(AWAIT=30 fg term_b "fg inbox answer"); RC=$?; PID=$(fgpid "$OUT")
check "in main's foreground a 30 s wait returns 0 at once, naming the follower's log; the answer is in the inbox" "0:1:1" \
  "$RC:$(grep -c 'checked in the background' <<<"$OUT"):$(grep -c 'fg inbox answer' "$T/inbox")"
[ -z "$PID" ] || { pkill -P "$PID" 2>/dev/null; kill "$PID" 2>/dev/null; }
echo idle > "$T/state"; : > "$T/inbox"
OUT=$(fg term_b "fg typed answer"); RC=$?; PID=$(fgpid "$OUT")
[ -z "$PID" ] || tail --pid="$PID" -f /dev/null
check "a delivered answer: the follower's log says delivered, and main is sent nothing" "0:1:0" \
  "$RC:$(cat "$T"/scratch/answer-worker-answer-*.log 2>/dev/null | grep -c 'delivered to term_b (typed into the pane)'):$(wc -l < "$T/inbox" | tr -d ' ')"
touch "$T/deaf"; rm -f "$T"/scratch/answer-worker-answer-*.log
OUT=$(fg term_b "fg lost answer"); RC=$?; PID=$(fgpid "$OUT")
[ -z "$PID" ] || tail --pid="$PID" -f /dev/null
check "an answer that never reaches the log: the call returned 0, the follower logs NOT delivered, and main is told" "0:1:1" \
  "$RC:$(cat "$T"/scratch/answer-worker-answer-*.log 2>/dev/null | grep -c 'NOT delivered'):$(cat "$T"/scratch/queue/*.jsonl 2>/dev/null | grep -c 'answer-worker.sh: not delivered')"
rm -f "$T/deaf"

# Issue 351: an inbox answer to a pane that is mid-turn is checked on after the first wait (queued, said once), until the
# tag is in the log (delivered) or the acknowledgement limit passes (NOT acknowledged, exit 1). In main's foreground the
# follower sends main that last result as one question.
echo working > "$T/state"; : > "$T/inbox"; : > "$T/typed"
(sleep 4; jq -cn '{type: "user", message: {role: "user", content: "[late-tag] a late read"}, timestamp: "2026-10-15T10:06:00Z", sessionId: "s1"}' >> "$LOG") &
OUT=$(AACK=12 ANSWER_WORKER_TAG=late-tag answer term_b "a late read"); RC=$?; wait
check "an answer read during the longer wait ends delivered (exit 0), after the queued line, and is not NOT acknowledged" "0:1:1:0" \
  "$RC:$(grep -c 'queued, not read yet' <<<"$OUT"):$(grep -c 'delivered to term_b' <<<"$OUT"):$(grep -c 'NOT acknowledged' <<<"$OUT")"
: > "$T/inbox"; rm -f "$T"/scratch/answer-worker-answer-*.log "$T"/scratch/queue/*.jsonl
OUT=$(fg term_b "fg unread answer"); RC=$?; PID=$(fgpid "$OUT")
[ -z "$PID" ] || tail --pid="$PID" -f /dev/null
check "in main's foreground an answer never read reaches main as one question" "0:1:1" \
  "$RC:$(cat "$T"/scratch/answer-worker-answer-*.log 2>/dev/null | grep -c 'NOT acknowledged'):$(cat "$T"/scratch/queue/*.jsonl 2>/dev/null | grep -c 'answer-worker.sh: not delivered')"

# Issue 351 ask 1: main answers without the question's id. A pane blocked in `orchestration ask` returns only on a reply
# in its question's thread, so the answer looks up the pane's own open question from its seat record, the way
# pp_task_close counts it (one helper, pp_seat_open_ask): asked under the seat's dispatch, since the seat's launch, by
# this pane and no other. Without it the answer is a plain send and the asker waits out its limit.
# The seat: pane term_b, task_w (its dispatch is ctx_w), launched 1000 s ago.
NOWTS=$(date +%s); LOOKREC=$T/scratch/seat-look-builder.txt
rm -f "$T"/scratch/seat-*.txt "$T"/scratch/answer-worker-answer-*.log; : > "$T/replies"; : > "$T/inbox"; : > "$T/typed"
printf 'handle=term_b\ntask=task_w\nrole=builder\nunit=look\nlaunched=%s\n' $((NOWTS - 1000)) > "$LOOKREC"
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
msg() { jq -nc --arg id "$1" --arg from "$2" --arg at "$3" '{id:$id,type:"question",from_handle:$from,thread_id:null,created_at:$at}'; }
inbox() { jq -sc '{result:{messages:.}}' > "$T/inbox.json"; : > "$T/replies"; : > "$T/inbox"; }
echo working > "$T/state"; touch "$T/reads"
{ msg msg_q0 dispatch:ctx_w "$(iso $((NOWTS - 2000)))"; msg msg_qx term_x "$(iso $((NOWTS - 10)))"; msg msg_q1 dispatch:ctx_w "$(iso $((NOWTS - 20)))"; } | inbox
OUT=$(answer term_b "Ruling 4"); RC=$?
check "no id given, the pane has an open question under its dispatch: the answer is a reply in that thread, and no other question gets one" "0 1 0 0" \
  "$RC $(grep -c '^msg_q1 .*Ruling 4' "$T/replies") $(grep -c '^msg_q0' "$T/replies") $(grep -c '^msg_qx' "$T/replies")"
check "no id given: the answer says which question it replied in" 1 "$(grep -c 'replying in msg_q1, the open question of term_b' <<<"$OUT")"
# Nothing open (an older question from before the launch, another pane's): sent as today and nothing said of a lookup.
{ msg msg_q0 dispatch:ctx_w "$(iso $((NOWTS - 2000)))"; msg msg_qx term_x "$(iso $((NOWTS - 10)))"; } | inbox
OUT=$(answer term_b "Ruling 5"); RC=$?
check "no open question: a plain inbox send (queued, mid-turn), no reply, no lookup complaint" "1 0 1 0" \
  "$RC $(wc -l < "$T/replies" | tr -d ' ') $(grep -c 'Ruling 5' "$T/inbox") $(grep -c 'could not be read\|no seat record' <<<"$OUT")"
inbox </dev/null; : > "$T/inbox-down"
OUT=$(answer term_b "Ruling 6"); RC=$?
check "no id given and the inbox cannot be read: says so and sends without an id" "1 0 1 1" \
  "$RC $(wc -l < "$T/replies" | tr -d ' ') $(grep -c 'Ruling 6' "$T/inbox") $(grep -c 'open question of term_b could not be read' <<<"$OUT")"
rm -f "$T/inbox-down"; mv "$LOOKREC" "$LOOKREC.gone"
OUT=$(answer term_b "Ruling 7"); RC=$?
check "no id given and no seat record names the pane: says the lookup was skipped and sends as today" "1 1 1" \
  "$RC $(grep -c 'Ruling 7' "$T/inbox") $(grep -c 'no seat record names term_b, so its open question was not looked up' <<<"$OUT")"
mv "$LOOKREC.gone" "$LOOKREC"
# --interrupt (issue 351 ask 4) has its own file: answer-worker-interrupt.test.sh.

# Issue 447: a Claude pane whose running tool call is not a wait never reads its inbox, so an order left there sat unread
# while the Builder built what the order cancelled. Claude Code hands it typed text at its next tool result. The log is
# rebuilt for these two (the one above ends in a done marker) and put back after.
cp "$LOG" "$T/log.bak"
BUSY_USE='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_work","name":"Bash","input":{"command":"npm test"}}]}}'
PARK_USE='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_park","name":"Bash","input":{"command":"orca-ide orchestration check --wait"}}]}}'
rows() { { echo '{"type":"user","message":{"role":"user","content":"build it"},"timestamp":"2026-10-15T10:00:00Z","sessionId":"s1"}'; echo "$1"; } > "$LOG"; : > "$T/typed"; : > "$T/inbox"; : > "$T/replies"; }
echo working > "$T/state"
rows "$BUSY_USE"
OUT=$(answer term_b "Ruling 8: drop the last item"); RC=$?
check "a Claude pane mid-work gets the answer typed at once, no inbox, confirmed in its log (issue 447)" "0 1 0 1" \
  "$RC $(wc -l < "$T/typed" | tr -d ' ') $(wc -l < "$T/inbox" | tr -d ' ') $(grep -c 'delivered to term_b (typed into the pane mid-work' <<<"$OUT")"
rows "$PARK_USE"
OUT=$(answer term_b "Ruling 9: keep the last item"); RC=$?
check "a pane parked in check --wait still gets the inbox message (issue 447)" "1 0 1" \
  "$RC $(wc -l < "$T/typed" | tr -d ' ') $(grep -c 'Ruling 9' "$T/inbox")"
cp "$T/log.bak" "$LOG"

# Issue 454: a Builder in ask-main.sh's wait is a pane that reads its inbox, and its question is the one whose call token
# (<id>.asking, pid= and pane=, beside the wait token <id>.wait) names it. With no id given and no seat record, the token
# supplies the id, so the answer is a reply in that thread (the only way ask-main.sh returns) and closes that question
# only. The tokens are read, never moved.
rm -f "$T"/scratch/seat-*.txt; mkdir -p "$T/scratch/ask-main"
bash -c 'sleep 30; :' ask-main.sh & WAITPID=$!
printf 'pid=%s\npane=term_b\n' "$WAITPID" > "$T/scratch/ask-main/msg_new.wait"; cp "$T/scratch/ask-main/msg_new.wait" "$T/scratch/ask-main/msg_new.asking"
ASK_USE='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_ask","name":"Bash","input":{"command":"bash scripts/ask-main.sh q body"}}]}}'
MIX_USE='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_mix","name":"Bash","input":{"command":"ask-main.sh q b; npm test"}}]}}'
echo working > "$T/state"; touch "$T/reads"
rows "$ASK_USE"
OUT=$(answer term_b "Ruling 10: wait in ask-main"); RC=$?
check "a pane waiting in ask-main.sh gets its answer as a reply in its question's thread, nothing typed (issue 454)" "0 1 0 0 1" \
  "$RC $(grep -c '^msg_new .*Ruling 10' "$T/replies") $(wc -l < "$T/typed" | tr -d ' ') $(wc -l < "$T/inbox" | tr -d ' ') $(grep -c "^pane=term_b$" "$T/scratch/ask-main/msg_new.wait" 2>/dev/null)"
# F1: the same call inside a compound command reads as work, so the answer is typed at its next tool result, as before.
rows "$MIX_USE"
OUT=$(answer term_b "Ruling 11: compound call"); RC=$?
check "a compound ask-main.sh call reads as work: the answer is typed, not left in the inbox (issue 454)" "0 1 0" \
  "$RC $(wc -l < "$T/typed" | tr -d ' ') $(wc -l < "$T/inbox" | tr -d ' ')"
rows "$ASK_USE"
for q in new q4; do (cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" \
  bash "$REAL/scripts/decision.sh" add "u1-msg_$q" "question $q" none 'u1 asks' --waits-on main >/dev/null); done
OUT=$(answer term_b "Ruling 12: the waiting one"); RC=$?
check "an answer with no id and no seat record replies in the waiting question's thread and closes only that question (issue 454)" "0 1 u1-msg_q4 1" \
  "$RC $(grep -c '^msg_new .*Ruling 12' "$T/replies") $(open) $(grep -c 'replying in msg_new' <<<"$OUT")"
# Between two inbox waits (a batch without the answer is being printed) ask-main.sh holds no <id>.wait, only the
# call-long <id>.asking: an answer sent in that gap still replies in the question's thread, the only way the call returns.
mv "$T/scratch/ask-main/msg_new.wait" "$T/scratch/ask-main/msg_new.asking"
OUT=$(answer term_b "Ruling 13: between two waits"); RC=$?
check "an answer sent while ask-main.sh is between two inbox waits replies in its question's thread" "0 1 0" \
  "$RC $(grep -c '^msg_new .*Ruling 13' "$T/replies") $(wc -l < "$T/typed" | tr -d ' ')"
kill "$WAITPID" 2>/dev/null; wait "$WAITPID" 2>/dev/null
cp "$T/log.bak" "$LOG"

# Issue 463: main's foreground call returns before ask-main.sh writes its question's token, so a send can find none. The
# stub's `orchestration send` writes the tokens as it returns, no sleep; only a look after the send can see them.
rm -f "$T"/scratch/seat-*.txt "$T"/scratch/ask-main/* "$T"/scratch/answer-worker-answer-*.log; mkdir -p "$T/bin3"
cat > "$T/bin3/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "orchestration send") "$T/bin/orca-ide" "\$@"
    if [ -e "$T/gap" ]; then for k in wait asking; do printf 'pid=%s\npane=term_b\n' "\$(cat "$T/gap")" > "$T/scratch/ask-main/msg_gap.\$k"; done; fi ;;
  "terminal send") a=("\$@"); while [ \$# -gt 0 ]; do case \$1 in --text) t=\$2 ;; esac; shift; done
    if [ "\$t" = \$'\x1b' ]; then echo esc >> "$T/esc"
      [ ! -e "$T/esc-works" ] || { kill "\$(cat "$T/escpid")"; echo idle > "$T/state"
        printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_ask","is_error":true,"content":"interrupted"}]},"timestamp":"2026-10-15T10:07:00Z","sessionId":"s1"}' \
          '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]},"timestamp":"2026-10-15T10:07:01Z","sessionId":"s1"}' >> "$LOG"; }
      echo '{"ok":true}'
    else "$T/bin/orca-ide" "\${a[@]}"
      # the fresh session reads the answer file: its text, tag included, reaches the pane's log
      case "\$t" in *"Your task spec is the file"*) cat "$T"/ws/u1/.claude/briefs/u1-answer-*.md | jq -Rsc '{type: "user", message: {role: "user", content: .}, timestamp: "2026-10-15T10:09:00Z", sessionId: "s2"}' >> "$LOG" ;; esac
    fi ;;
  *) exec "$T/bin/orca-ide" "\$@" ;;
esac
EOF
chmod +x "$T/bin3/orca-ide"
answer3() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR COMMANDECK_FOREGROUND=1 HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_FRESH_ROUND_SETTLE_SECONDS=0 ANSWER_WORKER_WAIT=2 ANSWER_WORKER_ACK_WAIT=${AACK:-3} PATH="$T/bin3:$PATH" bash "$REAL/scripts/answer-worker.sh" "$@" 2>&1); }
fg3() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR -u COMMANDECK_FOREGROUND CLAUDECODE=1 HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" ANSWER_WORKER_WAIT=2 ANSWER_WORKER_ACK_WAIT=${AACK:-3} PATH="$T/bin3:$PATH" timeout 8 bash "$REAL/scripts/answer-worker.sh" "$@" </dev/null 2>&1); }
bash -c 'sleep 30; :' ask-main.sh & GAPPID=$!; echo "$GAPPID" > "$T/gap"
echo working > "$T/state"; touch "$T/reads"; rows "$ASK_USE"
OUT=$(answer3 term_b "Ruling 14: the gap"); RC=$?
check "a start-gap answer threads (issue 463)" "0 1 1" \
  "$RC $(grep -c '^msg_gap .*Ruling 14' "$T/replies") $(grep -c 'replying in msg_gap' <<<"$OUT")"
# The same in main's foreground: the detached follower, not the call, is the one that looks again.
rm -f "$T/scratch/ask-main/msg_gap".*; rows "$ASK_USE"
OUT=$(fg3 term_b "Ruling 15: the follower"); RC=$?
for _ in $(seq 80); do grep -q 'delivered to term_b' "$T"/scratch/answer-worker-answer-*.log 2>/dev/null && break; sleep 0.1; done
check "the follower finds the token (issue 463)" "0 1 1" \
  "$RC $(grep -c '^msg_gap .*Ruling 15' "$T/replies") $(cat "$T"/scratch/answer-worker-answer-*.log 2>/dev/null | grep -c 'replying in msg_gap')"
rm -f "$T/gap" "$T/scratch/ask-main/msg_gap".*; kill "$GAPPID" 2>/dev/null; wait "$GAPPID" 2>/dev/null

# Issue 478: past the cache's start + ttl a Builder's old session is stale and its answer is fresh-session work. Idle, it
# is handed over; parked in ask-main.sh's wait, one Escape (A17: the pid ends, the tool call is_error, no model call)
# ends the wait first, and the hand-off runs only once that is confirmed.
printf 'handle=term_b\nrole=builder\nunit=u1\n' > "$T/scratch/seat-u1-builder.txt"
COLD='{"type":"assistant","message":{"id":"m1","role":"assistant","usage":{"input_tokens":5,"cache_creation_input_tokens":900,"cache_creation":{"ephemeral_5m_input_tokens":900}},"content":[{"type":"text","text":"x"}]},"timestamp":"2026-10-15T10:00:30Z","sessionId":"s1"}'
rows "$COLD"; echo idle > "$T/state"; rm -f "$T"/ws/u1/.claude/briefs/u1-answer-*.md
OUT=$(answer3 term_b "Ruling 16: cold"); RC=$?; wait
check "a cold answer goes fresh (issue 478)" "0 1 1" \
  "$RC $(grep -c 'delivered to term_b (handed to a fresh session)' <<<"$OUT") $(cat "$T"/ws/u1/.claude/briefs/u1-answer-*.md | grep -c 'Ruling 16: cold')"
# The same seat with a warm cache keeps its session: the expiry is what sends an answer fresh.
rows "$COLD"; jq -c --arg t "$(date -u +%FT%TZ)" '.timestamp = $t' "$LOG" > "$LOG.warm"; mv "$LOG.warm" "$LOG"
echo idle > "$T/state"; rm -f "$T"/ws/u1/.claude/briefs/u1-answer-*.md
OUT=$(answer3 term_b "Ruling 16: warm"); wait
check "a cold answer goes fresh (issue 478)" "0 0" \
  "$(grep -c 'handed to a fresh session' <<<"$OUT") $(ls "$T"/ws/u1/.claude/briefs/u1-answer-*.md 2>/dev/null | wc -l | tr -d ' ')"
bash -c 'sleep 30; :' ask-main.sh & PARKPID=$!; echo "$PARKPID" > "$T/escpid"
for k in wait asking; do printf 'pid=%s\npane=term_b\n' "$PARKPID" > "$T/scratch/ask-main/msg_new.$k"; done
rm -f "$T"/ws/u1/.claude/briefs/u1-answer-*.md "$T/esc"; : > "$T/replies"; touch "$T/esc-works"
echo working > "$T/state"; rows "$COLD"; echo "$ASK_USE" >> "$LOG"
OUT=$(answer3 term_b "Ruling 17: cold and parked"); RC=$?; wait
PGONE=0; ! kill -0 "$PARKPID" 2>/dev/null || PGONE=1
check "a parked cold answer goes fresh (issue 478)" "0 1 1 1 1 0" \
  "$RC $(grep -c 'delivered to term_b (handed to a fresh session)' <<<"$OUT") $(wc -l < "$T/esc" | tr -d ' ') $(ls "$T"/ws/u1/.claude/briefs/u1-answer-*.md | wc -l | tr -d ' ') $(grep -c '^msg_new .*Ruling 17' "$T/replies") $PGONE"
kill "$PARKPID" 2>/dev/null; wait "$PARKPID" 2>/dev/null
# An Escape that does not end the wait (the pid lives): nothing is cleared or handed off, and the reply lands in the thread.
bash -c 'sleep 30; :' ask-main.sh & PARKPID=$!; echo "$PARKPID" > "$T/escpid"
for k in wait asking; do printf 'pid=%s\npane=term_b\n' "$PARKPID" > "$T/scratch/ask-main/msg_new.$k"; done
rm -f "$T"/ws/u1/.claude/briefs/u1-answer-*.md "$T/esc" "$T/esc-works"; : > "$T/replies"
echo working > "$T/state"; rows "$COLD"; echo "$ASK_USE" >> "$LOG"
OUT=$(ANSWER_WORKER_ESCAPE_WAIT=2 answer3 term_b "Ruling 18: escape missed"); RC=$?
check "a failed Escape keeps the reply (issue 478)" "0 1 0 1" \
  "$RC $(wc -l < "$T/esc" | tr -d ' ') $(ls "$T"/ws/u1/.claude/briefs/u1-answer-*.md 2>/dev/null | wc -l | tr -d ' ') $(grep -c '^msg_new .*Ruling 18' "$T/replies")"
kill "$PARKPID" 2>/dev/null; wait "$PARKPID" 2>/dev/null
cp "$T/log.bak" "$LOG"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
