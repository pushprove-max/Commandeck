#!/usr/bin/env bash
# Main's session restarts (a crash, a handoff, a lapsed login) and Orca gives it
# a new terminal handle. Senders that kept the old handle lost every message
# after that, and main sat idle with the owner's answers undelivered. Pinned:
# a message sent after the restart reaches the new pane, one sent while main is
# down is queued with a loud line and shown first when main comes back, and
# unread mail to an earlier handle is shown too; a main that never restarted
# sees nothing extra.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ws"
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
# Orca: the live panes are list.json; a send lands unread in its handle's inbox; a check reads and empties it.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "terminal list") cat "$T/list.json" ;;
  # need-from: a send naming no sender is refused, as Orca refuses one from a process with no terminal.
  "orchestration send") [ ! -e "$T/send-fail" ] || { cat "$T/send-fail"; exit 1; }
    [ ! -e "$T/need-from" ] || [[ " \$* " == *" --from "* ]] || { echo '{"ok":false,"error":{"message":"Could not determine the sender terminal"}}'; exit 1; }
    while [ \$# -gt 0 ]; do case \$1 in --to) to=\$2 ;; --from) fr=\$2 ;; --subject) s=\$2 ;; --type) ty=\$2 ;; --body) b=\$2 ;; esac; shift; done
    # send-fail-<handle>: Orca refuses a send to that pane; on-fail then runs, as a restart between the lookup and the retry.
    [ ! -e "$T/send-fail-\$to" ] || { [ ! -e "$T/on-fail" ] || bash "$T/on-fail"; cat "$T/send-fail-\$to"; exit 1; }
    jq -cn --arg s "\$s" --arg t "\$ty" --arg b "\$b" --arg to "\$to" --arg f "\${fr:-}" '{subject: \$s, type: \$t, body: \$b, to_handle: \$to, from_handle: \$f, read: 0, created_at: (now | todate)}' >> "$T/inbox-\$to"
    if [ -e "$T/msg-id" ]; then echo '{"ok":true,"result":{"message":{"id":"msg_t1"}}}'; else echo '{"ok":true}'; fi ;;
  "orchestration inbox") cat "$T"/inbox-* 2>/dev/null | jq -s '{ok: true, result: {messages: .}}' ;;
  "orchestration check") h=\$4; [ ! -e "$T/fail-\$h" ] || exit 1; [ ! -e "$T/hang" ] && [ ! -e "$T/hang-\$h" ] || sleep 10; jq -s '{ok: true, result: {messages: .}}' "$T/inbox-\$h" 2>/dev/null || echo '{"ok":true,"result":{"messages":[]}}'; rm -f "$T/inbox-\$h" ;;
  "terminal read") jq -Rn --arg h "\$4" '{ok: true, result: {terminal: {handle: \$h, tail: [inputs]}}}' "$T/screen-\$4" 2>/dev/null || exit 1 ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
