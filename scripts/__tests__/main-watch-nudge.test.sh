#!/usr/bin/env bash
# timeout: 240
# Issue 258: a Builder that ended its turn with no DONE line or verdict was posted to main at once, and main spent a
# turn on a Builder one typed line would have set going again. What this pins: such a Builder, read done or idle, is
# typed one STOPPED line and main hears nothing yet; still stopped one repost window later, main is posted with
# "Nudged"; at most two nudges per pane, so a third stop is posted at once; never a nudge while an open decision
# names the unit; and a pane that is gone is posted without one.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
# The decisions ledger is read through decision.sh; with no ledger nothing is held.
mkdir -p "$REPO/hooks/lib"; cp "$SOURCE/scripts/decision.sh" "$REPO/scripts/"; cp "$SOURCE/hooks/lib/project.sh" "$REPO/hooks/lib/"
tick 5000
nudges() { cat "$T/typed" 2>/dev/null | grep -c -- "--terminal $1 --text Signal STOPPED" || true; }
stopped() { posts "$1 builder stopped without reporting"; }

# One stop: nudged, main not posted; still stopped past the repost window: posted, saying it was nudged.
bseat wt-n1 term_wt-n1 task_wt-n1 9000; state term_wt-n1 working; tick 10000
state term_wt-n1 idle; tick 10060
[ "$(nudges term_wt-n1)" = 1 ] || fail "an idle Builder that stopped without reporting was not nudged once: $(cat "$T/typed" 2>/dev/null)"
[ "$(stopped wt-n1)" = 0 ] || fail "a Builder just nudged was posted to main"
tick 10120
[ "$(nudges term_wt-n1)$(stopped wt-n1)" = 10 ] || fail "a nudged Builder was nudged again or posted inside the repost window"
tick 10400
[ "$(nudges term_wt-n1)" = 1 ] || fail "a Builder still stopped was nudged a second time for the same stop"
grep -q 'wt-n1 builder stopped without reporting.*Nudged 5 min ago' "$T/sends" || fail "a Builder still stopped one window after its nudge was not posted with Nudged"

# A second stop after it worked again is nudged once more; the third posts at once, with no nudge.
for t in 11000 12000; do state term_wt-n1 working; tick $t; state term_wt-n1 "done"; tick $((t + 60)); done
[ "$(nudges term_wt-n1)" = 2 ] || fail "a pane's second stop was not nudged, or its third was"
[ "$(posts 'wt-n1 builder stopped without reporting')" -ge 2 ] || fail "a pane's third stop was not posted at once: $(grep wt-n1 "$T/sends")"

# An open decision naming the unit: the stop is the owner's to settle, so main is posted and the pane is not typed into.
mkdir -p "$REPO/.claude/metrics"
jq -nc '{id: "q-1999-01-01-n2", askedAt: "1999-01-01T00:00:00Z", question: "Keep the reply for wt-n2?", proposedDefault: "keep",
  source: "builder wt-n2", answeredAt: null, answer: null}' > "$REPO/.claude/metrics/decisions.jsonl"
bseat wt-n2 term_wt-n2 task_wt-n2 13000; state term_wt-n2 working; tick 14000; state term_wt-n2 "done"; tick 14060
[ "$(nudges term_wt-n2)$(stopped wt-n2)" = 01 ] || fail "a Builder whose unit has an open decision was nudged, or not posted"
rm -f "$REPO/.claude/metrics/decisions.jsonl"

# A pane that is gone has no one to type to: posted with no nudge.
bseat wt-n3 term_wt-n3 task_wt-n3 15000; state term_wt-n3 working; tick 16000
sed -i '/^term_wt-n3 /d' "$F/agents"; tick 16060; tick $((16060 + 1300))
[ "$(nudges term_wt-n3)" = 0 ] || fail "a gone pane was nudged"
[ "$(stopped wt-n3)" -ge 1 ] || fail "a gone Builder was not posted: $(grep wt-n3 "$T/sends")"

