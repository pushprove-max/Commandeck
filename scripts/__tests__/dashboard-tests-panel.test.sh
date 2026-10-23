#!/usr/bin/env bash
# dashboard-tests-panel.test.sh -- the Tests card (issue 269): the test runs going now on this machine, from ps and
# lsof, with who started each and how long it has run; the finished ones with their passed and failed totals, from
# the Claude session logs; and a run past its time cap shown as stalled. ps and lsof answer the collector's own call
# from a file. The fixture is dashboard-built.test.sh's.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"
tests_q() { jq -c "first(.[]) | $1" "$T/out/run/project.json" 2>&1; }

REAL_PS=$(command -v ps) REAL_LSOF=$(command -v lsof)
printf '#!/bin/sh\ncase "$*" in "-axww -o pid=,ppid=,etime=,command=") cat "$PS_OUT" ;; *) exec %s "$@" ;; esac\n' "$REAL_PS" > "$BIN/ps"
printf '#!/bin/sh\ncase "$*" in "-a -d cwd -Fn -p "*) cat "$LSOF_OUT" ;; *) exec %s "$@" ;; esac\n' "$REAL_LSOF" > "$BIN/lsof"
chmod +x "$BIN/ps" "$BIN/lsof"
export PS_OUT=$T/ps.out LSOF_OUT=$T/lsof.out
# 501 a runner with its child 502 and grandchild 504 under a process that names no runner (one row); 600 in the main
# checkout; 700 a wrapper that only names a runner; 705 to 707 a shell's -c and -n and node's -e, which run no test file;
# 800 another project's; 900 a run past the cap of its one file.
cat > "$PS_OUT" <<'EOF'
  501     1    00:40 bash scripts/run-shell-tests.sh a.test.sh
  502   501    00:39 bash a.test.sh
  503   502    00:38 sleep 5
  504   503    00:37 bash b.test.sh
  600     1 01:02:03 node --test x.test.mjs
  700     1    05:00 zsh -c run-shell-tests.sh is-mentioned
  705     1    00:10 bash -c npm run test:unit
  706     1    00:10 bash -n x.test.sh
  707     1    00:10 node -e console.log('--test')
  800     1 3-01:00:00 npm run test:unit
  900     1    05:00 bash scripts/run-shell-tests.sh slow.test.sh
EOF
printf 'p501\nn%s\np502\nn%s\np600\nn%s\np800\nn/elsewhere/other\np900\nn%s\n' "$WS/u-verdicts" "$WS/u-verdicts" "$MAIN" "$WS/u-verdicts" > "$LSOF_OUT"