main_is() { jq -n --arg p "$T/p" --arg h "${1:-}" '{result: {terminals: (if $h == "" then [] else [{handle: $h, worktreePath: $p, agentIdentity: "claude"}] end)}}' > "$T/list.json"; }
E=(env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch" PATH="$T/bin:$PATH")
send() { (cd "$T/p" && "${E[@]}" bash "$REAL/scripts/to-main.sh" status "$1" "body of $1" 2>&1); }
# start <handle> -- main's session starts in that pane: what its startup context says about missed mail.
start() { (cd "$T/p" && "${E[@]}" ORCA_TERMINAL_HANDLE="$1" bash "$REAL/hooks/agent-startup-context.sh" </dev/null 2>/dev/null) | sed -n '/reached no live pane/,/^$/p'; }

main_is term_1; start term_1 >/dev/null
check "a message reaches the live main" "to-main: sent to main (term_1)" "$(send one)"
rm -f "$T/inbox-term_1"   # main read it
main_is term_2; start term_2 >/dev/null
check "after a restart the next message reaches the new pane, not the old handle" "to-main: sent to main (term_2):no" \
  "$(send two):$([ -e "$T/inbox-term_1" ] && echo yes || echo no)"
rm -f "$T/inbox-term_2"
# A sender that still held the first handle wrote to it after the restart.
(PATH="$T/bin:$PATH" orca-ide orchestration send --to term_1 --type question --subject stale --body "to the old handle" >/dev/null)
main_is ''
OUT=$(send three); RC=$?
check "with main down the message is queued, loudly, and not reported sent" "3:1:0" "$RC:$(grep -c 'main is not running; message queued' <<<"$OUT"):$(grep -c 'sent to' <<<"$OUT")"
main_is term_3
OUT=$(start term_3)
check "main back: the queued message is shown first" 1 "$(grep -c '^- \[status\] three (queued .*): body of three$' <<<"$OUT")"
check "and the unread mail to its earlier handle" 1 "$(grep -c '^- \[question\] stale (to term_1): to the old handle$' <<<"$OUT")"
check "each once" "" "$(start term_3)"
check "a main that never restarted sees nothing extra" "" "$(main_is term_3; start term_3)"

# A Builder restarts the same way: main answers it by its unit, and an answer while it is down waits for it.
git -C "$T/p" worktree add -q "$T/ws/u1" 2>/dev/null
main_is ''
OUT=$(cd "$T/p" && "${E[@]}" bash "$REAL/scripts/answer-worker.sh" u1 "use the second option" 2>&1); RC=$?
check "an answer to a Builder that is down is queued, and not reported delivered" "1:1" "$RC:$(grep -c 'the Builder of u1 is not running; the answer is queued' <<<"$OUT")"
check "the Builder's next session shows it first" 1 \
  "$( (cd "$T/ws/u1" && "${E[@]}" COMMANDECK_BUILDER=1 ORCA_TERMINAL_HANDLE=term_b2 bash "$REAL/hooks/agent-startup-context.sh" </dev/null 2>/dev/null) | grep -c '^- \[status\] answer from main (queued .*): use the second option$')"


# A queued message is never lost to the cut or to a slow check: one too long to show is kept whole and named.
main_is ''
send "$(printf '%03100d' 0)" >/dev/null 2>&1
main_is term_4
OUT=$(start term_4)
check "a queued message too long to show is kept whole, and the output says where" "1:1" \
  "$(grep -c "1 queued message(s) did not fit here, kept whole in $T/scratch/queue/main.held.jsonl" <<<"$OUT"):$(jq -r .subject "$T/scratch/queue/main.held.jsonl" | grep -c '^0\{3100\}$')"
main_is ''; send five >/dev/null 2>&1; main_is term_5; touch "$T/hang"
OUT=$(cd "$T/p" && "${E[@]}" ORCA_TERMINAL_HANDLE=term_5 timeout 3 bash "$REAL/scripts/inbox-drain.sh" main 2>/dev/null)
check "a drain cut short by slow inbox checks has shown the queue first" 1 "$(grep -c '^- \[status\] five (queued' <<<"$OUT")"
rm -f "$T/hang"
mkdir -p "$T/emo/queue"; python3 -c 'import json; print(json.dumps({"at": "x", "type": "question", "subject": "s", "body": "\U0001F600" * 2400}, ensure_ascii=False))' > "$T/emo/queue/main.jsonl"
OUT=$(cd "$T/p" && "${E[@]}" COMMANDECK_SCRATCH="$T/emo" LC_ALL=en_US.UTF-8 bash "$REAL/scripts/inbox-drain.sh" main)
check "the cut counts bytes: a long message of emoji is kept whole, not shown cut" "1:1" \
  "$(grep -c 'queued message(s) did not fit here' <<<"$OUT"):$(( $(wc -c <<<"$OUT") < 3000 ))"
main_is ''; send nine >/dev/null 2>&1; send "$(printf '%03100d' 0)" >/dev/null 2>&1; chmod 400 "$T/scratch/queue/main.held.jsonl"; main_is term_9
OUT=$(start term_9)
check "a held file that cannot be written keeps the queue, and says so" "1:1" \
  "$(grep -c 'could not be moved' <<<"$OUT"):$(grep -c '^0\{3100\}' <(jq -r .subject "$T/scratch/queue/main.jsonl.taking" 2>/dev/null))"
chmod 600 "$T/scratch/queue/main.held.jsonl"
check "and shows it again, whole, at the next start" 1 "$(main_is term_10; start term_10 | grep -c 'did not fit here, kept whole')"
# A Builder may be named main: its queue is its own.
main_is ''
(cd "$T/p" && "${E[@]}" bash "$REAL/scripts/to-main.sh" --unit main status "for the builder" "stop this build" >/dev/null 2>&1)
check "a message for a Builder named main is not shown to main" "" "$(main_is term_6; start term_6)"
# The live pane, not the first row: a disconnected old pane and a reviewer pane in the same worktree are passed over.
jq -n --arg p "$T/p" '{result: {terminals: [{handle: "term_old", worktreePath: $p, agentIdentity: "claude", connected: false, orphaned: true},
  {handle: "term_rev", worktreePath: $p, agentIdentity: "claude", title: "Reviewer r1 — x"}, {handle: "term_7", worktreePath: $p, agentIdentity: "claude"}]}}' > "$T/list.json"