# Issue 320: a plan seat's own report or fresh plan commit is its finish; without either, a silent stop still alerts.
pseat() { mkdir -p "$T/ws/$1/.claude/plans"; git -C "$T/ws/$1" init -q
  printf 'handle=%s\ntask=%s\nrole=plan-author\nunit=%s\nworktree=%s\nlaunched=%s\nplanref=\n' "$2" "$3" "$1" "$1" "$4" > "$S/seat-$1-plan-author.txt"; echo "$3 running" >> "$F/tasks"
  # Its session log reads the turn ended, nothing running: only such a turn's report or commit is its finish.
  printf 'state=complete\noutstanding=\nasked=0\n' > "$F/state-$1"; }
said() { # <from> <created at> <subject> -- the seat's message to the run, already read by main
  jq -nc --arg f "$1" --argjson at "$2" --arg s "$3" '{from_handle: $f, to_handle: "run:run_test", type: "worker_done", subject: $s, body: "", read: 1, created_at: ($at | todate)}' >> "$F/said.jsonl"
  jq -sc '{ok: true, result: {messages: .}}' "$F/said.jsonl" > "$F/inbox"; }
pcommit() { echo "plan $2" > "$T/ws/$1/.claude/plans/$1.md"; git -C "$T/ws/$1" add -A
  GIT_COMMITTER_DATE="@$2 +0000" git -C "$T/ws/$1" -c user.name=t -c user.email=t@t commit -qm plan; }
pstopped() { posts "$1 plan-author stopped without reporting"; }
pfinished() { posts "seat plan-author on $1 finished"; }
pseat wt-p1 term_wt-p1 task_wt-p1 30000; state term_wt-p1 working; tick 31000; said term_wt-p1 31030 'Plan revised: section 3'
state term_wt-p1 "done"; tick 31060
[ "$(pstopped wt-p1)$(pfinished wt-p1)" = 00 ] || fail "a plan seat that sent 'Plan revised' to the run, no marker, was posted"
grep -qx handled "$S/main-watch/item-seat-term_wt-p1-task_wt-p1" || fail "a plan seat that reported its own finish was not handled"
pseat wt-p2 term_wt-p2 task_wt-p2 32000; state term_wt-p2 working; tick 32100; pcommit wt-p2 32200; state term_wt-p2 "done"; tick 32260
[ "$(pstopped wt-p2):$(pfinished wt-p2)" = 0:1 ] || fail "a plan seat whose plan commit landed after launch was not posted as finished, or was posted stopped"
# Finish, follow-up, silent stop: the report belongs to the first episode, not the second.
pseat wt-p3 term_wt-p3 task_wt-p3 33000; state term_wt-p3 working; tick 33060; said term_wt-p3 33100 'Plan written: wt-p3'
state term_wt-p3 "done"; tick 33120; state term_wt-p3 working; tick 33200; state term_wt-p3 "done"; tick 33260
[ "$(pstopped wt-p3)" = 1 ] || fail "a follow-up episode's silent stop was hidden by the first episode's report"
# A stale `working` snapshot over a fresh plan commit: one finish, no stall, nothing more inside the repost window.
pseat wt-p4 term_wt-p4 task_wt-p4 34000; state term_wt-p4 working; tick 34000; pcommit wt-p4 34100
for t in 35200 35260 35320 35380; do tick $t; done
[ "$(posts 'wt-p4 plan-author stalled'):$(pfinished wt-p4)" = 0:1 ] || fail "a stale working snapshot over a plan commit was not one finish post"
# No commit, message or marker: still stopped, and the post carries the pane's last words.
pseat wt-p6 term_wt-p6 task_wt-p6 36000; state term_wt-p6 working; tick 36060; echo 'I paused to ask about section 3.' > "$F/verdict-term_wt-p6"
state term_wt-p6 "done"; tick 36120
grep 'wt-p6 plan-author stopped without reporting' "$T/sends" | grep -q 'Last words: I paused to ask about section 3\.' \
  || fail "a plan seat with no commit, message or marker was not posted stopped with its last words"
