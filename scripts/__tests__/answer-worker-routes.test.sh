#!/usr/bin/env bash
# answer-worker-routes.test.sh -- split from answer-worker.test.sh (its 500-line cap): delivered only from a prompt row (issue 658),
# the send route and closed panes (issue 585), one unit name in two projects (issue 646), a pane list read once more
# (issue 663). The setup below is answer-worker.test.sh's.
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

# queued row), and a pane that ended its turn with the answer still unread gets it typed in once.
rm -f "$T/reads" "$T/deaf" "$T/two" "$T/inbox-down"; : > "$T/inbox"; : > "$T/typed"
qrow() { jq -cn --arg t "[$1] $2" '{type: "queue-operation", operation: "enqueue", content: $t, timestamp: "2026-10-15T10:06:00Z", sessionId: "s1"}' >> "$LOG"; }
echo working > "$T/state"
(sleep 1; qrow q658a "the queued answer") &
OUT=$(AACK=5 ANSWER_WORKER_TAG=q658a answer term_b "the queued answer"); RC=$?; wait
check "issue 658: queued-row tag is not delivered" "1:0:1" \
  "$RC:$(grep -c 'delivered to term_b' <<<"$OUT"):$(grep -c 'NOT acknowledged' <<<"$OUT")"
: > "$T/typed"; echo working > "$T/state"
(sleep 1; qrow q658b "typed after the turn"; sleep 2; echo idle > "$T/state") &
OUT=$(AACK=12 ANSWER_WORKER_TAG=q658b answer term_b "typed after the turn"); RC=$?; wait
check "issue 658: ended turn with unread inbox answer is typed once" "0:1:1" \
  "$RC:$(wc -l < "$T/typed" | tr -d ' '):$(grep -c 'typed into the pane once its turn ended' <<<"$OUT")"

# Issue 585 (CG3, DG7-DG9): an answer typed into a pane whose turn has ended can sit in its composer; `orchestration send`
# is the route the send trial proves starts a turn there. It is taken only for an agent whose send passed on this host
# (docs/orca-native-trial.json, here $T/rec.json); every other pane keeps the typed answer. Orca here: panes from
# $T/list4 (handle key worktree), agents from $T/ps4 (key kind state worktree); a send or a typed text lands as a user row
# in that worktree's log; a send to dispatch:ctx_c while $T/reopen exists lists the reopened pane term_new in u5.
B4=$T/bin4 HOSTK=$(uname -s); mkdir -p "$B4"
lg() { local p=$T/home/.claude/projects/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$p" "$1"; echo "$p/s.jsonl"; }
cat > "$B4/orca-ide" <<EOF
#!/usr/bin/env bash
row() { jq -cn --arg t "\$2" '{type: "user", message: {role: "user", content: \$t}, timestamp: "2026-10-15T10:05:00Z", sessionId: "s1"}' >> "$T/home/.claude/projects/\$(printf '%s' "\$1" | tr -c 'A-Za-z0-9' '-')/s.jsonl"; }
wt() { awk -v h="\$1" '\$1 == h { print \$3 }' "$T/list4"; }
case "\$1 \$2" in
  "terminal list") jq -Rn '{result: {terminals: [inputs | split(" ") | {handle: .[0], tabId: (.[1] | split(":")[0]), leafId: (.[1] | split(":")[1]), worktreePath: .[2]}]}}' < "$T/list4" ;;
  "worktree ps") jq -Rn '[inputs | split(" ")] | group_by(.[3]) | {result: {worktrees: map({path: .[0][3], agents: map({paneKey: .[0], agentType: .[1], state: .[2]})})}}' < "$T/ps4" ;;
  "terminal send") a=("\$@"); while [ \$# -gt 0 ]; do case \$1 in --text) t=\$2 ;; --terminal) h=\$2 ;; esac; shift; done
    echo "typed \${a[*]}" >> "$T/typed4"; row "\$(wt "\$h")" "\$t"; echo '{"ok":true}' ;;
  "orchestration send") echo "\$*" >> "$T/sends4"; while [ \$# -gt 0 ]; do case \$1 in --to) to=\$2 ;; --body) b=\$2 ;; esac; shift; done
    if [ "\$to" = dispatch:ctx_c ] && [ -e "$T/reopen" ]; then echo "term_new t5:l1 $T/ws/u5" >> "$T/list4"; echo "t5:l1 claude idle $T/ws/u5" >> "$T/ps4"; to=term_new; fi
    [ "\${to#dispatch:}" = "\$to" ] || to=\$(awk -v t="\${to#dispatch:ctx_}" '\$0 ~ "task=task_" t { print FILENAME }' "$T"/scratch/seat-*.txt | head -1 | xargs sed -n 's/^handle=//p')
    [ -z "\$(wt "\$to")" ] || row "\$(wt "\$to")" "\$b"; echo '{"ok":true}' ;;
  "orchestration reply") while [ \$# -gt 0 ]; do case \$1 in --body) b=\$2 ;; --id) i=\$2 ;; esac; shift; done; printf '%s %s\n' "\$i" "\$b" >> "$T/replies4"; echo '{"ok":true}' ;;
  "orchestration dispatch-show") while [ \$# -gt 0 ]; do case \$1 in --task) k=\$2 ;; esac; shift; done; jq -n --arg d "ctx_\${k#task_}" '{ok: true, result: {dispatch: {id: \$d}}}' ;;
  "orchestration inbox") echo '{"result":{"messages":[]}}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$B4/orca-ide"