start term_7 >/dev/null
check "a send reaches the live pane, past a disconnected one and a reviewer" "to-main: sent to main (term_7)" "$(send seven)"
# A Builder's answer goes to the pane its last session start recorded, not to another seat in its worktree.
jq -n --arg w "$T/ws/u1" '{result: {terminals: [{handle: "term_plan", worktreePath: $w, agentIdentity: "claude", title: "Plan author —u1"},
  {handle: "term_b2", worktreePath: $w, agentIdentity: "claude", title: "Builder — u1"}]}}' > "$T/list.json"
check "a message to a Builder reaches the Builder, not its plan author" "to-main: sent to the Builder of u1 (term_b2)" \
  "$(cd "$T/p" && "${E[@]}" bash "$REAL/scripts/to-main.sh" --unit u1 status s b 2>&1)"
# A plan seat runs in the Builder's worktree with the Builder's settings: its start is not the Builder's.
printf 'path:%s\tPlan author —u1\tterm_plan\t1\n' "$T/ws/u1" >> "$T/scratch/pane-titles.tsv"
(cd "$T/ws/u1" && "${E[@]}" COMMANDECK_BUILDER=1 ORCA_TERMINAL_HANDLE=term_plan bash "$REAL/hooks/agent-startup-context.sh" </dev/null >/dev/null 2>&1)
jq -n --arg w "$T/ws/u1" '{result: {terminals: [{handle: "term_plan", worktreePath: $w, agentIdentity: "claude", title: "Plan author —u1"}]}}' > "$T/list.json"
(cd "$T/p" && "${E[@]}" bash "$REAL/scripts/to-main.sh" --unit u1 status s b >/dev/null 2>&1); RC=$?
check "a plan author's start does not make it the Builder: a message for the Builder is queued" 3 "$RC"
# A unit still in planning: the plan author is up and no Builder has started yet, so nothing names the Builder's pane.
git -C "$T/p" worktree add -q "$T/ws/u2" 2>/dev/null
jq -n --arg w "$T/ws/u2" '{result: {terminals: [{handle: "term_d2", worktreePath: $w, agentIdentity: "claude", title: "Plan author —u2"}]}}' > "$T/list.json"
(cd "$T/p" && "${E[@]}" bash "$REAL/scripts/to-main.sh" --unit u2 status s b >/dev/null 2>&1); RC=$?
check "before its Builder starts, a message for it is queued, never sent to another pane" 3 "$RC"
# A seat that starts before its launch record is written still knows its role: seat.sh exports it.
git -C "$T/p" worktree add -q "$T/ws/u3" 2>/dev/null
(cd "$T/ws/u3" && "${E[@]}" COMMANDECK_BUILDER=1 COMMANDECK_SEAT=plan-author ORCA_TERMINAL_HANDLE=term_d3 bash "$REAL/hooks/agent-startup-context.sh" </dev/null >/dev/null 2>&1)
jq -n --arg w "$T/ws/u3" '{result: {terminals: [{handle: "term_d3", worktreePath: $w, agentIdentity: "claude"}]}}' > "$T/list.json"
(cd "$T/p" && "${E[@]}" bash "$REAL/scripts/to-main.sh" --unit u3 status s b >/dev/null 2>&1); RC=$?
check "a plan seat with no launch record yet is not taken for the Builder" 3 "$RC"
# drain <handle> -- main's drain itself, as its session start runs it.
drain() { (cd "$T/p" && "${E[@]}" ORCA_TERMINAL_HANDLE="$1" bash "$REAL/scripts/inbox-drain.sh" main 2>/dev/null); }
# A handle whose check timed out is not dropped from the history: its mail is shown at a later start.
printf '%s\n' h1 h2 h3 h4 > "$T/scratch/handles/main"
(PATH="$T/bin:$PATH" orca-ide orchestration send --to h1 --type question --subject late --body "to h1" >/dev/null)
touch "$T/hang-h1"; drain h5 >/dev/null; rm -f "$T/hang-h1"
check "mail to a handle whose check timed out is shown at the next start" 1 "$(drain h6 | grep -c '^- \[question\] late (to h1): to h1$')"
# Handles whose checks always fail go to the back: a later handle still gets its check.
printf '%s\n' g1 g2 g3 g4 g5 > "$T/scratch/handles/main.unchecked"; touch "$T/fail-g1" "$T/fail-g2" "$T/fail-g3" "$T/fail-g4"
(PATH="$T/bin:$PATH" orca-ide orchestration send --to g5 --type question --subject behind --body "to g5" >/dev/null)
drain g6 >/dev/null
check "four handles that always fail do not keep a fifth from its check" 1 "$(drain g7 | grep -c '^- \[question\] behind (to g5): to g5$')"
# A queue that cannot be taken for showing stays queued, and the drain says so.
main_is ''; echo '{"at":"x","type":"status","subject":"old","body":"b"}' > "$T/scratch/queue/main.jsonl.taking"; chmod 400 "$T/scratch/queue/main.jsonl.taking"
send stuck >/dev/null 2>&1
OUT=$(drain h7)
check "a queue that cannot be moved for showing stays in the queue, and the drain says so" "1:1" \
  "$(grep -c 'body of stuck' "$T/scratch/queue/main.jsonl" 2>/dev/null):$(grep -c 'could not be taken' <<<"$OUT")"
