#!/usr/bin/env bash
# main-watch-dead-seat.test.sh -- issue 590: a seat whose pane exited before its verdict went unnoticed. main-watch
# reads Orca's daemon log: a non-Builder seat whose pane is gone, whose latest exit row (by its exact pty id, since its
# launch) is not an operator close, and whose current episode has no finish gets one item naming the seat and its unit.
set -uo pipefail
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
export COMMANDECK_ORCA_LOG=$T/daemon.log
: > "$COMMANDECK_ORCA_LOG"
# dseat <unit> <role> <handle> <task> <pty> [record lines] -- a seat launched at 500 whose pane Orca no longer lists.
dseat() {
  mkdir -p "$T/ws/$1"
  printf 'handle=%s\ntask=%s\nrole=%s\nunit=%s\nworktree=%s\nlaunched=500\n%s%s' "$3" "$4" "$2" "$1" "$1" "${5:+pty=$5$'\n'}" "${6:-}" > "$S/seat-$1-$2.txt"
  echo "$4 running" >> "$F/tasks"
}
# xrow <pty> <epoch> <cause> [log] -- one session-exited row as Orca's daemon writes it.
xrow() { jq -nc --arg s "$1" --argjson t "$2" --arg c "$3" '{src: "daemon", ts: ($t | todate), pid: 1, event: "session-exited", sessionId: $s, code: 0, cause: $c}' >> "${4:-$COMMANDECK_ORCA_LOG}"; }
dead() { grep -o -- "seat $2 on $1 exited before its verdict" "$T/sends" | wc -l | tr -d ' '; }
J=plan-judge-sol
dseat u-dead $J term_a task_a pa;               xrow pa 600 unknown
dseat u-verdict $J term_b task_b pb $'verdict=VERDICT: GO\n'; xrow pb 600 unknown
dseat u-op $J term_c task_c pc;                 xrow pc 600 operator_close
dseat u-two $J term_d1 task_d1 pd1;             xrow pd1 600 unknown
dseat u-two plan-judge-astra term_d2 task_d2 pd2
dseat u-nopty $J term_e task_e "";              xrow '' 600 unknown
# Revised after its verdict: the revised prompt landed (--state names its session) and its new turn has no finish.
dseat u-revised $J term_f task_f2 pf $'verdict=VERDICT: GO\nrevised=task_f2\n'; xrow pf 600 unknown; echo session=s1 > "$F/state-u-revised"
# Its session log holds a verdict that collect never read.
dseat u-log $J term_g task_g pg;                xrow pg 600 unknown; echo 'VERDICT: GO' > "$F/verdict-term_g"
# main-watch settled its last turn as silent: no finish.
dseat u-silent $J term_h task_h ph;             xrow ph 600 unknown; mkdir -p "$S/main-watch"; echo silent > "$S/main-watch/kind-seat-term_h-task_h"
dseat u-fin $J term_i task_i pi;                xrow pi 600 unknown; echo finished > "$S/main-watch/kind-seat-term_i-task_i"
dseat u-unkop $J term_j task_j pj;              xrow pj 600 unknown; xrow pj 610 operator_close
# Revised before its new prompt landed: the session still ends on the old PLAN-DONE.
dseat u-old plan-author term_k task_k2 pk $'revised=task_k2\n'; xrow pk 600 unknown; echo 'U-OLD-PLAN-DONE' > "$F/verdict-term_k"
dseat u-failed $J term_l task_l pl;             xrow pl 600 unknown; awk '$1 == "task_l" { $2 = "failed" } 1' "$F/tasks" > "$F/tasks.new"; mv "$F/tasks.new" "$F/tasks"
echo 'not json' >> "$COMMANDECK_ORCA_LOG"

tick 1000
tick 2000
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected $2, got $3)"; fi; }
check "a seat whose pane exited with no verdict is reported once naming the seat and unit" "1:1" \
  "$(dead u-dead $J):$(grep -c "Seat $J (term_a) on u-dead" "$T/sends")"
check "a seat that exited after its verdict is not reported" 0 "$(dead u-verdict $J)"
check "an operator-closed seat pane is not reported" 0 "$(dead u-op $J)"
check "two seats in one worktree: only the seat whose pty exited is reported" "1:0" "$(dead u-two $J):$(dead u-two plan-judge-astra)"
check "a seat record with no pty value is not reported" 0 "$(dead u-nopty $J)"
check "a seat revised after its verdict whose pane then exits is reported" 1 "$(dead u-revised $J)"
check "a seat whose session log holds its verdict but was not collected is not reported when its pane exits" 0 "$(dead u-log $J)"
check "a seat whose last turn ended with no verdict and whose state reads silent is reported when its pane exits" 1 "$(dead u-silent $J)"
check "a seat main-watch settled as finished is not reported when its pane exits" 0 "$(dead u-fin $J)"
check "an unknown exit row followed by an operator_close row for one pty is not reported" 0 "$(dead u-unkop $J)"
check "a seat revised before its new prompt landed whose session still ends in the old PLAN-DONE is reported when its pane exits" 1 "$(dead u-old plan-author)"
check "a dead seat whose own task is failed in the task list still gets one item" 1 "$(dead u-failed $J)"