answer4() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR COMMANDECK_FOREGROUND=1 HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" ANSWER_WORKER_WAIT=2 ANSWER_WORKER_ACK_WAIT=${AACK:-3} ONT_RECORD="$T/rec.json" PATH="$B4:$PATH" bash "$REAL/scripts/answer-worker.sh" "$@" 2>&1); }
rec4() { jq -n --arg h "$HOSTK" "$1" > "$T/rec.json"; }
fresh4() { : > "$T/typed4"; : > "$T/sends4"; : > "$T/replies4"; }
W4=$T/ws/u4; L4=$(lg "$W4"); echo '{"type":"user","message":{"role":"user","content":"build it"},"timestamp":"2026-10-15T10:00:00Z"}' > "$L4"
printf 'term_d t4:l1 %s\nterm_x t4:l2 %s\n' "$W4" "$W4" > "$T/list4"; printf 't4:l1 claude idle %s\n' "$W4" > "$T/ps4"
printf 'handle=term_d\ntask=task_d\nrole=judge\nunit=u4\nworktree=u4\ncmd=claude --model x\n' > "$T/scratch/seat-u4-judge.txt"

rec4 '{send: {claude: {($h): {result: "pass", form: "handle"}}}}'; fresh4
OUT=$(answer4 term_d "ruling A: ship it"); RC=$?
check "ended pane gets orchestration send" "0:1:0:1" \
  "$RC:$(grep -c -- '--to term_d .*--type dispatch' "$T/sends4"):$(wc -l < "$T/typed4" | tr -d ' '):$(grep -c 'delivered to term_d' <<<"$OUT")"
fresh4; OUT=$(answer4 --interrupt term_d "ruling B"); RC=$?
check "interrupt send still typed" "1:0:1" "$RC:$(wc -l < "$T/sends4" | tr -d ' '):$(grep -c 'not waiting in ask-main.sh' <<<"$OUT")"
rec4 '{send: {claude: {($h): {result: "pass", form: "dispatch"}}}}'; fresh4
OUT=$(answer4 term_d "ruling C"); RC=$?
check "follow-up uses the recorded form" "0:1" "$RC:$(grep -c -- '--to dispatch:ctx_d ' "$T/sends4")"
rec4 '{send: {claude: {($h): {result: "pass", form: "handle"}}}}'; fresh4
echo "t4:l2 codex idle $W4" >> "$T/ps4"
OUT=$(answer4 term_x "ruling D"); RC=$?
check "Codex pane with unproven send keeps typed answer" "0:1" "$(wc -l < "$T/sends4" | tr -d ' '):$(grep -c -- '--terminal term_x' "$T/typed4")"
fresh4; OUT=$(answer4 term_d "ruling E" u4-msg_q7); RC=$?
check "ended pane with open question gets follow-up and thread reply" "0:1:1:0" \
  "$RC:$(wc -l < "$T/sends4" | tr -d ' '):$(grep -c '^msg_q7 answered: answer-' "$T/replies4"):$(wc -l < "$T/typed4" | tr -d ' ')"