pseat wt-p7 term_wt-p7 task_wt-p7 37000; state term_wt-p7 working; tick 37000; tick 38200
[ "$(posts 'wt-p7 plan-author stalled')" = 1 ] || fail "a working seat silent past STALL_S raised no stall post"
# A plan seat whose pane is gone (Orca lists it no more) after it sent 'Plan revised': its finish, not "stopped".
pseat wt-p8 term_wt-p8 task_wt-p8 38300; state term_wt-p8 working; tick 38360; said term_wt-p8 38380 'Plan revised: wt-p8'
sed -i '/^term_wt-p8 /d' "$F/agents"; tick 38420
[ "$(pstopped wt-p8)" = 0 ] || fail "a gone plan seat that reported its finish was posted stopped"
grep -qx handled "$S/main-watch/item-seat-term_wt-p8-task_wt-p8" || fail "a gone plan seat that reported its finish was not handled"
# Only a plan author's own message is its finish: a judge's unread 'Plan revised: judged' note is not its verdict, so
# its markerless stop still posts "stopped", and no PLAN-DONE is made up for it.
mkdir -p "$T/ws/wt-j2"; git -C "$T/ws/wt-j2" init -q
printf 'handle=term_wt-j2\ntask=task_wt-j2\nrole=plan-judge-sol\nunit=wt-j2\nworktree=wt-j2\nlaunched=40000\n' > "$S/seat-wt-j2-plan-judge-sol.txt"
echo "task_wt-j2 running" >> "$F/tasks"; state term_wt-j2 working; tick 40060
jq -nc '{from_handle: "term_wt-j2", to_handle: "run:run_test", type: "status", subject: "Plan revised: judged", body: "Judging the plan.", read: 0, created_at: (40080 | todate)}' >> "$F/said.jsonl"
jq -sc '{ok: true, result: {messages: .}}' "$F/said.jsonl" > "$F/inbox"
printf 'state=complete\noutstanding=\nasked=0\n' > "$F/state-wt-j2"; echo 'Judging the plan.' > "$F/verdict-term_wt-j2"; state term_wt-j2 "done"; tick 40140
[ "$(posts 'wt-j2 plan-judge-sol stopped without reporting'):$(posts 'seat plan-judge-sol on wt-j2 finished')" = 1:0 ] \
  || fail "a judge's unread 'Plan revised' note stood in for its verdict: $(grep wt-j2 "$T/sends")"
# Main's ruling 1: an ordinary clean finish of each seat type is posted as a finish, never as a stall or a stop.
pseat wt-c1 term_wt-c1 task_wt-c1 41000; state term_wt-c1 working; tick 41060; echo PLAN-DONE > "$F/verdict-term_wt-c1"; state term_wt-c1 "done"; tick 41120; tick 41180
[ "$(posts 'wt-c1 plan-author stalled'):$(pstopped wt-c1):$(pfinished wt-c1)" = 0:0:1 ] \
  || fail "a plan author's plain PLAN-DONE finish raised a stall or stop alert, or was not posted once: $(grep wt-c1 "$T/sends")"
bseat wt-c2 term_wt-c2 task_wt-c2 42000; state term_wt-c2 working; tick 42060; echo 'WT-C2-DONE' > "$F/verdict-term_wt-c2"; state term_wt-c2 "done"; tick 42120; tick 42180
[ "$(posts 'wt-c2 builder stalled'):$(stopped wt-c2):$(posts 'seat builder on wt-c2 finished')" = 0:0:1 ] \
  || fail "a Builder's plain DONE finish raised a stall or stop alert, or was not posted once: $(grep wt-c2 "$T/sends")"