check "and the next start shows it" 1 "$(drain h8 | grep -c '^- \[status\] stuck (queued')"
# A unit named like a handle is still a unit.
git -C "$T/p" worktree add -q "$T/ws/term_api" 2>/dev/null; main_is ''
OUT=$(cd "$T/p" && "${E[@]}" bash "$REAL/scripts/answer-worker.sh" term_api "use the second option" 2>&1)
check "a unit whose name starts with term_ gets its answer queued" 1 "$(grep -c 'the Builder of term_api is not running; the answer is queued' <<<"$OUT")"
# The owner's message the relay passes to main is owed a reply to the relay:
# marked until main sends one (cos-tell.sh --note) or the relay's watcher flags
# main's ended turn. A script's message from main's own checkout owes nothing.
git -C "$T/p" worktree add -q "$T/ws/Chief-of-Staff" 2>/dev/null; main_is term_11; start term_11 >/dev/null
# The mark is written under the lock the scripts that clear it hold from their read to their removal (cos-tell.test.sh
# races them): one written outside it lands between the two and is removed. The mark's clock is read inside the lock.
printf '#!/bin/sh\n[ "$1" != +%%s ] || ! flock -n %q true || echo unlocked >> %q\nexec %q "$@"\n' "$T/scratch/cos-owed.lock" "$T/date.log" "$(command -v date)" > "$T/bin/date"
chmod +x "$T/bin/date"; : > "$T/date.log"
(cd "$T/ws/Chief-of-Staff" && "${E[@]}" bash "$REAL/scripts/to-main.sh" question "is u1 merged?" "the owner asks" >/dev/null 2>&1)
rm "$T/bin/date"
check "a message the relay sends main is marked owed, with its subject, under the clearing scripts' lock" "is u1 merged?:0" \
  "$(cut -f2 "$T/scratch/cos-owed" 2>/dev/null):$(grep -c unlocked "$T/date.log")"