# u-verdicts' session log: one runner command at 40, 50 and 90 s, one that failed, calls that run no test, and a
# background run whose completion is a task notification (logged twice), its output in the output file.
TL_ROOT=$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$WS/u-verdicts")
tl() { jq -cn --arg ts "$(date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.000Z)" --arg cwd "${4:-$WS/u-verdicts}" --argjson c "$2" --arg ty "$3" '{type:$ty,timestamp:$ts,cwd:$cwd,message:{content:[$c]}}'; }
tl_use() { tl "$1" "$(jq -cn --arg id "$2" --arg cmd "$3" '{type:"tool_use",name:"Bash",id:$id,input:{command:$cmd}}')" assistant "${4:-}"; }
tl_res() { tl "$1" "$(jq -cn --arg id "$2" --arg o "$3" '{type:"tool_result",tool_use_id:$id,content:$o}')" user "${4:-}"; }
t0=$(( $(date +%s) - 900 )); CA='bash scripts/run-shell-tests.sh x.test.sh'; CB='npm run test:unit'
printf 'ℹ pass 2\nℹ fail 0\n1 passed, 1 failed, 0 parked\n' > "$T/bg1.output"
NOTE="<task-notification>
<task-id>bg1</task-id>
<tool-use-id>g1</tool-use-id>
<output-file>$T/bg1.output</output-file>
<status>completed</status>
<summary>Background command \"bg\" completed (exit code 1)</summary>
</task-notification>"
{ tl_use $t0 a1 "$CA"; tl_res $((t0 + 40)) a1 $'..\n1 passed, 0 failed, 0 parked'
  tl_use $((t0 + 100)) a2 "$CA"; tl_res $((t0 + 150)) a2 $'1 passed, 0 failed, 0 parked'
  tl_use $((t0 + 160)) a3 "$CA"; tl_res $((t0 + 250)) a3 $'1 passed, 0 failed, 0 parked'
  tl_use $((t0 + 300)) b1 "$CB"; tl_res $((t0 + 330)) b1 $'ℹ pass 4\nℹ fail 1'
  tl_use $((t0 + 460)) c1 "grep -rn run-shell-tests.sh docs"; tl_res $((t0 + 461)) c1 'docs/x.md'
  tl_use $((t0 + 470)) c2 "python3 - <<'EOF'
print('a.test.sh')
EOF"; tl_res $((t0 + 475)) c2 'a.test.sh'
  tl_use $((t0 + 480)) c3 "cd /x && GUARD_PART=7 bash hooks/__tests__/g.test.sh 2>&1"; tl_res $((t0 + 484)) c3 $'ok\n1 passed, 0 failed, 0 parked'
  tl_use $((t0 + 485)) c4 "bash hooks/__tests__/h.test.sh"; tl_res $((t0 + 486)) c4 $'FAIL x\n124 passed, 1 failed'
  tl_use $((t0 + 490)) m3 "bash w.test.sh | tail -1"; tl_res $((t0 + 491)) m3 'done'
  tl_use $((t0 + 500)) m5 "bash -n scripts/__tests__/dashboard.test.sh"; tl_res $((t0 + 501)) m5 ''
  tl_use $((t0 + 510)) m6 "node -e \"console.log('--test a.test.sh')\""; tl_res $((t0 + 511)) m6 '--test a.test.sh'
  tl_use $((t0 + 520)) m7 "bash -c 'echo x.test.sh'"; tl_res $((t0 + 521)) m7 'x.test.sh'
  tl_use $((t0 + 530)) m8 "npm test --help"; tl_res $((t0 + 531)) m8 'usage'
  tl $((t0 + 600)) "$(jq -cn '{type:"tool_use",name:"Bash",id:"g1",input:{command:"bash scripts/run-shell-tests.sh bg.test.sh",run_in_background:true}}')" assistant
  tl_res $((t0 + 601)) g1 'Command running in background with ID: bg1.'
  jq -cn --arg ts "$(date -u -d "@$((t0 + 660))" +%Y-%m-%dT%H:%M:%S.000Z)" --arg c "$NOTE" '{type:"queue-operation",operation:"enqueue",timestamp:$ts,content:$c}'
  jq -cn --arg ts "$(date -u -d "@$((t0 + 661))" +%Y-%m-%dT%H:%M:%S.000Z)" --arg c "$NOTE" '{type:"user",timestamp:$ts,message:{role:"user",content:$c}}'; } > "$TL_ROOT/s2.jsonl"
# Another project's session: its runs are not this project's, nor its three runs of $CB this project's usual time.
OTHER=$HOME/.claude/projects/-elsewhere-other; mkdir -p "$OTHER"
{ tl_use $t0 o1 "bash scripts/run-shell-tests.sh other.test.sh" /elsewhere/other; tl_res $((t0 + 10)) o1 '1 passed, 0 failed, 0 parked' /elsewhere/other
  for i in 1 2 3; do tl_use $((t0 + 20 * i)) "ob$i" "$CB" /elsewhere/other; tl_res $((t0 + 20 * i + 1)) "ob$i" $'ℹ pass 1\nℹ fail 0' /elsewhere/other; done; } > "$OTHER/s.jsonl"
dash

check "the sources of the card are named" '["fresh","fresh"]' "$(jq -c 'first(.[]) | [.sources["tests-ps"].status, .sources["tests-logs"].status]' "$T/out/run/project.json" 2>&1)"
check "the outermost runner of each process tree is a row; a wrapper that only names a runner, bash -c, bash -n, node -e and another project's run are not" '[501,600,900]' \
  "$(tests_q '.tests.running | map(.pid)')"
check "who started a run is the worktree unit or main; a Builder's is marked; elapsed is ps's etime in seconds, with days" '[["u-verdicts",true,40],["main",false,3723],["u-verdicts",true,300]]' \
  "$(tests_q '.tests.running | map([.who, .builder, .elapsedSec])')"
