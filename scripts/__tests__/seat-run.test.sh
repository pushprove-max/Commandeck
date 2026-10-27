#!/usr/bin/env bash
# seat-run.test.sh -- seat.sh run, on the hand-written commandeck.json of fixtures/seat-setup.sh. What this pins:
# run is launch, wait and collect in one call, one line back and one wake for main, on GO, NO-GO and a dead pane;
# and a plan judge reads a read-only copy of the plan.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"
# The judge these cases run, launched in pu's planning worktree with its plan, by the setup lines of
# seat-plan-marker.test.sh.
PWT=$HOME/orca/workspaces/proj/pu; git -C "$PROJ" worktree add -q "$PWT" && echo pu > "$(git -C "$PWT" rev-parse --absolute-git-dir)/commandeck-plan-of"
# The plan passes plan-check.sh, which every launch of a judge sent to it runs first (issue 384).
GOODPLAN=$'## What can go wrong\n\n- a case: its test\n\n- Planned size: 1 files, 1 changed lines'
echo PLAN-DONE > "$T/screen"; mkdir -p "$PWT/.claude/plans"; printf '%s\n' "$GOODPLAN" > "$PWT/.claude/plans/pu.md"
PH=$(sha256sum < "$PWT/.claude/plans/pu.md" | cut -d' ' -f1)
printf 'Judge the plan.\nEnd on a line of its own.\n' > "$T/judge-spec.md"
srun launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1
JREC=$(ls "$HOME/.commandeck/scratch/"*/seat-pu-plan-judge-sol.txt)

# Issue 257: seat.sh run is launch, wait and collect in one call, one line back; issue 288: each outcome is exactly
# one wake for main (collect's verdict wake, or run's own line when there is none), never zero and never two.
SQ=$(ls -d "$HOME/.commandeck/scratch/"*/ | head -1)queue/main.jsonl
wakes() { cat "$T/wakes" "$SQ" 2>/dev/null | wc -l | tr -d ' '; }
rrun() { : > "$T/wakes"; rm -f "$SQ" "$T/pane-up"; (export COMMANDECK_FOREGROUND=1 COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 COMMANDECK_LOOP_POLL_SECONDS=0; seat_sh run "$@"); }
printf 'Judge the plan below, run one.\nPlan: .claude/plans/pu.md\nEnd on a verdict line.\n' > "$T/run-go.md"; echo 'VERDICT: GO' > "$T/screen"
OUT=$(rrun plan-judge-sol pu "$T/run-go.md" --effort high 2>/dev/null); RC=$?; RP=$(sed -n 's/.* report=//p' <<<"$OUT")
# The line is the whole of stdout: a reader of its first line gets the verdict, never the launch's or wait's chatter.
check "run on GO: exit 0, one line naming the verdict and a report that exists, nothing else on stdout, one wake" "0:1:1:yes:1" \
  "$RC:$(grep -cx "seat=plan-judge-sol unit=pu VERDICT: GO report=$RP" <<<"$OUT"):$(grep -c . <<<"$OUT"):$([ -s "$RP" ] && echo yes):$(wakes)"
check "run hands the plan seat's launch options to its launch, and main's rules name run" "1:1" \
  "$(grep -cx 'opts=--effort high' "$JREC"):$(grep -c '`seat.sh run` launches, waits and collects' "$REAL/templates/main-session.md")"
check "a plan judge's launch records the plan it reads and that plan's hash, and its collect when (issue 256)" "1:1:1" \
  "$(grep -cx "plan=$PWT/.claude/plans/pu.md" "$JREC"):$(grep -cx "planhash=$PH" "$JREC"):$(grep -cE '^collected=[0-9]+$' "$JREC")"
# Main's ruling 2: the judge is pointed at a read-only copy of the plan taken at launch, so an edit to the live plan
# while it reads (then restored before --from-plan) is never what the GO certifies.
JSPEC=$(sed -n 's/^Your task spec is the file \(.*\)\. Read all of it.*/\1/p' "$(sed -n 's/^prompt=//p' "$JREC" | tail -1)")
SNAP=$(sed -n 's/^Plan: \([^ ]*\) .*/\1/p' "$JSPEC" 2>/dev/null); echo 'plan B' > "$PWT/.claude/plans/pu.md"
check "a plan judge reads a read-only copy of the plan, the copy its record hashes, whatever the live plan becomes" "1:0:$PH:ro" \
  "$(grep -c '^Judge the plan below, run one\.$' "$JSPEC" 2>/dev/null):$(grep -c '^Plan: \.claude/plans/pu\.md$' "$JSPEC" 2>/dev/null):$(sha256sum < "$SNAP" 2>/dev/null | cut -d' ' -f1):$([ -f "$SNAP" ] && [ ! -w "$SNAP" ] && echo ro)"