rm -f "$T/scratch/cos-owed"; send eleven >/dev/null 2>&1
check "a message sent from main's checkout is not" no "$([ -e "$T/scratch/cos-owed" ] && echo yes || echo no)"

# Main with its own question or permission prompt open reads nothing until the owner answers it in main's pane:
# the relay thought its sends were lost. The message is stored either way; the sender is told why no reply comes.
main_is term_12; start term_12 >/dev/null
printf 'Which release?\n> 1. 0.18.0\n  2. 0.17.1\nEnter to select, Esc to cancel\n' > "$T/screen-term_12"
OUT=$(send twelve); RC=$?
check "main showing an open question: sent, and the sender told main reads it only once that prompt is answered" "0:1" \
  "$RC:$(grep -c '^to-main: sent to main (term_12), but its pane shows an open question or permission prompt: it reads this only after that prompt is answered in its own pane$' <<<"$OUT")"
printf 'Done: u1 merged.\n> \n' > "$T/screen-term_12"
check "a plain screen gets the plain sent line" "to-main: sent to main (term_12)" "$(send thirteen)"
rm "$T/screen-term_12"
check "an unreadable screen gets the plain sent line" "to-main: sent to main (term_12)" "$(send fourteen)"
# A send Orca refused said only "failed": its reason is what the sender needs.
echo '{"ok":false,"error":{"message":"terminal term_12 is not accepting input"}}' > "$T/send-fail"
OUT=$(send fifteen); RC=$?
check "a failed send exits 1 and prints Orca's error" "1:1" "$RC:$(grep -c 'failed: terminal term_12 is not accepting input' <<<"$OUT")"
rm "$T/send-fail"

# Issue 318: only actionable mail wakes main, read off both forms that reach it. to-main.sh sends to main's terminal
# handle, not the run: a classifier reading the run alone would never wake main for a question sent this way. And a
# detached merge's exit notice is the only word of that result, so it must be a type that wakes main.
rm -f "$T"/inbox-*; main_is term_20; start term_20 >/dev/null
(cd "$T/p" && "${E[@]}" bash "$REAL/scripts/to-main.sh" question "which file?" "a Builder asks" >/dev/null 2>&1)
act() { (cd "$T/p" && "${E[@]}" CLAUDE_CONFIG_DIR="$T/cfg" bash -c '. "$0/scripts/paths.sh" && pp_inbox_actionable run_x "$1" | jq -r "map(.subject) | join(\",\")"' "$REAL" "$@"); }
check "a question sent through to-main.sh lands addressed to main's handle and pp_inbox_actionable counts it" "which file?:" \
  "$(act term_20):$(act '')"
rm -f "$T"/inbox-*
(cd "$T/p" && "${E[@]}" bash -c '. "$0/scripts/paths.sh" && pp_detach "$1/d/m.log" merge-u1 true >/dev/null' "$REAL" "$T")
for _ in $(seq 1 50); do [ -s "$T/inbox-term_20" ] && break; sleep 0.1; done
check "a detached merge's exit notice reaches main as a question" "question merge-u1: exit 0" \
  "$(jq -r '"\(.type) \(.subject)"' "$T/inbox-term_20" 2>/dev/null)"