# The default log: on this Linux host (COMMANDECK_HOST_OS), under ~/.config/orca/logs.
mkdir -p "$T/home/.config/orca/logs"
dseat u-def $J term_m task_m pm; xrow pm 600 unknown "$T/home/.config/orca/logs/daemon.log"
(unset COMMANDECK_ORCA_LOG; tick 3000)
check "with COMMANDECK_ORCA_LOG unset the log under the host's default Orca folder is read" 1 "$(dead u-def $J)"
: > "$T/stderr"
COMMANDECK_ORCA_LOG=$T/no-such.log tick 4000
check "a missing Orca daemon log says so in one line" 1 "$(grep -c 'no Orca daemon log at' "$T/stderr")"

# test: issue 663: recover-stalls.sh never posts itself; its `ask:` line is one main-watch question (once, across ticks)
# and its `recovered:` line goes to the digest, not a question.
cat > "$T/rs-stub" <<EOF
#!/usr/bin/env bash
echo 'the driver died again; log tail here' > "$S/main-watch/recover-R4-ux.txt"
printf 'ask: R4-ux\trecovery failed once: driver of ux died again\t%s\n' "$S/main-watch/recover-R4-ux.txt"
echo 'recovered: dispatch uy: task task_y left ready'
EOF
export COMMANDECK_RECOVER_STALLS=$T/rs-stub
tick 5000
tick 6000
unset COMMANDECK_RECOVER_STALLS
RD=$(( $(cat "$S/main-watch/digest" "$T/sends" 2>/dev/null | grep -c 'recovered: dispatch uy: task task_y left ready') > 0 ))
check "recovery ask line reaches post once" "1:1:0" \
  "$(posts 'recovery failed once: driver of ux died again'):$RD:$(grep -c 'recovered: dispatch uy' "$T/stderr")"

# test: issue 663 R4b: dead_seats posted a dead seat at once and never relaunched it, so the unit waited on a person for
# a step one relaunch would carry. A seat that cannot be relaunched is still posted, and the post names why.
dseat u-nospec reviewer term_n task_n pn;       xrow pn 600 unknown
tick 7000
check "dead seat with no spec posts naming why" "1:1" \
  "$(dead u-nospec reviewer):$(grep -c 'Seat reviewer (term_n) on u-nospec: .*not relaunched: its seat record names no spec file' "$T/sends")"
# A plan seat whose driver left its args file is the driver's to relaunch (recover-stalls.sh R4b, after the driver's own
# `no verdict` STOP): a question before that relaunch is the bug. The item file is the mark R4b reads.
dseat u-wait plan-judge-sol term_w task_w pw;   xrow pw 600 unknown
printf '%s\n' "$T/a.md" "$T/j.md" "$T/b.md" drive-u-wait-100 > "$S/drive-u-wait.args"
tick 8000
check "dead plan seat whose driver can restart it is not posted on its first exit" "0:1" \
  "$(dead u-wait plan-judge-sol):$([ -e "$S/main-watch/item-dead-u-wait-plan-judge-sol-500" ] && echo 1 || echo 0)"
rm -f "$S/drive-u-wait.args"
# A non-plan seat with its spec: the real recover-stalls.sh relaunches it once (seat.sh stubbed: it logs the call and
# writes the new launch's record, as a real launch does); only the relaunched seat's own exit is a question, and that
# question starts no second relaunch (a loop of relaunches is the other half of the bug).
mkdir -p "$T/rstub"; touch "$T/spec-re.md"
cat > "$T/rstub/seat.sh" <<EOF
#!/usr/bin/env bash
echo "seat \$*" >> "$T/rcalls"
printf 'handle=term_r2\ntask=task_r2\nrole=%s\nunit=%s\nworktree=%s\nlaunched=700\nspec=%s\npty=pr2\n' "\$2" "\$3" "\$3" "\$4" > "$S/seat-\$3-\$2.txt"
echo "task_r2 running" >> "$F/tasks"
EOF
dseat u-re reviewer term_r task_r pr "spec=$T/spec-re.md"$'\n'; xrow pr 600 unknown
export COMMANDECK_RECOVER_STALLS=$SOURCE/scripts/recover-stalls.sh COMMANDECK_RECOVER_SCRIPTS=$T/rstub
tick 9000
tick 10000
check "dead non-plan seat is relaunched once before any question" "1:0" "$(grep -c "^seat launch reviewer u-re $T/spec-re.md$" "$T/rcalls"):$(dead u-re reviewer)"
xrow pr2 800 unknown
tick 11000
tick 12000
unset COMMANDECK_RECOVER_STALLS COMMANDECK_RECOVER_SCRIPTS
check "dead non-plan seat is relaunched once, then posted on its second exit" "1:1:1" \
  "$(grep -c '^seat launch' "$T/rcalls"):$(dead u-re reviewer):$(grep -c 'Seat reviewer (term_r2) on u-re: .*relaunched once and exited again' "$T/sends")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