rec4 '{send: {codex: {"PC-host": {result: "pass", form: "handle"}}, claude: {($h): {result: "pass", form: "handle"}}}}'; fresh4
OUT=$(answer4 term_x "ruling F"); RC=$?
check "PC send pass leaves a Mac Codex pane typed" "0:1" "$(wc -l < "$T/sends4" | tr -d ' '):$(grep -c -- '--terminal term_x' "$T/typed4")"
# Closed panes (DG8): the record names the old handle; Orca no longer lists it; the task's dispatch reaches the worker.
W5=$T/ws/u5; L5=$(lg "$W5"); echo '{"type":"user","message":{"role":"user","content":"judge it"},"timestamp":"2026-10-15T10:00:00Z"}' > "$L5"
printf 'handle=term_old\ntask=task_c\nrole=judge\nunit=u5\nworktree=u5\ncmd=claude --model x\n' > "$T/scratch/seat-u5-judge.txt"
cp "$T/scratch/seat-u5-judge.txt" "$T/u5.before"
rec4 '{send: {claude: {($h): {result: "pass", form: "handle"}}}}'; fresh4; touch "$T/reopen"
OUT=$(answer4 term_old "ruling G"); RC=$?
check "closed pane without a closed-send pass keeps the refusal" "1:0:1:same" \
  "$RC:$(wc -l < "$T/sends4" | tr -d ' '):$(grep -c 'no agent pane term_old' <<<"$OUT"):$(cmp -s "$T/u5.before" "$T/scratch/seat-u5-judge.txt" && echo same || echo changed)"
rec4 '{send: {claude: {($h): {result: "pass", form: "handle", closed: {result: "pass"}}}}}'; fresh4
OUT=$(answer4 term_old "ruling H"); RC=$?
check "closed seat pane reopened by its dispatch gets the answer" "0:1:1:term_new:term_old:1" \
  "$RC:$(grep -c -- '--to dispatch:ctx_c ' "$T/sends4"):$(grep -c 'reopened as term_new' <<<"$OUT"):$(sed -n 's/^handle=//p' "$T/scratch/seat-u5-judge.txt"):$(sed -n 's/^prior_pane=//p' "$T/scratch/seat-u5-judge.txt"):$(grep -c 'ruling H' "$L5")"
rm -f "$T/reopen"
# DG8: a record of another repo's seat (seat-<repo>@<unit>-<role>.txt) holds a bare worktree name; the reopened pane is
# looked for in that repo's workspace ($HOME/orca/workspaces/<repo>), not this project's, or it is never found and the
# answer is refused after Orca took it. No COMMANDECK_WORKSPACES here: the workspace is not given.
W7=$T/home/orca/workspaces/repo2/u7; L7=$(lg "$W7"); echo '{"type":"user","message":{"role":"user","content":"judge"},"timestamp":"2026-10-15T10:00:00Z"}' > "$L7"
printf 'handle=term_r1\ntask=task_r\nrole=judge\nunit=u7\nworktree=u7\ncmd=claude --model x\n' > "$T/scratch/seat-repo2@u7-judge.txt"
mkdir -p "$T/bin5"; cat > "$T/bin5/orca-ide" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "orchestration send" ] && [[ " \$* " == *" --to dispatch:ctx_r "* ]]; then
  echo "\$*" >> "$T/sends4"; echo "term_r2 t7:l1 $W7" >> "$T/list4"; echo "t7:l1 claude idle $W7" >> "$T/ps4"
  while [ \$# -gt 0 ]; do case \$1 in --body) b=\$2 ;; esac; shift; done
  jq -cn --arg t "\$b" '{type: "user", message: {role: "user", content: \$t}, timestamp: "2026-10-15T10:05:00Z"}' >> "$L7"; echo '{"ok":true}'; exit
fi
exec "$B4/orca-ide" "\$@"
EOF
chmod +x "$T/bin5/orca-ide"; fresh4
OUT=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR -u COMMANDECK_WORKSPACES COMMANDECK_FOREGROUND=1 HOME="$T/home" COMMANDECK_MAIN="$T/p" \
  COMMANDECK_SCRATCH="$T/scratch" ANSWER_WORKER_WAIT=2 ANSWER_WORKER_ACK_WAIT=3 ONT_RECORD="$T/rec.json" PATH="$T/bin5:$B4:$PATH" \
  bash "$REAL/scripts/answer-worker.sh" term_r1 "ruling R" 2>&1); RC=$?
