#!/usr/bin/env bash
# recover-stalls.test.sh -- issue 663: a stalled unit waited for a person. Each stall is now recovered once per unit per
# condition (an answer never delivered to an idle pane, a ready task, a Builder pane that never got its task, a dead
# driver, a seat that died with no verdict, panes left after a merge), with one `recovered:` line; a second failure is
# one `ask:` line for main, never a loop. The scripts it calls are stubs that log their words.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
P=$T/p SC=$T/scratch WS=$T/ws ST=$T/scratch/main-watch STUB=$T/stub
mkdir -p "$T/bin" "$STUB" "$ST" "$SC/scratchpad" "$WS" "$T/home" "$P/.claude/metrics"
git init -q -b main "$P" && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
NOW=$(date +%s); L=$((NOW - 1000)); NOW_MS=$((NOW * 1000))
: > "$T/calls"
# Stubs: each logs `<name> <args>`, exits with rc-<name> if present. unit-drive start on a unit named in restart-<unit>
# rewrites the args file to a new service name, as a real start does.
for s in answer-worker dispatch-task seat unit-drive; do
  cat > "$STUB/$s.sh" <<EOF
#!/usr/bin/env bash
echo "$s \$*" >> "$T/calls"
[ ! -e "$T/rc-$s" ] || echo "$s stub refused: \$*" >&2
if [ "$s" = unit-drive ] && [ -e "$T/restart-\$2" ]; then sed -i.bak '4s/.*/drive-'"\$2"'-200/' "$SC/drive-\$2.args"; echo "drive-\$2-200" > "$SC/drive-\$2.owner"; echo "drive-\$2-200.service" >> "$T/active"; fi
exit \$(cat "$T/rc-$s" 2>/dev/null || echo 0)
EOF
done
printf '#!/usr/bin/env bash\necho "idle_seconds=$(cat %s/idle 2>/dev/null || echo 0)"\n' "$T" > "$STUB/read-verdict.sh"
cat > "$T/bin/systemctl" <<EOF
#!/usr/bin/env bash
n=\${@: -1}; grep -qx "\${n%.service}.service" "$T/active" 2>/dev/null && { echo active; exit 0; }; echo inactive; exit 3
EOF
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "worktree list") jq -n '{result: {worktrees: [{path: "$WS/um", displayName: "um", cliProvenance: {kind: "created-by-cli"}},
    {path: "$WS/uu", displayName: "uu", cliProvenance: {kind: "created-by-cli"}}, {path: "$WS/us", displayName: "us", cliProvenance: {kind: "created-by-cli"}}]}}' ;;
  "terminal close") echo "\$4" >> "$T/closed"; echo '{"ok":true,"result":{}}' ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
