#!/usr/bin/env bash
# board.sh is the one call main makes after every wake. It listed a unit's
# round files only as brief names with times, so a unit whose newest pass ended
# NO-GO read like one waiting to merge (#91). What this pins: the newest round by
# number (r10 after r9, whatever the file times) is shown with its kind, its
# verdict and its finding counts.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
mkdir -p "$T/bin" "$T/home"; printf '#!/bin/sh\nexit 1\n' > "$T/bin/orca-ide"; chmod +x "$T/bin/orca-ide"
git init -q -b main "$T/proj" && git -C "$T/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$T/proj" worktree add -q "$T/ws/u1" -b u1; B=$T/ws/u1/.claude/briefs; mkdir -p "$B"
board() { (cd "$T/proj" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/proj" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_AGENTS= COMMANDECK_DRIVERS= bash "$REAL/scripts/board.sh" u1 2>&1 | grep '^      pass '); }
round() { printf '## Sol\nReviewed: x\nCodex thread: t\nPass: %s\n\n%s\n\nVERDICT: %s\n' "$2" "$3" "$4" > "$B/u1-r$1-reports.md"; }

round 9 adversarial '- [P3] nit -- a:1' GO
round 10 review $'- [P1] bad -- a:1\n- [P2] meh -- a:2\n- [P2] meh too -- a:3' NO-GO
touch -t 202601010000 "$B/u1-r10-reports.md"
check "a unit whose newest pass ended NO-GO shows it, with its findings" "      pass r10 review: VERDICT: NO-GO (P1 1, P2 2)" "$(board)"
round 11 final 'Clean.' GO
check "the next pass's GO replaces it" "      pass r11 final: VERDICT: GO" "$(board)"
# Sol r3: a planner runs in <unit>-plan before its unit has a worktree, and the seats list hid it.
mkdir -p "$T/scratch" "$T/ws/u2-plan"; printf 'handle=h7\ntask=task_7\nrole=plan-author\nunit=u2\nworktree=u2-plan\n' > "$T/scratch/seat-u2-plan-author.txt"
check "a planner in its planning worktree is listed under its unit" "  u2 plan-author h7 task_7" \
  "$(cd "$T/proj" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/proj" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_AGENTS= COMMANDECK_DRIVERS= bash "$REAL/scripts/board.sh" u2 2>&1 | grep '^  u2 plan-author')"
# Issue 233 put a seat's launch in the background: main reads where each seat of a unit is, one line per seat record.
printf 'handle=h8\ntask=task_8\nrole=builder\nunit=u3\nphase=launching\nphase=dispatched\nverdict=VERDICT: GO\n' > "$T/scratch/seat-u3-builder.txt"
printf 'handle=h9\nrole=plan-judge-sol\nunit=u3\n' > "$T/scratch/seat-u3-plan-judge-sol.txt"
printf 'handle=h6\nrole=builder\nunit=u3-x\n' > "$T/scratch/seat-u3-x-builder.txt"
check "--unit u3 --seats prints each of u3's seats (role, handle, phase, verdict), and no other unit's" \
  "$(printf '  builder h8 dispatched VERDICT: GO\n  plan-judge-sol h9 - -')" \
  "$(cd "$T/proj" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/proj" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" bash "$REAL/scripts/board.sh" --unit u3 --seats 2>&1)"
# Issue 223: board.sh printed every worktree whole, and thirty of them filled main's context. The default is cut at
# 3,000 bytes, each section still shown, with the whole board in a named file; --full prints the whole.
for i in $(seq -w 1 30); do
  git -C "$T/proj" worktree add -q "$T/ws/w$i" -b "w$i"; mkdir -p "$T/ws/w$i/.claude/briefs"
  echo brief > "$T/ws/w$i/.claude/briefs/w$i.md"; printf 'Pass: review\n\nVERDICT: GO\n' > "$T/ws/w$i/.claude/briefs/w$i-r1-reports.md"
done
bd() { (cd "$T/proj" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/proj" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_AGENTS= COMMANDECK_DRIVERS= bash "$REAL/scripts/board.sh" "$@" 2>&1); }
OUT=$(bd); WHOLE=$(sed -n 's/.*(whole board: \([^;]*\);.*/\1/p' <<<"$OUT")
check "thirty worktrees: under 3,000 bytes, every section header kept, the whole board in the named file" "yes 1 30" \
  "$([ "$(printf '%s' "$OUT" | wc -c)" -lt 3000 ] && echo yes) $(grep -c '^== loops and main-watch' <<<"$OUT") $(grep -c '^  w[0-9]* \[' "$WHOLE" 2>/dev/null)"
check "--full prints every worktree" 30 "$(bd --full | grep -c '^  w[0-9]* \[')"
# The host project's second-machine chain lines read files no plugin script writes; the plugin has no second machine.
check "no CHAIN HOST, OFFLOADED or PLACEMENT WAIT line" 0 "$(bd --full | grep -cE '^(CHAIN HOST|OFFLOADED|PLACEMENT WAIT)')"
# Issue 353: a stopped Builder seat whose worktree has a round file shows its newest report (verdict, kind, age), not
# the words of its pane. The stand-in Orca lists the Builder's pane as done.
mkdir -p "$T/bin2" "$T/scratch"
cat > "$T/bin2/orca-ide" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "terminal list") echo '{"result":{"terminals":[{"handle":"h5","tabId":"t","leafId":"l"}]}}' ;;
  "worktree ps") echo '{"result":{"worktrees":[{"agents":[{"paneKey":"t:l","state":"done"}]}]}}' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/bin2/orca-ide"
printf 'handle=h5\ntask=task_5\nrole=builder\nunit=u1\nlaunched=0\n' > "$T/scratch/seat-u1-builder.txt"
round 12 review '- [P3] nit -- a:1' GO; touch -d '2 hours ago' "$B/u1-r12-reports.md"
STOP=$(cd "$T/proj" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin2:$PATH" COMMANDECK_MAIN="$T/proj" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_AGENTS= COMMANDECK_DRIVERS= bash "$REAL/scripts/board.sh" --full 2>&1 | grep '^  u1 builder:')
check "a stopped Builder shows its newest report, verdict, kind and age" "1" \
  "$(grep -c '^  u1 builder: newest report u1-r12-reports.md: GO (review), 1[12][0-9] min ago$' <<<"$STOP")"

# #532: board.sh binds whoever calls it, and in the main checkout only a git-dir check stood between an Orca automation
# at the repo root and the run. Only the run's coordinator is main: it binds as before and records itself in
# main-pane.txt; a second pane binds nothing, rewrites nothing, and a fresh main whose old pane is closed (or a run with
# no coordinator) is told the run-use line instead, because only main's own explicit run-use proves a pane is main.
mkdir -p "$T/bin3"
cat > "$T/bin3/orca-ide" <<'EOF'
#!/bin/sh
D=${COMMANDECK_SCRATCH%/*}
echo "$*" >> "$D/orca3.log"
case "$1 $2" in
  "orchestration run-current") cat "$D/run-current" 2>/dev/null || echo '{}' ;;
  "orchestration run-list") cat "$D/run-list" 2>/dev/null || exit 1 ;;
  "terminal list") cat "$D/term-list" 2>/dev/null || exit 1 ;;
  "orchestration run-use") echo '{"ok":true}' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/bin3/orca-ide"
S3=$T/d3/scratch; mkdir -p "$S3"
mb() { rm -f "$T/d3/orca3.log" "$S3/main-pane.txt"; echo "$RUNFILE" > "$S3/current-run"
  (cd "$T/proj" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_RUN HOME="$T/home" PATH="$T/bin3:$PATH" COMMANDECK_MAIN="$T/proj" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$S3" COMMANDECK_AGENTS= COMMANDECK_DRIVERS= ORCA_TERMINAL_HANDLE=me BOARD_UNCUT=1 bash "$REAL/scripts/board.sh" 2>&1); }
runlist() { printf '{"result":{"runs":[{"id":"run_a","coordinator_handle":%s}]}}\n' "$1" > "$T/d3/run-list"; }
termlist() { printf '{"result":{"terminals":[%s]}}\n' "$1" > "$T/d3/term-list"; }
used() { grep -c '^orchestration run-use' "$T/d3/orca3.log" 2>/dev/null || true; }
RUNFILE=run_a; rm -f "$T/d3/run-current"
runlist '"me"'; termlist '{"handle":"me"}'; OUT=$(mb)
check "board.sh in the run's coordinator pane binds as before and writes main-pane.txt" "1:handle=me" \
  "$(grep -c '^BOUND this terminal to run_a' <<<"$OUT"):$(cat "$S3/main-pane.txt" 2>/dev/null)"
# Orca's current run moved to another run: a second pane must not pull the run file along with it.
printf '{"result":{"run":{"id":"run_b"}}}\n' > "$T/d3/run-current"
runlist '"other"'; termlist '{"handle":"other"},{"handle":"me"}'; OUT=$(mb)
check "board.sh in a second pane neither binds the run nor rewrites the run file" "0:run_a:no:1" \
  "$(used):$(cat "$S3/current-run"):$([ -e "$S3/main-pane.txt" ] && echo yes || echo no):$(grep -c "^not main: the run's coordinator is other" <<<"$OUT")"
rm -f "$T/d3/run-current"
runlist '"old"'; termlist '{"handle":"me"}'; OUT=$(mb)
check "a fresh main whose old coordinator pane is closed is told the run-use line and neither binds nor writes main-pane.txt" "0:no:1" \
  "$(used):$([ -e "$S3/main-pane.txt" ] && echo yes || echo no):$(grep -cF 'THIS TERMINAL IS NOT BOUND: run run_a has no live coordinator (old); if this pane is main: orca-ide orchestration run-use --id run_a' <<<"$OUT")"
runlist '""'; termlist '{"handle":"me"}'; OUT=$(mb)
check "a fresh main on a run with no coordinator is told the run-use line and neither binds nor writes main-pane.txt" "0:no:1" \
  "$(used):$([ -e "$S3/main-pane.txt" ] && echo yes || echo no):$(grep -cF 'THIS TERMINAL IS NOT BOUND: run run_a has no live coordinator (none); if this pane is main: orca-ide orchestration run-use --id run_a' <<<"$OUT")"
# The extra rule: an automation (or any pane) in the main folder never claims the run, even with the old pane gone and
# Orca's run-current empty -- the one case that used to bind it.
runlist '"old"'; rm -f "$T/d3/term-list"; OUT=$(mb)
check "with the terminal list failing, a second pane still binds nothing and names the coordinator" "0:no:1" \
  "$(used):$([ -e "$S3/main-pane.txt" ] && echo yes || echo no):$(grep -c "^not main: the run's coordinator is old" <<<"$OUT")"
rm -f "$T/d3/run-list"; OUT=$(mb)
check "with the run list failing, board.sh binds nothing and names the coordinator unknown" "0:no:1" \
  "$(used):$([ -e "$S3/main-pane.txt" ] && echo yes || echo no):$(grep -c "^not main: the run's coordinator is unknown" <<<"$OUT")"
# Issue 647: a reviewer that writes its findings as bold headings (`**F1 (P2):**`) is counted like the bracket form; a
# (P2) in the middle of a sentence is not a heading and is not counted.
round 30 review $'**F1 (P2):** meh -- a:1\n- **F2 (P1):** bad -- a:2\nA note on the (P2) above.' NO-GO
check "board counts bold P2 finding" "      pass r30 review: VERDICT: NO-GO (P1 1, P2 1)" "$(board)"
# Issue 658: a Builder that asked main and ended its turn reads `working` in Orca, so it was listed nowhere and its
# answer, left unread, held the unit with no line saying so. Working in Orca, an open question, a session log idle 5 min
# or more: it is listed under the stopped panes with its idle minutes and the question.
mkdir -p "$T/bin6" "$T/ws/u6/.claude/briefs"
cat > "$T/bin6/orca-ide" <<EOF
#!/bin/sh
case "\$1 \$2" in
  "terminal list") echo '{"result":{"terminals":[{"handle":"h6","tabId":"t6","leafId":"l6","worktreePath":"$T/ws/u6","agentIdentity":"claude"}]}}' ;;
  "worktree ps") echo '{"result":{"worktrees":[{"agents":[{"paneKey":"t6:l6","state":"working"}]}]}}' ;;
  "orchestration dispatch-show") echo '{"result":{"dispatch":null}}' ;;
  "orchestration inbox") cat "$T/inbox6" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/bin6/orca-ide"
printf 'handle=h6\ntask=task_6\nrole=builder\nunit=u6\nworktree=u6\nlaunched=%s\n' "$(($(date +%s) - 3600))" > "$T/scratch/seat-u6-builder.txt"
L6=$T/home/.claude/projects/$(printf '%s' "$T/ws/u6" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$L6"
iso6() { jq -nr --argjson s "$1" 'now - $s | floor | todate'; }
{ jq -cn --arg t "$(iso6 900)" '{type: "user", message: {role: "user", content: "build u6"}, timestamp: $t, sessionId: "s6", cwd: "'"$T/ws/u6"'"}'
  jq -cn --arg t "$(iso6 600)" '{type: "assistant", message: {role: "assistant", stop_reason: "end_turn", content: [{type: "text", text: "QUESTION: which store?"}]}, timestamp: $t, sessionId: "s6"}'
  jq -cn --arg t "$(iso6 600)" '{type: "system", subtype: "turn_duration", timestamp: $t, sessionId: "s6"}'; } > "$L6/s6.jsonl"
jq -cn --arg t "$(iso6 620)" '{result: {messages: [{id: "msg_q6", type: "question", thread_id: null, from_handle: "h6", subject: "which store?", created_at: $t}]}}' > "$T/inbox6"
b6() { (cd "$T/proj" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin6:$PATH" COMMANDECK_MAIN="$T/proj" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_AGENTS= COMMANDECK_DRIVERS= bash "$REAL/scripts/board.sh" --full u6 2>&1 | grep '^  u6 builder:'); }
check "issue 658: idle Builder on an open question is listed as stopped" 1 "$(b6 | grep -cE '^  u6 builder: idle 1[0-1]m on open question msg_q6$')"
jq -cn --arg t "$(iso6 620)" '{result: {messages: [{id: "msg_q6", type: "question", thread_id: null, from_handle: "h6", subject: "which store?", created_at: $t},
  {id: "msg_a6", type: "status", thread_id: "msg_q6", from_handle: "main", subject: "answer", created_at: $t}]}}' > "$T/inbox6"
check "issue 658: an answered question lists nothing" 0 "$(b6 | grep -c 'open question')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