check "closed seat of another repo resolves its workspace by record name" "0:1:term_r2:1" \
  "$RC:$(grep -c 'reopened as term_r2' <<<"$OUT"):$(sed -n 's/^handle=//p' "$T/scratch/seat-repo2@u7-judge.txt"):$(grep -c 'ruling R' "$L7")"
# DG9: a pane parked in `orchestration ask` gets the full text by reply (it returns as that tool's result, no prompt row),
# so no follow-up is sent; once its turn ends with no prompt row holding the tag, the answer is typed in once.
fresh4; sed -i.bak '/t4:l1/d' "$T/ps4"; echo "t4:l1 claude working $W4" >> "$T/ps4"
jq -nc '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", id: "tu_ask", name: "Bash", input: {command: "orca-ide orchestration ask --question x"}}]}}' >> "$L4"
(sleep 1; jq -nc '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "tu_ask", content: "reply"}]}}' >> "$L4"
  sed -i.bak 's/^t4:l1 claude working/t4:l1 claude idle/' "$T/ps4") &
OUT=$(AACK=10 answer4 term_d "ruling I" u4-msg_q8); RC=$?; wait
DG9L="reply-only answer to an asking worker is typed once its turn ends, never when its waiting call returned the answer"
check "$DG9L" "0:0:1:1" \
  "$RC:$(wc -l < "$T/sends4" | tr -d ' '):$(grep -c '^msg_q8 \[answer-.*\] ruling I$' "$T/replies4"):$(wc -l < "$T/typed4" | tr -d ' ')"
# Pass 19 (duplicate-answer): the reply came back as the ask call's own tool result, tag and all. The worker read it, so
# typing it again once the turn ends repeats an instruction: it is delivered, never typed.
fresh4; sed -i.bak '/t4:l1/d' "$T/ps4"; echo "t4:l1 claude working $W4" >> "$T/ps4"
jq -nc '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", id: "tu_ask2", name: "Bash", input: {command: "bash scripts/ask-main.sh q body"}}]}}' >> "$L4"
(for _ in $(seq 50); do [ -s "$T/replies4" ] && break; sleep 0.1; done
  jq -nc --arg c "$(sed -n 's/^msg_q9 //p' "$T/replies4")" '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "tu_ask2", content: [{type: "text", text: $c}]}]}}' >> "$L4"
  sed -i.bak 's/^t4:l1 claude working/t4:l1 claude idle/' "$T/ps4") &
OUT=$(AACK=10 answer4 term_d "ruling J" u4-msg_q9); RC=$?; wait
check "$DG9L" "0:1:0:1" \
  "$RC:$(grep -c '^msg_q9 \[answer-.*\] ruling J$' "$T/replies4"):$(wc -l < "$T/typed4" | tr -d ' '):$(grep -c 'delivered to term_d' <<<"$OUT")"
# The rule itself, both providers: a tagged result counts only from a waiting call (ask-main.sh, orchestration ask or
# check); a result of another call, and Claude's queue row, do not.
DL=$T/dl.jsonl
dl() { (source <(sed -n '/^delivered() {$/,/^}$/p' "$REAL/scripts/answer-worker.sh"); LOG=$DL TAG=answer-p KIND=$1; delivered && echo 1 || echo 0); }
CU='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a1","name":"Bash","input":{"command":"%s"}}]}}\n{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a1","content":"[answer-p] yes"}]}}\n'
XU='{"type":"response_item","payload":{"type":"function_call","call_id":"c1","name":"shell","arguments":"{\\"command\\":[\\"bash\\",\\"-lc\\",\\"%s\\"]}"}}\n{"type":"response_item","payload":{"type":"function_call_output","call_id":"c1","output":"[answer-p] yes"}}\n'
G=; for c in 'bash scripts/ask-main.sh q d' 'orca-ide orchestration ask --question x' 'cat notes.txt'; do
  printf "$CU" "$c" > "$DL"; G+=$(dl claude); printf "$XU" "$c" > "$DL"; G+=$(dl codex); done