check "the full command is a join key only, never published" 'false' "$(tests_q '.tests.running | map(has("full")) | any')"
check "a run past the cap of its one file (120 s) with no result is stalled; a young one is not" '[false,false,true]' "$(tests_q '.tests.running | map(.stalled)')"
check "a running command no logged run matches has no usual time" '[null,null,null]' "$(tests_q '.tests.running | map(.usualSec)')"
dash
check "a finished run: the command and took, the result's time minus the call's, newest first" '[90,50,40]' \
  "$(tests_q '.tests.finished | map(select(.what == "'"$CA"'")) | map(.took)')"
check "its totals come from the runner's own summary line" 'true' \
  "$(tests_q '.tests.finished | map(select(.what == "'"$CA"'")) | all(.passed == 1 and .failed == 0 and .result == "passed")')"
check "a node summary with a failure is a failed run with its totals" '[4,1,"failed"]' \
  "$(tests_q '.tests.finished | map(select(.what == "'"$CB"'")) | .[0] | [.passed, .failed, .result]')"
check "a run is named by its simple command, without the cd, env prefix or redirect" 'true' \
  "$(tests_q '.tests.finished | any(.what == "bash hooks/__tests__/g.test.sh")')"
check "a shell test file's own summary line, with no parked count, gives its totals and a failure" '[124,1,"failed"]' \
  "$(tests_q '.tests.finished | map(select(.what == "bash hooks/__tests__/h.test.sh")) | .[0] | [.passed, .failed, .result]')"
check "a piped exit with no counts is unknown, never passed" '"unknown"' \
  "$(tests_q '.tests.finished | map(select(.what == "bash w.test.sh")) | .[0].result')"
check "a grep, a heredoc, bash -n, node -e, bash -c and npm test --help are no runs" '[]' \
  "$(tests_q '[.tests.finished[].what | select(test("grep|python3|-n |-e |-c |--help"))]')"
check "a background run is timed to its completion notification, once, and read from its output file (node's and the runner's summaries add up)" '[1,60,"failed",3,1]' \
  "$(tests_q '.tests.finished | map(select(.what == "bash scripts/run-shell-tests.sh bg.test.sh")) | [length, .[0].took, .[0].result, .[0].passed, .[0].failed]')"
check "another project's run is left out, and a finished run names who ran it" 'true' \
  "$(tests_q '.tests.finished | all(.who == "u-verdicts")')"
check "a command's usual time is the median of this project's 3 or more runs (40, 50, 90 s); fewer is null, however often another project ran it" '[50,null]' \
  "$(tests_q '.tests.finished | [(map(select(.what == "'"$CA"'")) | .[0].usual), (map(select(.what == "'"$CB"'")) | .[0].usual)]')"
check "a running command that a logged run contains gets that run's usual time, and the cap becomes 3 times it" '[50,150,false]' \
  "$(printf 'p11\nn%s\n' "$WS/u-verdicts" > "$LSOF_OUT"; printf '  11     1    00:10 bash scripts/run-shell-tests.sh x.test.sh\n' > "$PS_OUT"; dash; tests_q '.tests.running[0] | [.usualSec, .capSec, .stalled]')"
check "npm test and npm run test are both running runs, npm itself or node running npm" '[12,13,14]' \
  "$(printf 'p12\nn%s\np13\nn%s\np14\nn%s\n' "$MAIN" "$MAIN" "$MAIN" > "$LSOF_OUT"
     printf '  12     1    00:10 npm test\n  13     1    00:10 npm run test:unit\n  14     1    00:10 node /usr/local/bin/npm test\n' > "$PS_OUT"; dash; tests_q '.tests.running | map(.pid)')"
check "a lsof that prints nothing leaves the owners unknown: the runs are not measured, never an empty list" '[null,"not-measured"]' \
  "$(printf '  11     1    00:10 bash scripts/run-shell-tests.sh x.test.sh\n' > "$PS_OUT"; printf '#!/bin/sh\nexit 1\n' > "$BIN/lsof"; dash
     jq -c 'first(.[]) | [.tests.running, .sources["tests-ps"].status]' "$T/out/run/project.json" 2>&1)"
check "a process list that cannot be read is not measured either" '[null,"not-measured"]' \
  "$(printf '#!/bin/sh\nexit 1\n' > "$BIN/ps"; dash; jq -c 'first(.[]) | [.tests.running, .sources["tests-ps"].status]' "$T/out/run/project.json" 2>&1)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