# Issue 321: a service (the dashboard's) has no terminal, and Orca refused its every send for want of a sender.
rm -f "$T"/inbox-*; touch "$T/need-from"
check "to-main.sh question from a service env: sent with --from and accepted" "to-main: sent to main (term_20):term_20" \
  "$(cd "$T/p" && env -u ORCA_TERMINAL_HANDLE "${E[@]}" bash "$REAL/scripts/to-main.sh" question q1 b 2>&1):$(jq -r .from_handle "$T/inbox-term_20" 2>/dev/null)"
rm -f "$T/need-from"
# A question to main is waited on by its message id (ask-main.sh): the sent line carries it.
rm -f "$T"/inbox-*; touch "$T/msg-id"
check "a delivered send prints the message id on its sent line" "to-main: sent to main (term_20) id msg_t1" "$(send idq)"
rm -f "$T/msg-id" "$T"/inbox-*
# A pane that closed after the lookup: Orca refuses with terminal_not_found. The send is looked up once more.
GONE='{"ok":false,"error":{"code":"terminal_not_found","message":"Terminal term_gone has no live pane or durable Run/Dispatch mailbox."}}'
rm -rf "$T/scratch/queue"; main_is term_gone; start term_gone >/dev/null; echo "$GONE" > "$T/send-fail-term_gone"
OUT=$(send closed); RC=$?
check "send with no live main is queued, not lost: exit 3 and the queue holds the message once" "3:1" \
  "$RC:$(grep -c 'body of closed' "$T/scratch/queue/main.jsonl" 2>/dev/null)"
# The new main appeared between the lookup and the retry: the retry goes to it.
rm -rf "$T/scratch/queue" "$T"/inbox-*
printf '%s\n' "jq -n --arg p '$T/p' '{result: {terminals: [{handle: \"term_new\", worktreePath: \$p, agentIdentity: \"claude\"}]}}' > '$T/list.json'; echo term_new >> '$T/scratch/handles/main'" > "$T/on-fail"
OUT=$(send moved); RC=$?
check "a refusal for a closed pane retries on the new live main" "0:to-main: sent to main (term_new):1" \
  "$RC:$OUT:$(grep -c 'body of moved' "$T/inbox-term_new" 2>/dev/null)"
rm -f "$T/on-fail" "$T/send-fail-term_gone" "$T"/inbox-*
# Any other refusal is a failure, not a closed pane.
rm -rf "$T/scratch/queue"; main_is term_busy; start term_busy >/dev/null
echo '{"ok":false,"error":{"code":"invalid_argument","message":"bad subject"}}' > "$T/send-fail-term_busy"
send other >/dev/null; RC=$?
check "another refusal still exits 1 and queues nothing" "1:no" "$RC:$([ -e "$T/scratch/queue/main.jsonl" ] && echo yes || echo no)"
rm -f "$T/send-fail-term_busy"
# A recorded handle that is no longer live (a handoff whose new pane has not started its own drain) does not hide the live main.
echo term_dead > "$T/scratch/handles/main"; main_is term_live
check "a dead recorded handle falls back to the live pane in main's checkout" "to-main: sent to main (term_live)" "$(send fallback)"
# Main running in another checkout: the fallback looks in COMMANDECK_MAIN_PANE_DIR, as main-watch does.
mkdir -p "$T/other"; jq -n --arg p "$T/other" '{result: {terminals: [{handle: "term_elsewhere", worktreePath: $p, agentIdentity: "claude"}]}}' > "$T/list.json"
check "a dead recorded handle falls back to the live pane in COMMANDECK_MAIN_PANE_DIR" "to-main: sent to main (term_elsewhere)" \
  "$(cd "$T/p" && "${E[@]}" COMMANDECK_MAIN_PANE_DIR="$T/other" bash "$REAL/scripts/to-main.sh" status elsewhere "body" 2>&1)"