echo '{"type":"queue-operation","operation":"enqueue","content":"[answer-p] yes"}' > "$DL"; G+=$(dl claude)
check "$DG9L" "1111000" "$G"

# Issue 646: one unit name open in two Orca projects. This project's u9 has no live pane and another project's u9 has
# one: the answer is neither queued here, where no Builder may ever read it, nor typed into the other project's Builder.
# One line names both and nothing is sent. With a live pane in this project's u9, that pane takes the answer.
mkdir -p "$T/ws/u9" "$T/other/ws/u9" "$T/b646"
cat > "$T/b646/orca-ide" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$T/calls646"
case "\$1 \$2" in
  "terminal list") cat "$T/list646.json" ;;
  "worktree ps") jq -n '{result: {worktrees: [{path: "$T/ws/u9", agents: [{paneKey: "t9:l9", agentType: "claude", state: "idle"}]}]}}' ;;
  *) exec "$T/bin/orca-ide" "\$@" ;;
esac
EOF
chmod +x "$T/b646/orca-ide"
aw646() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR COMMANDECK_FOREGROUND=1 HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" PP_PANE_MAP_FRESH=1 ANSWER_WORKER_WAIT=2 ANSWER_WORKER_ACK_WAIT=3 PATH="$T/b646:$T/bin:$PATH" bash "$REAL/scripts/answer-worker.sh" "$@" 2>&1); }
jq -n --arg o "$T/other/ws/u9" '{result: {terminals: [{handle: "term_o", worktreePath: $o, agentIdentity: "claude"}]}}' > "$T/list646.json"
OUT=$(aw646 u9 "use the second option"); RC=$?
check "same unit in two projects refuses naming both" "1:1:0:0" \
  "$RC:$(grep -cF "unit u9 is open in two projects: $T/ws/u9 (no live pane) and $T/other/ws/u9; nothing sent or queued" <<<"$OUT"):$([ -e "$T/scratch/queue/unit-u9.jsonl" ] && echo 1 || echo 0):$(cat "$T/calls646" 2>/dev/null | grep -cE 'term_o|orchestration send|terminal send')"
: > "$T/calls646"; mkdir -p "$T/scratch/handles"; echo term_u9 > "$T/scratch/handles/unit-u9"
jq -n --arg o "$T/other/ws/u9" --arg w "$T/ws/u9" '{result: {terminals: [{handle: "term_o", worktreePath: $o, agentIdentity: "claude"},
  {handle: "term_u9", tabId: "t9", leafId: "l9", worktreePath: $w, agentIdentity: "claude"}]}}' > "$T/list646.json"
OUT=$(aw646 u9 "use the second option"); RC=$?
check "own project's pane wins over another project's" "0:1:0" \
  "$(grep -c 'open in two projects' <<<"$OUT"):$(grep -cE -- '(--terminal|--to) term_u9( |$)' "$T/calls646" | sed 's/^[1-9][0-9]*$/1/'):$(grep -cE -- '(--terminal|--to) term_o( |$)' "$T/calls646")"

# test: issue 663 R6: one unreadable pane list lost the answer for good; the two list reads are retried inside a 12 s
# budget, so a list Orca fails to give once still gets the answer sent.
mkdir -p "$T/bin4"
cat > "$T/bin4/orca-ide" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = "terminal list" ] && [ ! -e "$T/tl-once" ]; then touch "$T/tl-once"; exit 1; fi
exec "$T/bin/orca-ide" "\$@"
EOF
chmod +x "$T/bin4/orca-ide"; echo idle > "$T/state"; : > "$T/typed"; rm -f "$T/tl-once" "$T/deaf"
OUT=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR COMMANDECK_FOREGROUND=1 HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" ANSWER_WORKER_WAIT=2 ANSWER_WORKER_ACK_WAIT=3 ANSWER_WORKER_TAG=r663 PATH="$T/bin4:$PATH" \
  bash "$REAL/scripts/answer-worker.sh" term_b "after a list retry" 2>&1); RC=$?
check "issue 663: unread pane list is retried" "0:1:0" \
  "$RC:$([ -e "$T/tl-once" ] && echo 1 || echo 0):$(grep -c 'pane lists cannot be read' <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