EOF
chmod +x "$STUB"/*.sh "$T/bin/"*; : > "$T/active"
TERMS='{"result":{"terminals":[]}}' TASKS='{"result":{"tasks":[]}}'
pane() { TERMS=$(jq -c --arg h "$1" --arg w "$WS/$2" --argjson at "${3:-$NOW_MS}" '.result.terminals += [{handle: $h, tabId: $h, leafId: "l", worktreePath: $w, lastOutputAt: $at}]' <<<"$TERMS"); }
task() { TASKS=$(jq -c --arg i "$1" --arg s "$2" '.result.tasks += [{id: $i, status: $s}]' <<<"$TASKS"); }
seat() { # <unit> <role> <handle> <task> [extra lines]
  printf 'handle=%s\ntask=%s\nrole=%s\nunit=%s\nworktree=%s\nlaunched=%s\nspec=%s\n%s' "$3" "$4" "$2" "$1" "$1" "$L" "$T/spec-$1.md" "${5:-}" > "$SC/seat-$1-$2.txt"; }
E=(env -u CLAUDE_PROJECT_DIR -u ORCA_TERMINAL_HANDLE HOME="$T/home" COMMANDECK_MAIN="$P" COMMANDECK_SCRATCH="$SC" COMMANDECK_WORKSPACES="$WS"
  COMMANDECK_HOST_OS=Linux COMMANDECK_RECOVER_SCRIPTS="$STUB" PATH="$T/bin:$PATH")
N=0
rs() { N=$((N + 1)); (cd "$P" && "${E[@]}" COMMANDECK_TERMINALS_JSON="$TERMS" COMMANDECK_TASKS_JSON="$TASKS" COMMANDECK_PS_JSON='{"result":{"worktrees":[]}}' \
  bash "$REAL/scripts/recover-stalls.sh" > "$T/out-$N" 2> "$T/err-$N"); }
twice() { rs; rs; }
calls() { grep -c -- "^$1" "$T/calls" || true; }
out() { cat "$T"/out-* 2>/dev/null; }

# R1 (close-done-panes.sh): a Builder pane of a unit merged after its launch closes; an unmerged unit's stays; a unit
# stopped while its Builder is still alive and idle stays (its STOP asks main to act in that pane).
mkdir -p "$T/home/.commandeck/builds"
PROJ=$(bash -c '. "$1/hooks/lib/project.sh" && pp_project "$2" && echo "$PP_PROJECT"' _ "$REAL" "$P")
jq -cn --arg m "$P" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{main: $m, unit: "um", how: "merged", at: $at}' > "$T/home/.commandeck/builds/$PROJ.jsonl"
seat um builder h_m task_m; seat uu builder h_u task_u; seat us builder h_s task_s; echo "STOP unit=us stage=watch: idle; next: x" > "$SC/unit-loop-us.done"
R1T='{"result":{"terminals":[{"handle":"h_m","tabId":"a","leafId":"l","worktreePath":"'$WS/um'","lastOutputAt":'$NOW_MS'},
  {"handle":"h_u","tabId":"b","leafId":"l","worktreePath":"'$WS/uu'","lastOutputAt":'$NOW_MS'},{"handle":"h_s","tabId":"c","leafId":"l","worktreePath":"'$WS/us'","lastOutputAt":'$NOW_MS'}]}}'
R1P='{"result":{"worktrees":[{"agents":[{"paneKey":"a:l","state":"idle","updatedAt":'$NOW_MS',"agentType":"claude"},
  {"paneKey":"b:l","state":"idle","updatedAt":'$NOW_MS',"agentType":"claude"},{"paneKey":"c:l","state":"idle","updatedAt":'$NOW_MS',"agentType":"claude"}]}]}}'
mkdir -p "$WS/um" "$WS/uu" "$WS/us"
(cd "$P" && "${E[@]}" COMMANDECK_DRIVERS=none COMMANDECK_TERMINALS_JSON="$R1T" COMMANDECK_PS_JSON="$R1P" bash "$REAL/scripts/close-done-panes.sh" --close >/dev/null 2>&1)
check "merged unit pane is closed" 1 "$(grep -cx h_m "$T/closed" 2>/dev/null || echo 0)"
check "unmerged unit pane is not closed" 0 "$(cat "$T/closed" 2>/dev/null | grep -cx h_u)"
check "stopped unit with live idle Builder is kept" 0 "$(cat "$T/closed" 2>/dev/null | grep -cx h_s)"
rm -f "$SC"/seat-*.txt "$SC"/unit-loop-*.done

# R2: an answer sent to a pane whose follower log has no `delivered` line, the pane idle 5 min: retyped once, the text
# read from the decision the follower log names.
pp_wake() { jq -cn --arg to "$1" --arg r "answer $2" '{at: "2026-11-05T00:00:00Z", from: "answer-worker", to: $to, reason: $r, result: "sent", error: ""}' >> "$SC/wake-log.jsonl"; }
echo '{"id":"d2","answer":"use option B"}' >> "$P/.claude/metrics/decisions.jsonl"
echo '{"id":"d2b","answer":"take the inbox answer"}' >> "$P/.claude/metrics/decisions.jsonl"
pane h2 u2; pp_wake h2 t2; printf 'decision=d2\nanswer-worker: NOT delivered: the answer was typed\n' > "$SC/answer-worker-t2.log"; echo 400 > "$T/idle"
twice
check "answered idle pane retyped once" "1:1" "$(calls 'answer-worker h2 use option B d2'):$(grep -c '^recovered: .* u2: ' <<<"$(out)")"
pane h2b u2b; pp_wake h2b t2b; printf 'decision=d2b\nanswer-worker: queued, not read yet: h2b is still mid-turn\n' > "$SC/answer-worker-t2b.log"
twice
check "answer sent as inbox reply with no turn is redelivered once" 1 "$(calls 'answer-worker h2b take the inbox answer d2b')"
# test: issue 663 R2: a follower log can end NOT delivered while the pane took the answer later (its tag is then in a
# prompt row of the pane's log, answer-worker.sh's delivered rule); retyping it gave the pane the same answer twice. A
# tag seen only in a tool result is no prompt, so that answer is still retyped once.
printf '#!/usr/bin/env bash\necho "idle_seconds=$(cat %s/idle 2>/dev/null || echo 0)"\necho "session=%s/session.jsonl"\necho provider=claude\n' "$T" "$T" > "$STUB/read-verdict.sh"
echo '{"id":"d2d","answer":"merge it"}' >> "$P/.claude/metrics/decisions.jsonl"
echo '{"id":"d2e","answer":"ship it"}' >> "$P/.claude/metrics/decisions.jsonl"
jq -cn '{type: "user", message: {role: "user", content: "merge it [answer t2d]"}}' > "$T/session.jsonl"
jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "x", content: "inbox: ship it t2e"}]}}' >> "$T/session.jsonl"
pane h2d u2d; pp_wake h2d t2d; printf 'decision=d2d\nanswer-worker: NOT delivered: the answer was typed\n' > "$SC/answer-worker-t2d.log"
pane h2e u2e; pp_wake h2e t2e; printf 'decision=d2e\nanswer-worker: NOT delivered: the answer was typed\n' > "$SC/answer-worker-t2e.log"
# Pass 19 (duplicate-answer): a tag in the result of the pane's own ask-main.sh call is an answer the pane read.
echo '{"id":"d2f","answer":"keep it"}' >> "$P/.claude/metrics/decisions.jsonl"
jq -cn '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", id: "ask2f", name: "Bash", input: {command: "bash scripts/ask-main.sh q b"}}]}}' >> "$T/session.jsonl"
jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "ask2f", content: "keep it [answer t2f]"}]}}' >> "$T/session.jsonl"
pane h2f u2f; pp_wake h2f t2f; printf 'decision=d2f\nanswer-worker: NOT delivered: the answer was typed\n' > "$SC/answer-worker-t2f.log"
twice
check "answer already in a prompt row is not retyped" 0 "$(calls 'answer-worker h2d ')"
check "answer whose tag is only in another call's tool result is retyped once, one its ask call returned never" 1:0 \
  "$(calls 'answer-worker h2e ship it d2e'):$(calls 'answer-worker h2f ')"

# R3: a Builder's task left ready while its pane is listed is dispatched once; a task Orca does not list is not.
seat u3 builder h3 task_3; pane h3 u3; task task_3 ready
seat u3n builder h3n task_3n; pane h3n u3n
rs; ONE=$(cat "$T/out-$N"); rs
check "ready task with live pane is dispatched once" 1 "$(calls "dispatch-task task_3 terminal:h3")"
check "unlisted task is not dispatched" 0 "$(calls "dispatch-task task_3n")"
check "recovery prints one line" 1 "$(grep -c '^recovered: dispatch u3: ' <<<"$ONE")"
seat uh builder hh task_h; pane hh uh; task task_h ready; printf 'R3 task_h' >> "$ST/recovered"; echo >> "$ST/recovered"
seat ur builder hr task_r; pane hr ur; task task_r ready; echo 'R3 task_r ready' >> "$ST/recovered"
rs
check "half row does not block a recovery" 1 "$(calls "dispatch-task task_h terminal:hh")"
check "recovery row blocks a second act" 0 "$(calls "dispatch-task task_r")"
# Pass 13 (recovery-failure-hidden): a dispatch that fails still spends the once-only attempt, so main must be asked,
# or the Builder stays stranded with nobody told.
seat uf builder hf task_f; pane hf uf; task task_f ready; echo 1 > "$T/rc-dispatch-task"
twice; rm -f "$T/rc-dispatch-task"
check "failed dispatch is tried once and main is asked once" "1:1" \
  "$(calls "dispatch-task task_f terminal:hf"):$(out | grep -c '^ask: R3-task_f	')"

# R3b: a Builder whose task is ready and whose pane Orca does not list is launched again once; a second missing pane is
# one question.
seat u3b builder h3b task_3b; task task_3b ready
twice
check "ready Builder task with no pane relaunches once" "1:1" "$(calls "seat launch builder u3b $T/spec-u3b.md"):$(grep -c '^ask: R3b-u3b	' <<<"$(out)")"
rm -f "$SC"/seat-*.txt

# R4: a dead driver (its service gone, no done file) is restarted once from its args file; the owner file may be gone.
args() { printf '%s\n' "$T/a-$1.md" "$T/j.md" "$T/b-$1.md" "drive-$1-100" > "$SC/drive-$1.args"; }
args ud; echo drive-ud-100 > "$SC/drive-ud.owner"; touch "$T/restart-ud"
# Pass 18 (completed-driver-restart): a unit merged after its driver started ended DONE, whatever its args file says;
# R4 never restarts it.
args um2; jq -cn --arg m "$P" '{main: $m, unit: "um2", how: "merged", at: "2026-11-05T00:00:00Z"}' >> "$T/home/.commandeck/builds/$PROJ.jsonl"
twice
check "dead driver is restarted once, and a merged unit's driver never" "1:0" "$(calls "unit-drive start ud $T/a-ud.md $T/j.md $T/b-ud.md"):$(calls "unit-drive start um2 ")"
rm -f "$SC/drive-um2.args"
args uc
twice
check "driver crashed past its owner file is restarted once" 1 "$(calls "unit-drive start uc ")"
# The restarted driver resumes: the question it had not sent yet is raised by its own question gate, so the restart is
# the only act and it happens once.
args uq; touch "$T/restart-uq"
twice
check "restarted driver re-raises unasked question once" "1:drive-uq-200" "$(calls "unit-drive start uq "):$(sed -n 4p "$SC/drive-uq.args")"
# Pass 17 (recovery-retry-loop): a refused start (R3b, R4, R4b) once wrote no row and was retried every tick with
# nobody asked. Each is now tried once, and main gets one question carrying the start's own error.
echo 2 > "$T/rc-unit-drive"; echo 1 > "$T/rc-seat"; args ux
seat uy builder hy task_y; task task_y ready; seat uz reviewer hz task_z; touch "$ST/item-dead-uz-reviewer-$L"
twice; rm -f "$T/rc-unit-drive" "$T/rc-seat" "$SC/seat-uy-builder.txt" "$SC/seat-uz-reviewer.txt"
check "a refused restart or relaunch is tried once and main is asked once, with its error" "1:1:1 1:1:1 1:1:1" \
  "$(calls "unit-drive start ux "):$(out | grep -c '^ask: R4-ux	'):$(grep -c 'unit-drive stub refused' "$ST/recover-R4-ux.txt" 2>/dev/null) $(calls "seat launch builder uy "):$(out | grep -c '^ask: R3b-uy	'):$(grep -c 'seat stub refused' "$ST/recover-R3b-uy.txt" 2>/dev/null) $(calls "seat launch reviewer uz "):$(out | grep -c '^ask: R4b-uz-reviewer-'):$(cat "$ST"/recover-R4b-uz-*.txt 2>/dev/null | grep -c 'seat stub refused')"
rm -f "$SC/drive-uc.args" "$SC/drive-ux.args" "$SC/drive-uq.args"
# The restarted ud dies too: one question with its log tail, no third start.
echo 'the driver log last words' > "$SC/scratchpad/ud-drive-200.log"; : > "$T/active"
twice
check "second driver death goes to the owner with the log" "1:1:1" \
  "$(calls "unit-drive start ud "):$(grep -c '^ask: R4-ud	' <<<"$(out)"):$(cat "$ST"/recover-R4-ud.txt 2>/dev/null | grep -c 'the driver log last words')"
rm -f "$SC/drive-ud.args"

# R4b: a seat main-watch found dead with no verdict is relaunched once; a plan seat goes through its driver's start,
# and only once that driver stopped.
seat uv reviewer hv task_v; touch "$ST/item-dead-uv-reviewer-$L"
seat um3 reviewer hm3 task_m3; touch "$ST/item-dead-um3-reviewer-$L"
jq -cn --arg m "$P" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{main: $m, unit: "um3", how: "merged", at: $at}' >> "$T/home/.commandeck/builds/$PROJ.jsonl"
twice
check "seat with no verdict is relaunched once, and a merged unit's seat never" "1:0" "$(calls "seat launch reviewer uv $T/spec-uv.md"):$(calls "seat launch reviewer um3 ")"
seat up plan-judge-sol hp task_p; touch "$ST/item-dead-up-plan-judge-sol-$L"; args up; echo "STOP unit=up stage=judge: no verdict; next: x" > "$SC/unit-loop-up.done"
twice
check "dead plan seat relaunches through the driver" "1:0" "$(calls "unit-drive start up $T/a-up.md"):$(calls "seat launch plan-judge-sol")"
seat uw plan-judge-sol hw task_w; touch "$ST/item-dead-uw-plan-judge-sol-$L"; args uw; echo drive-uw-100.service >> "$T/active"
twice
check "dead plan seat under a live driver waits for its stop" "0:0" "$(calls "unit-drive start uw"):$(calls "seat launch plan-judge-sol uw")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