# Issue 331: each send leaves one line in the wake log with its result, so a message that never woke main can be found.
WLJ=$T/scratch/wake-log.jsonl
logged() { jq -rs 'map("\(.from):\(.result)") | join(",")' "$WLJ" 2>/dev/null; }
rm -f "$WLJ" "$T"/inbox-*; main_is term_w; start term_w >/dev/null; send logsent >/dev/null
check "a delivered send writes one sent line" "to-main:sent" "$(logged)"
rm -f "$WLJ"; printf 'Which release?\n> 1. 0.18.0\nEnter to select, Esc to cancel\n' > "$T/screen-term_w"; send logblocked >/dev/null
check "a pane with an open prompt writes sent_blocked" "to-main:sent_blocked" "$(logged)"
rm -f "$WLJ" "$T/screen-term_w"; echo '{"ok":false,"error":{"message":"terminal term_w is not accepting input"}}' > "$T/send-fail"; send logrefused >/dev/null
check "a refused send writes one refused line carrying Orca's reason" "to-main:refused:terminal term_w is not accepting input" \
  "$(logged):$(jq -rs 'last | .error' "$WLJ")"
rm -f "$WLJ" "$T/send-fail"; main_is ''; send logqueued >/dev/null
check "no live main writes one queued line" "to-main:queued" "$(logged)"
main_is term_w
# Issue 363: bare message text after the type is not forwarded to Orca as an unknown command: the helper takes exactly
# <type> <subject> <body>, refuses anything else with its usage line, and makes no Orca call.
rm -f "$T"/inbox-*
OUT=$(cd "$T/p" && "${E[@]}" bash "$REAL/scripts/to-main.sh" status "bare text with no body" 2>&1); RC=$?
check "bare text after the type is refused with the usage line and no Orca call" "2:1:0" \
  "$RC:$(grep -c '^usage: to-main.sh \[--unit <unit>\] <type> <subject> <body>$' <<<"$OUT"):$(ls "$T"/inbox-* 2>/dev/null | wc -l | tr -d ' ')"

# Issue 368: main runs in a checkout other than the project's (a pane in a different folder). The Builder's settings carry
# that folder as COMMANDECK_MAIN_PANE_DIR, which the pane lookup falls back to; without it the message queues, and says
# plainly that main does not see the queue.
OTHER=$T/other-main; mkdir -p "$OTHER"; rm -rf "$T"/inbox-* "$T/scratch/queue"
jq -n --arg p "$OTHER" '{result: {terminals: [{handle: "term_other", worktreePath: $p, agentIdentity: "claude"}]}}' > "$T/list.json"
OUT=$(cd "$T/p" && "${E[@]}" COMMANDECK_MAIN_PANE_DIR="$OTHER" bash "$REAL/scripts/to-main.sh" status "far" "body of far" 2>&1)
check "a Builder whose main runs in another checkout delivers to that pane, not to the queue" "1 0" \
  "$(grep -c 'body of far' "$T/inbox-term_other" 2>/dev/null) $(ls "$T"/scratch/queue/main.jsonl 2>/dev/null | wc -l | tr -d ' ')"
OUT=$(cd "$T/p" && "${E[@]}" bash "$REAL/scripts/to-main.sh" status "far2" "body of far2" 2>&1)
check "with no pane folder recorded, the message queues and says main does not see the queue until a main session starts in the project" "1 1" \
  "$(grep -c 'does not see this queue until a main session starts in' <<<"$OUT") $(ls "$T"/scratch/queue/main.jsonl 2>/dev/null | wc -l | tr -d ' ')"
check "a queued message to a Builder does not say it" 0 "$(cd "$T/p" && "${E[@]}" bash "$REAL/scripts/to-main.sh" --unit ux status s b 2>&1 | grep -c 'does not see this queue')"
main_is term_w

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