# Issue 321: a seat pane's marker turn is silent in both Stop hooks because main-watch reports that finish: the hooks
# run on a judge seat's pane (no wait claims it, the run file is there, no driver owns the unit) and send nothing,
# and the next tick posts the finish to main exactly once.
git init -q "$T/jr" && git -C "$T/jr" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first && git -C "$T/jr" worktree add -q "$T/ws/wt-j1"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/systemctl"; chmod +x "$T/bin/systemctl"
printf 'handle=term_wt-j1\ntask=task_wt-j1\nrole=plan-judge-sol\nunit=wt-j1\nworktree=wt-j1\nlaunched=39000\n' > "$S/seat-wt-j1-plan-judge-sol.txt"
echo "task_wt-j1 running" >> "$F/tasks"; state term_wt-j1 working; tick 39060
jq -nc '{type: "assistant", uuid: "j1", message: {content: [{type: "text", text: "Judged.\nVERDICT: GO"}]}}' > "$T/j1.jsonl"
hook() { (cd "$T/ws/wt-j1" && env -u CLAUDE_PROJECT_DIR ORCA_TERMINAL_HANDLE=term_wt-j1 ORCA_WORKTREE_ID="id::$T/ws/wt-j1" HOME="$T/home" \
  COMMANDECK_MAIN="$REPO" COMMANDECK_SCRATCH="$S" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_HOOK_FIRE_LOG=/dev/null PATH="$T/bin:$PATH" "$@" >/dev/null 2>&1); }
jq -n --arg p "$T/j1.jsonl" '{transcript_path: $p, stop_hook_active: false, hook_event_name: "Stop"}' | hook bash "$SOURCE/hooks/claude-worker-notify.sh"
hook bash "$SOURCE/hooks/codex-notify.sh" '{"type":"agent-turn-complete","turn-id":"j1","last-assistant-message":"Judged.\nVERDICT: GO"}' </dev/null
[ "$(grep -c 'turn complete' "$T/sends")" = 0 ] || fail "a seat pane's marker turn was sent by a Stop hook"
echo 'VERDICT: GO' > "$F/verdict-term_wt-j1"; state term_wt-j1 "done"; tick 39120; tick 39180
[ "$(posts 'seat plan-judge-sol on wt-j1 finished'):$(posts 'wt-j1 plan-judge-sol stalled'):$(posts 'wt-j1 plan-judge-sol stopped')" = 1:0:0 ] \
  || fail "the judge's finish the hooks left to main-watch was not posted to main exactly once, or raised a stall or stop alert"
# Commit-only completion across the wait, the watcher and collect (real times: the wait's claim is read against
# the clock): the wait releases on the commit and records PLAN-DONE, the watcher's markerless read is that wait's,
# and collect's report is the one notification.
cp "$SOURCE/scripts/seat.sh" "$SOURCE/scripts/run-bound.sh" "$REPO/scripts/"
R=$(date +%s); pseat wt-p5 term_wt-p5 task_wt-p5 $((R - 200)); state term_wt-p5 working; tick $((R - 100)); pcommit wt-p5 $((R - 50))
printf '1\nseen %s PLAN-DONE\n' "$R" > "$S/waiting-term_wt-p5"; echo marker=PLAN-DONE >> "$S/seat-wt-p5-plan-author.txt"
state term_wt-p5 "done"; tick $((R + 1))
(cd "$REPO" && env -u COMMANDECK_FOREGROUND -u COMMANDECK_DRIVER CLAUDECODE=1 PATH="$T/bin:$PATH" HOME="$T/home" COMMANDECK_SCRATCH="$S" \
  COMMANDECK_WORKSPACES="$T/ws" bash scripts/seat.sh collect plan-author wt-p5 >"$T/collect" 2>&1) || fail "collect of the committed plan failed: $(cat "$T/collect")"
[ "$(grep -c wt-p5 "$T/sends")" = 1 ] || fail "commit-only completion was not one notification across wait, watcher and collect"

echo "PASS main-watch-nudge.test.sh"