# The judge prints its inputs with peek.sh from that same copy, so its bundle never reads the live plan (issue 413).
check "a plan judge's prompt points peek at its frozen copy" "1" \
  "$(grep -cF "peek.sh --unit pu --plan $SNAP" "$(sed -n 's/^prompt=//p' "$JREC" | tail -1)" 2>/dev/null)"
printf '%s\n' "$GOODPLAN" > "$PWT/.claude/plans/pu.md"
printf 'Judge the plan, run two.\nEnd on a verdict line.\n' > "$T/run-nogo.md"; printf -- '- [P1] a gap\nVERDICT: NO-GO\n' > "$T/screen"
OUT=$(rrun plan-judge-sol pu "$T/run-nogo.md" 2>/dev/null); RC=$?; RP=$(sed -n 's/.* report=//p' <<<"$OUT")
check "run on NO-GO: exit 1, one line, a report that exists, one wake" "1:1:yes:1" \
  "$RC:$(grep -cx "seat=plan-judge-sol unit=pu VERDICT: NO-GO report=$RP" <<<"$OUT"):$([ -s "$RP" ] && echo yes):$(wakes)"
printf 'Judge the plan, run three.\nEnd on a verdict line.\n' > "$T/run-dead.md"; printf 'Still judging.\nesc to interrupt\n' > "$T/screen"; touch "$T/die-on-wait"
OUT=$(rrun plan-judge-sol pu "$T/run-dead.md" 2>/dev/null); RC=$?
# The wake is a question, never a status: orca-wait.sh drops a status main's own handle sent, and a run from main has it.
check "a pane killed mid-run: exit 3, no verdict, never GO, and one wake saying so, of a type main's inbox keeps" "3:1:0:1:1:question" \
  "$RC:$(grep -c '^seat=plan-judge-sol unit=pu no verdict' <<<"$OUT"):$(grep -c 'GO' <<<"$OUT"):$(wakes):$(grep -c 'no verdict' "$SQ" 2>/dev/null):$(jq -r .type "$SQ" 2>/dev/null)"
rm -f "$T/die-on-wait"

# Host issue 3162: a seat run started by main survives main's pane closing. Main's foreground run goes on detached
# in its own session; the shell that started it then dies with its process group, as a closed pane's does, and the run
# still finishes and collects.
printf 'Judge the plan, detached.\nPlan: .claude/plans/pu.md\nEnd on a verdict line.\n' > "$T/run-det.md"; echo 'VERDICT: GO' > "$T/screen"
: > "$T/wakes"; rm -f "$SQ" "$T/pane-up"
cat > "$T/det.sh" <<EOF
cd "$PROJ" && env -u COMMANDECK_FOREGROUND -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR CLAUDECODE=1 COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 \
  COMMANDECK_LOOP_POLL_SECONDS=0 PATH="$BIN:\$PATH" HOME="$HOME" bash "$REAL/scripts/seat.sh" run plan-judge-sol pu "$T/run-det.md" > "$T/det.out" 2>&1
sleep 60
EOF
perl -e 'use POSIX; setpgid(0, 0); exec @ARGV' bash "$T/det.sh" & GRP=$!
for _ in $(seq 100); do grep -q 'running detached, pid' "$T/det.out" 2>/dev/null && break; sleep 0.2; done
DPID=$(sed -n 's/.*running detached, pid \([0-9]*\);.*/\1/p' "$T/det.out")
kill -TERM -- "-$GRP" 2>/dev/null; wait "$GRP" 2>/dev/null
[ -z "$DPID" ] || tail --pid="$DPID" -f /dev/null
DLOG=$(ls "$HOME/.commandeck/scratch/"*/run-*pu-plan-judge-sol.log 2>/dev/null | head -1)
check "a detached run started from a shell that is then killed (with its process group) still finishes and collects" "1:1" \
  "$(grep -c '^seat=plan-judge-sol unit=pu VERDICT: GO report=' "$DLOG" 2>/dev/null):$(grep -c "run-det.md" "$JREC")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
