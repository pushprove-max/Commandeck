#!/usr/bin/env bash
# Self-test for no-poll-loops.sh.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/no-poll-loops.sh"
PASS=0 FAIL=0
TEST_REPO=$(mktemp -d)
trap 'rm -rf -- "$TEST_REPO"' EXIT
git -C "$TEST_REPO" init -q

run_hook() { (cd "$TEST_REPO" && printf '%s\n' "$1" | env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR "$HOOK" >/dev/null 2>&1); echo $?; }
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
json() { jq -cn --arg cmd "$1" '{tool_input:{command:$cmd}}'; }

check "for-loop with sleep blocks" 2 \
  "$(run_hook "$(json 'for i in 1 2 3; do sleep 30; gh pr view 1; done')")"
check "sleep-then-check chain blocks" 2 \
  "$(run_hook "$(json 'sleep 30; gh pr checks 1; sleep 30; gh pr checks 1')")"
check "sleep && check chain blocks" 2 \
  "$(run_hook "$(json 'sleep 10 && cat log.txt; sleep 10 && cat log.txt')")"
check "ordinary multiline polling remains blocked" 2 \
  "$(run_hook "$(json $'sleep 2 && date\nsleep 2 && date')")"
check "single delayed Bash && command passes" 0 \
  "$(run_hook "$(json 'sleep 1 && date')")"
check "single delayed Bash semicolon command passes" 0 \
  "$(run_hook "$(json 'sleep 1; date')")"
check "single delayed Bash || command passes" 0 \
  "$(run_hook "$(json 'sleep 1 || date')")"

bg() { jq -cn --arg cmd "$1" --argjson bg "$2" '{tool_name:"Bash",tool_input:{command:$cmd,run_in_background:$bg}}'; }
check "orca-ide check --wait in the background passes" 0 \
  "$(run_hook "$(bg 'orca-ide orchestration check --run run_1 --wait --timeout-ms 600000 --json' true)")"
# owner ruling 2026-09-10: a foreground wait blocks his typing for ten minutes.
check "orca-ide check --wait in the foreground blocks" 2 \
  "$(run_hook "$(bg 'orca-ide orchestration check --wait --types worker_done,question --timeout-ms 540000 --json' false)")"
check "orca-ide check --wait with no background field blocks" 2 \
  "$(run_hook "$(jq -cn '{tool_name:"Bash",tool_input:{command:"orca-ide orchestration check --wait --timeout-ms 60000 --json | jq ."}}')")"
check "a commit message quoting the wait passes in the foreground" 0 \
  "$(run_hook "$(jq -cn '{tool_name:"Bash",tool_input:{command:"git commit -q -F - <<EOF\ntooling: the wait\n\n`orca-ide orchestration check --wait` without the flag exits 2.\nEOF"}}')")"
check "orca-ide check without --wait passes in the foreground" 0 \
  "$(run_hook "$(bg 'orca-ide orchestration check --peek --json' false)")"
check "loop that ends with an orca-ide send passes" 0 \
  "$(run_hook "$(json 'while ! grep -q exit= log; do sleep 5; done; orca-ide orchestration send --run run_1 --to run:run_1 --type heartbeat --subject done')")"
check "bare sleep with no check passes" 0 \
  "$(run_hook "$(json 'sleep 4')")"
check "a quoted loop in a brief is data, passes" 0 \
  "$(run_hook "$(json "grep -n 'while true; do sleep 5; done' brief.md")")"
check "no sleep at all passes" 0 \
  "$(run_hook "$(json 'gh pr view 1 --json state')")"
check "empty command passes" 0 \
  "$(run_hook "$(jq -cn '{tool_input:{}}')")"

# The Monitor tool (owner ruling 2026-09-10): only the Orca wait or a watcher
# that ends with an Orca send may run as a Monitor in the main session.
mon() { jq -cn --arg cmd "$1" '{tool_name:"Monitor",tool_input:{command:$cmd}}'; }
check "Monitor file watcher without Orca blocks" 2 \
  "$(run_hook "$(mon 'until grep -q SHIP-EXIT= ship.log; do sleep 5; done; tail -3 ship.log')")"
check "Monitor tail without sleep and without Orca blocks" 2 \
  "$(run_hook "$(mon 'tail -f app.log | grep --line-buffered ERROR')")"
# The inbox is never waited on from a Monitor: a 30-minute Monitor loop ran 21
# times in 12 hours, 9 wake-ups were only the Monitor expiring (2026-09-18).
check "Monitor that is the raw Orca wait blocks" 2 \
  "$(run_hook "$(mon 'orca-ide orchestration check --wait --types worker_done,question --timeout-ms 540000 --json')")"
check "Monitor watcher ending with an Orca send passes" 0 \
  "$(run_hook "$(mon 'until grep -q SHIP-EXIT= ship.log; do sleep 5; done; orca-ide orchestration send --to term_x --type question --subject done')")"

# `orca-wait.sh` drains the inbox, so the hook must recognise it: a single run
# passes, a Monitor or a loop does not.
check "Monitor looping orca-wait.sh blocks" 2 \
  "$(run_hook "$(mon 'while true; do bash scripts/orca-wait.sh; done')")"
check "orca-wait.sh in the background passes" 0 \
  "$(run_hook "$(bg 'bash scripts/orca-wait.sh' true)")"
check "Monitor running orca-wait.sh once blocks" 2 \
  "$(run_hook "$(mon 'bash scripts/orca-wait.sh')")"
check "a background while-loop of orca-wait.sh blocks" 2 \
  "$(run_hook "$(bg 'while true; do bash scripts/orca-wait.sh; done' true)")"
check "a background loop of the raw check --wait blocks" 2 \
  "$(run_hook "$(bg 'while :; do orca-ide orchestration check --wait --json; done' true)")"
check "a loop that only SEARCHES for orca-wait.sh passes" 0 \
  "$(run_hook "$(bg 'for f in a.md b.md; do grep -n orca-wait.sh docs/$f; done' false)")"
check "a loop of a double-quoted wait path blocks" 2 \
  "$(run_hook "$(bg 'while true; do bash "scripts/orca-wait.sh"; done' true)")"
check "a loop of a single-quoted wait path blocks" 2 \
  "$(run_hook "$(bg "while true; do bash 'scripts/orca-wait.sh'; done" true)")"
# Pass-4 review: bash passes `"scripts/""orca-wait.sh"` as one word, and a `done`
# inside a word (`${done}`, `"{done}"`) is no keyword, so the loop has not ended.
check "a loop of a quote-joined wait path blocks" 2 \
  "$(run_hook "$(bg 'while true; do bash "scripts/""orca-wait.sh"; done' true)")"
check "a loop of a quoted \$DIR wait path blocks" 2 \
  "$(run_hook "$(bg 'while true; do bash "$DIR/orca-wait.sh"; done' true)")"
check "a loop whose body echoes \${done} before the wait blocks" 2 \
  "$(run_hook "$(bg 'while true; do echo ${done}; bash scripts/orca-wait.sh; done' true)")"
check "a sleep loop whose body echoes \"{done}\" blocks" 2 \
  "$(run_hook "$(json 'while true; do echo "{done}"; sleep 30; done')")"
check "a sleep loop whose body echoes \${done} blocks" 2 \
  "$(run_hook "$(json 'while true; do echo ${done}; sleep 30; done')")"
check "a sleep loop past an inner loop named done blocks" 2 \
  "$(run_hook "$(json 'while true; do for done in a; do :; done; sleep 30; done')")"
check "a wait loop past an inner loop named done blocks" 2 \
  "$(run_hook "$(bg 'while true; do for done in a; do :; done; bash scripts/orca-wait.sh; done' true)")"
check "a brace group still ends a command" 2 \
  "$(run_hook "$(json 'while true; do { sleep 30; }; done')")"
check "a search whose quoted pattern holds a wait loop passes" 0 \
  "$(run_hook "$(bg "rg -n 'while true; do bash scripts/orca-wait.sh' .claude/hooks" true)")"
check "a wait after an inner loop, inside an outer loop, blocks" 2 \
  "$(run_hook "$(bg 'while true; do for x in a; do echo "$x"; done; bash scripts/orca-wait.sh; done' true)")"
# Newlines end commands exactly as semicolons do, except inside quotes.
check "a multiline loop of the wait blocks" 2 \
  "$(run_hook "$(bg $'while true\ndo\n  bash scripts/orca-wait.sh\ndone' true)")"
check "a multiline wait after a finished multiline loop passes" 0 \
  "$(run_hook "$(bg $'for f in a b\ndo\n  echo $f\ndone\nbash scripts/orca-wait.sh' true)")"
check "a quoted multiline pattern naming a wait loop passes" 0 \
  "$(run_hook "$(bg $'rg -n \'while true\ndo bash scripts/orca-wait.sh\' .claude/hooks' true)")"
check "a heredoc body quoting a wait loop is data, passes" 0 \
  "$(run_hook "$(bg $'cat > notes.md <<\'EOF\'\nwhile true\ndo\n bash scripts/orca-wait.sh\ndone\nEOF' true)")"
check "a numeric heredoc delimiter is data too" 0 \
  "$(run_hook "$(bg $'cat <<\'123\'\nwhile true\ndo\n bash scripts/orca-wait.sh\ndone\n123' true)")"
check "an unquoted punctuated delimiter is data too" 0 \
  "$(run_hook "$(bg $'cat <<END.NOTES\nwhile true\ndo\n bash scripts/orca-wait.sh\ndone\nEND.NOTES' true)")"
check "a real loop after a punctuated heredoc still blocks" 2 \
  "$(run_hook "$(bg $'cat <<\'END-NOTES\'\nhi\nEND-NOTES\nwhile true\ndo\n bash scripts/orca-wait.sh\ndone' true)")"
check "a comment before the do does not hide the loop" 2 \
  "$(run_hook "$(bg $'while true # wait for updates\ndo\n bash scripts/orca-wait.sh\ndone' true)")"
check "a concatenated delimiter closes on the whole word" 0 \
  "$(run_hook "$(bg $'cat <<\'END\'-NOTES\nEND\nwhile true\ndo\n bash scripts/orca-wait.sh\ndone\nEND-NOTES' true)")"
check "a real loop after a concatenated-delimiter heredoc still blocks" 2 \
  "$(run_hook "$(bg $'cat <<\'END\'-NOTES\nhi\nEND-NOTES\nwhile true\ndo\n bash scripts/orca-wait.sh\ndone' true)")"
check "a real loop AFTER a heredoc still blocks" 2 \
  "$(run_hook "$(bg $'cat > notes.md <<EOF\nhello\nEOF\nwhile true\ndo\n bash scripts/orca-wait.sh\ndone' true)")"
check "a here-string does not hide the lines after it" 2 \
  "$(run_hook "$(bg $'grep x <<<EOF\nwhile true\ndo\n bash scripts/orca-wait.sh\ndone' true)")"
check "a single wait AFTER a finished loop passes" 0 \
  "$(run_hook "$(bg 'for f in a.md b.md; do cat "$f"; done; bash scripts/orca-wait.sh' true)")"
check "the single-shot background form with the run id passes" 0 \
  "$(run_hook "$(bg 'bash scripts/orca-wait.sh --run "$(tr -d '"'"'[:space:]'"'"' < ~/.config/orca/current-run)"' true)")"
check "the loop refusal names the foreground drain" 0 \
  "$( (cd "$TEST_REPO" && bg 'while true; do bash scripts/orca-wait.sh; done' true | "$HOOK" 2>&1 >/dev/null) | grep -q 'drain ONCE in the foreground' && echo 0 || echo 1)"
# orca-wait.sh is a drain that never blocks: the foreground is its home.
check "orca-wait.sh in the foreground passes" 0 \
  "$(run_hook "$(bg 'bash scripts/orca-wait.sh' false)")"
check "a doc line naming orca-wait.sh passes in the foreground" 0 \
  "$(run_hook "$(bg 'git commit -q -m the wait is scripts/orca-wait.sh' false)")"

# WRITING ABOUT THE WAIT IS NOT WAITING. This exact append -- a report
# section quoting the waiter command in a heredoc -- was blocked on 2026-09-20,
# and the text being written is indistinguishable from the command only if the
# hook matches the literal string instead of parsing the command.
check "an append documenting the wait passes in the foreground" 0 \
  "$(run_hook "$(bg $'cat >> report.md <<\'EOF\'\nThe inbox wait is one call:\n  bash scripts/orca-wait.sh\nEOF' false)")"
check "an append documenting a sleep loop passes" 0 \
  "$(run_hook "$(bg $'cat >> report.md <<\'EOF\'\nNever do this:\n  while true; do sleep 30; gh pr view 1; done\n  sleep 30; gh pr view 1; sleep 30; gh pr view 1;\nEOF' false)")"
# The body must not hide a real command that follows it, or the strip becomes
# the hole: everything after the delimiter is code again.
check "a foreground wait AFTER a documenting heredoc still blocks" 2 \
  "$(run_hook "$(bg $'cat >> report.md <<\'EOF\'\n  orca-ide orchestration check --wait --json\nEOF\norca-ide orchestration check --wait --json' false)")"

# A comment is not run: a loop that is only written in one is not a poll.
check "a # inside a word starts no comment: the loop after it still blocks" 2 \
  "$(run_hook "$(json 'echo $# a#b; while true; do sleep 1; done')")"

# A comment and a quoted argument are text. Bash runs neither, so a loop
# or a wait that is only MENTIONED there is not one; the same text typed as a
# command still is, and so is a `$(...)` inside double quotes, which runs.
check "a sleep loop named in a comment passes" 0 \
  "$(run_hook "$(json 'printf done # while true; do sleep 1; done')")"
check "a sleep loop quoted in a multi-line body passes" 0 \
  "$(run_hook "$(json $'gh issue create --title x --body "The hook refuses\nwhile true; do sleep 1; done\nand it should."')")"
check "a sleep chain named in a comment passes" 0 \
  "$(run_hook "$(json 'date # sleep 30; gh pr checks 1; sleep 30; gh pr checks 1')")"
check "a foreground wait named in a comment passes" 0 \
  "$(run_hook "$(bg 'printf done # && orca-ide orchestration check --wait --json' false)")"
check "a wait loop named in a comment passes" 0 \
  "$(run_hook "$(bg 'printf done # while true; do bash scripts/orca-wait.sh; done' false)")"
check "a real sleep loop after a comment line still blocks" 2 \
  "$(run_hook "$(json $'# poll the log\nwhile true; do sleep 1; done')")"
check "a real sleep loop after a quoted body still blocks" 2 \
  "$(run_hook "$(json $'gh issue comment 1 --body "two\nlines"; while true; do sleep 5; done')")"
check "a sleep loop inside a command substitution in double quotes blocks" 2 \
  "$(run_hook "$(json 'echo "$(while true; do sleep 1; done)"')")"
check "a real wait loop after a comment line still blocks" 2 \
  "$(run_hook "$(bg $'# drain\nwhile true; do bash scripts/orca-wait.sh; done' true)")"
check "a wait loop behind a quoted word that starts with # still blocks" 2 \
  "$(run_hook "$(bg 'grep "#todo" notes.md; while true; do bash scripts/orca-wait.sh; done' true)")"
# A quoted word keeps the quote characters it holds; left in, the word parser
# gave up on the whole command and no loop was seen.
check "a wait loop behind a quoted word holding an apostrophe still blocks" 2 \
  "$(run_hook "$(bg 'grep "it'"'"'s" notes.md; while true; do bash scripts/orca-wait.sh; done' true)")"
check "a wait loop behind a quoted word holding a double quote still blocks" 2 \
  "$(run_hook "$(bg $'grep \'say"hi\' notes.md; while true; do bash scripts/orca-wait.sh; done' true)")"
check "a wait loop behind a quoted word holding a backslash still blocks" 2 \
  "$(run_hook "$(bg $'grep \'a\\\\\' notes.md; while true; do bash scripts/orca-wait.sh; done' true)")"
# The word parser is never handed what a quoted span holds unless it is plain
# word characters.
check "a wait loop beside a quoted word ending in one backslash still blocks" 2 \
  "$(run_hook "$(bg $'while true; do bash scripts/orca-wait.sh; done; printf \'%s\' \'a\\\'' true)")"
# A copy of the hook WITHOUT the quote helper reads the raw command, quotes and
# all, and still sees the loop: the tokenizer splits any text, so none is given up on.
mkdir -p "$TEST_REPO/nolib"; cp "$HOOK" "$TEST_REPO/nolib/no-poll-loops.sh"
bare_hook() { (cd "$TEST_REPO" && printf '%s\n' "$1" | env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR bash "$TEST_REPO/nolib/no-poll-loops.sh" 2>&1 >/dev/null); echo "rc=$?"; }
check "without the quote helper a wait loop beside unsplittable text still blocks" rc=2 \
  "$(bare_hook "$(bg $'while true; do bash scripts/orca-wait.sh; done; printf %s $\'a\\\'b\'' true)" | tail -1)"
check "one foreground drain with a quoted argument holding an apostrophe passes" 0 \
  "$(run_hook "$(bg 'bash scripts/orca-wait.sh "it'"'"'s"' false)")"
check "a sleep loop behind a quoted word holding an apostrophe still blocks" 2 \
  "$(run_hook "$(json 'grep "it'"'"'s" notes.md; while true; do sleep 1; done')")"
check "an Orca send named only in a comment does not excuse a sleep loop" 2 \
  "$(run_hook "$(json 'while true; do sleep 60; done # orca-ide orchestration send --type status')")"

# #89: a bare inbox check returns a batch and never acknowledges it, so the batch
# replays on every check and later messages queue behind it, in any pane.
git -C "$TEST_REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$TEST_REPO" worktree add -q "$TEST_REPO/wt" 2>/dev/null
# run_wt <payload> -- the hook in a linked worktree (a worker pane); TTL=1h sets the pane's prompt cache life.
run_wt() { (cd "$TEST_REPO/wt" && printf '%s\n' "$1" | env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u CLAUDE_CODE_PROMPT_CACHE_TTL \
  ${TTL:+CLAUDE_CODE_PROMPT_CACHE_TTL=$TTL} "$HOOK" 2>&1); echo "rc=$?"; }
for c in 'orca orchestration check' 'orca-ide orchestration check --json' 'cd /tmp && orca orchestration check --run r1'; do
  check "a bare check blocks: $c" 2 "$(run_hook "$(bg "$c" false)")"
done
check "a bare check blocks in a worker pane too" rc=2 "$(run_wt "$(bg 'orca orchestration check --json' false)" | tail -1)"
check "and the block names orca-wait.sh" 1 "$(run_wt "$(bg 'orca orchestration check --json' false)" | grep -c 'orca-wait.sh')"
for f in --peek --all --ack '--terminal term_1' --help '--wait --timeout-ms 1'; do
  check "a check with $f passes" 0 "$(run_hook "$(bg "orca orchestration check $f --json" true)")"
done
check "a bare check named in a commit message passes" 0 "$(run_hook "$(bg 'git commit -m "orca orchestration check"' false)")"
# Issue 214: no worker call waits past the prompt cache, since the next reply then rewrites it. A foreground call's
# stated waits are summed against one budget (270 s, wait-test-run.sh's default; 540 s under the 1-hour cache), and a
# foreground sleep loop, which states no end, is refused. A background call or a Monitor ends the turn: not held.
rc_wt() { run_wt "$(bg "$1" "${2:-false}")" | tail -1; }
OUT=$(run_wt "$(bg 'until grep -q passed /tmp/t.log; do sleep 5; done' false)")
check "a worker's foreground sleep loop on a test log is refused, naming run_in_background and wait-test-run.sh" rc=2:1 \
  "$(tail -1 <<<"$OUT"):$(grep -c 'run_in_background' <<<"$OUT" | tr -d ' ')$(grep -q 'wait-test-run.sh' <<<"$OUT" || echo ' no wait-test-run.sh')"
check "a worker's while kill -0 sleep loop is refused" rc=2 "$(rc_wt 'while kill -0 123; do sleep 5; done')"
check "a worker's ask of --timeout-ms 600000 is refused" rc=2 "$(rc_wt 'orca-ide orchestration ask --from t --question q --timeout-ms 600000')"
check "and its --resume rerun" rc=2 "$(rc_wt 'orca-ide orchestration ask --from t --question q --timeout-ms 600000 --resume m1')"
check "and under the 1-hour cache" rc=2 "$(TTL=1h rc_wt 'orca-ide orchestration ask --from t --question q --timeout-ms 600000')"
check "a quoted timeout is the number bash passes" rc=2 "$(rc_wt 'orca-ide orchestration ask --from t --question q --timeout-ms "600000"')"
OUT=$(run_wt "$(bg 'orca-ide orchestration ask --from t --question q --timeout-ms 240000; orca-ide orchestration ask --from t --question r --timeout-ms 240000' false)")
check "two asks of 240 s in one call (480 s) are refused, the sum named" rc=2:1 "$(tail -1 <<<"$OUT"):$(grep -c 'up to 480 s in all' <<<"$OUT")"
check "sleep 180; sleep 180 is refused" rc=2 "$(rc_wt 'sleep 180; sleep 180')"
check "sleep 400 is refused" rc=2 "$(rc_wt 'sleep 400')"
check "sleep 5m is refused" rc=2 "$(rc_wt 'sleep 5m')"
check "two wait-test-run.sh waits (540 s) are refused" rc=2 "$(rc_wt 'bash scripts/wait-test-run.sh 1 a.out; bash scripts/wait-test-run.sh 2 b.out')"
check "an ask of --timeout-ms 240000 passes" rc=0 "$(rc_wt 'orca-ide orchestration ask --from t --question q --timeout-ms 240000')"
check "--timeout-ms=540000 passes under the 1-hour cache" rc=0 "$(TTL=1h rc_wt 'orca-ide orchestration ask --from t --question q --timeout-ms=540000')"
check "a sleep 20 and an ask of 200 s (220 s) pass" rc=0 "$(rc_wt 'sleep 20; orca-ide orchestration ask --from t --question q --timeout-ms 200000')"
check "one wait-test-run.sh wait passes" rc=0 "$(rc_wt 'bash scripts/wait-test-run.sh 123 out.txt')"
check "sleep 20 && npm test passes" rc=0 "$(rc_wt 'sleep 20 && npm test')"
check "a background sleep loop passes" rc=0 "$(rc_wt 'until test -f x; do sleep 3; done' true)"
check "a Monitor passes" rc=0 "$(run_wt "$(jq -cn '{tool_name:"Monitor",tool_input:{command:"until test -f x; do sleep 3; done"}}')" | tail -1)"
check "a here-document whose body is a long ask is data, passes" rc=0 \
  "$(rc_wt $'cat > notes.md <<\'EOF\'\norca-ide orchestration ask --from t --question q --timeout-ms 600000\nEOF')"
check "a worker's plain command passes" rc=0 "$(rc_wt 'sleep 1 && date')"
# r1 findings: a sleep named by its path is still sleep; a wait in a loop repeats, so its one-pass sum is no bound;
# sleep sums all its operands; only a command that runs a --timeout-ms waits on it.
check "a worker's /bin/sleep loop is refused" rc=2 "$(rc_wt 'while kill -0 $$; do /bin/sleep 5; done')"
check "a worker's sleep loop past an inner loop named done is refused" rc=2 "$(rc_wt 'while true; do for done in a; do :; done; sleep 5; done')"
check "a worker's sleep loop past an echo of \${done} is refused" rc=2 "$(rc_wt 'while true; do echo ${done}; sleep 5; done')"
check "/bin/sleep 400 is refused" rc=2 "$(rc_wt '/bin/sleep 400')"
check "a wait-test-run.sh in a loop is refused" rc=2 "$(rc_wt 'for n in 1 2; do bash scripts/wait-test-run.sh $$ /dev/null; done')"
check "an ask in a loop is refused" rc=2 "$(rc_wt 'for n in 1 2; do orca-ide orchestration ask --from t --question q --timeout-ms 240000; done')"
check "a sleep in a while condition is refused" rc=2 "$(rc_wt 'while sleep 5; do date; done')"
check "sleep 200 200 (400 s) is refused" rc=2 "$(rc_wt 'sleep 200 200')"
check "sleep 2m 100 (220 s) passes" rc=0 "$(rc_wt 'sleep 2m 100')"
check "a search for a --timeout-ms pattern passes" rc=0 "$(rc_wt "rg -n -- '--timeout-ms=600000' .")"
check "a loop with no wait passes" rc=0 "$(rc_wt 'for f in a b; do echo done; done; sleep 10')"
for c in 'env sleep 400' 'timeout 600 sleep 400' 'echo $(sleep 400)' 'sleep infinity' 'until false; do ./scripts/wait-test-run.sh 1 a.out; done' \
  'X=1 command /usr/bin/sleep 400'; do
  check "the same guard's other ways round: $c is refused" rc=2 "$(rc_wt "$c")"
done
check "main: a /bin/sleep loop is refused" 2 "$(run_hook "$(json 'while true; do /bin/sleep 30; gh pr view 1; done')")"
# r2 findings: a wrapper's options, a redirection anywhere in the command, and any duration GNU sleep (or orca's
# --timeout-ms) accepts are read as bash and sleep read them; a sleep operand the hook cannot read is refused.
for c in 'env -u FOO orca-ide orchestration ask --from t --question q --timeout-ms 600000' 'command -- sleep 400' \
  'timeout --signal=TERM 600 sleep 400' 'timeout -s TERM -k 5 600 sleep 400' 'env -i -C /tmp sleep 400' 'nice -n 5 sleep 400' \
  '> /dev/null orca-ide orchestration ask --from t --question q --timeout-ms 600000' '2>&1 sleep 400' 'sleep>/dev/null 400' \
  'sleep 5m>/dev/null' 'sleep 4e2' 'sleep +400' 'sleep 0x190' 'sleep 4e0m 100' 'while true; do sleep 4e2; done' \
  'while true; do sleep +1; done' 'sleep $T' 'orca-ide orchestration ask --from t --question q --timeout-ms 6e5'; do
  check "worker: $c is refused" rc=2 "$(rc_wt "$c")"
done
for c in 'sleep .5' 'sleep 1e1 2>/dev/null' 'env -u FOO sleep 200' 'sleep 100 >&2'; do
  check "worker: $c passes" rc=0 "$(rc_wt "$c")"
done
check "worker: an unreadable sleep operand is named, not summed" 1 "$(run_wt "$(bg 'sleep $T' false)" | grep -c 'cannot read')"
for c in 'while true; do env -u X sleep 30; done' 'while true; do sleep +5; done' 'while true; do > /dev/null sleep 5; done' \
  'while true; do timeout --signal=TERM 9 sleep 5; done' 'sleep 30 >/dev/null; gh pr checks 1; sleep 30 >/dev/null; gh pr checks 1'; do
  check "main: $c is refused" 2 "$(run_hook "$(json "$c")")"
done
for c in 'env -u X orca-ide orchestration check --wait --json' '>/dev/null orca-ide orchestration check --wait --json'; do
  check "main: a foreground wait behind a wrapper or redirection blocks: $c" 2 "$(run_hook "$(bg "$c" false)")"
done
for c in '>/dev/null orca orchestration check' 'env -u X orca orchestration check' 'while true; do orca orchestration check; done'; do
  check "a bare check blocks: $c" 2 "$(run_hook "$(bg "$c" true)")"
done
for c in 'while true; do env -u X bash scripts/orca-wait.sh; done' 'while true; do bash scripts/orca-wait.sh>/dev/null; done'; do
  check "a wait loop blocks: $c" 2 "$(run_hook "$(bg "$c" true)")"
done
# r3 findings: a quoted argument keeps its position (a wrapper's option value, a redirection target), a descriptor
# duplication is one redirection, env's argv0 takes a value, and `command -v`/`-V` looks a name up without running it.
check "a bare check behind a quoted redirection target blocks" 2 "$(run_hook "$(bg '>"/dev/null" orca orchestration check' true)")"
check "main: a foreground wait behind a quoted wrapper option blocks" 2 \
  "$(run_hook "$(bg 'env -u "FOO" orca-ide orchestration check --wait --timeout-ms 600000' false)")"
check "main: a chain of quoted sleeps is refused" 2 "$(run_hook "$(json 'sleep "30"; gh pr checks 1; sleep "30"; gh pr checks 1')")"
check "a wait loop behind a leading 2>&1 blocks" 2 "$(run_hook "$(bg 'while true; do 2>&1 bash scripts/orca-wait.sh; done' true)")"
for c in 'env -a custom sleep 400' 'env --argv0 custom sleep 400' 'env -P /bin sleep 400' 'command -p sleep 400' \
  'env -u "FOO" sleep 400'; do
  check "worker: $c is refused" rc=2 "$(rc_wt "$c")"
done
for c in 'command -v sleep bash' 'command -V sleep' 'command -pv sleep'; do
  check "worker: $c passes" rc=0 "$(rc_wt "$c")"
done
# r5 finding: bash reads a reserved word only unquoted. A quoted or escaped `done` is a command that fails, and the
# loop goes on, so it must not end the loop's depth; an escaped or quoted command word is still the command it spells.
for c in 'while true; do "do""ne"; bash scripts/orca-wait.sh; done' 'while true; do ""done; bash scripts/orca-wait.sh; done' \
  'while true; do d\one; bash scripts/orca-wait.sh; done' "while true; do 'done'; bash scripts/orca-wait.sh; done"; do
  check "a wait loop behind a quoted done blocks: $c" 2 "$(run_hook "$(bg "$c" true)")"
done
for c in 'while true; do "done"; sleep 5; gh pr view 1; done' 'while true; do "sleep" 5; gh pr view 1; done' \
  'while true; do \sleep 5; gh pr view 1; done' 's\leep 30; gh pr checks 1; s\leep 30; gh pr checks 1'; do
  check "main: a sleep loop behind quoting blocks: $c" 2 "$(run_hook "$(json "$c")")"
done
for c in 'while true; do "done"; sleep 100; done' 's\leep 400' '\sleep 400' '"sl"eep 400'; do
  check "worker: $c is refused" rc=2 "$(rc_wt "$c")"
done
# r6 finding: an empty pair of quotes changes no word bash passes; it only keeps a reserved word from reading as one.
for c in 'sleep"" 400' "sleep'' 400" 'sleep 400""' 'sl""eep 400' 'while true; do done""; sleep 100; done'; do
  check "worker: $c is refused" rc=2 "$(rc_wt "$c")"
done
for c in 'orca orchestration check""' 'orca orchestration"" check' 'orca"" orchestration check'; do
  check "a bare check behind an empty pair of quotes blocks: $c" 2 "$(run_hook "$(bg "$c" true)")"
done
check "worker: a bare check\"\" blocks" rc=2 "$(rc_wt 'orca orchestration check""')"
check "main: a sleep loop behind done\"\" blocks" 2 "$(run_hook "$(json 'while true; do done""; sleep 5; gh pr view 1; done')")"
check "worker: X=\"\" sleep 400 is refused" rc=2 "$(rc_wt 'X="" sleep 400')"
check "a quoted done as an argument still passes" 0 "$(run_hook "$(json 'echo "done"; sleep 4')")"
check "worker: an escaped semicolon is an argument, not a second command" rc=0 "$(rc_wt 'find . -name x -exec sleep 1 \;')"
# r7 finding: quoting next to quoting (an empty pair, an escape, a quoted span) is still one word bash passes.
for c in '"""sleep" 400' '""\sleep 400' "''\"sleep\" 400" '"""s"\leep 400' '""""sleep 400'; do
  check "worker: $c is refused" rc=2 "$(rc_wt "$c")"
done
for c in '"""orca" orchestration check' '""\orca orchestration check' 'orca """orchestration" check'; do
  check "a bare check behind adjacent quoting blocks: $c" 2 "$(run_hook "$(bg "$c" true)")"
done
check "worker: a bare \"\"\"orca\" check blocks" rc=2 "$(rc_wt '"""orca" orchestration check')"
check "worker: an escaped quote before \"\"sleep is the word \"sleep, passes" rc=0 "$(rc_wt '\"""sleep 400')"

# Issues 216 and 215: a shell string runs too. The script of `bash -c`, `eval` and `env -S` is read by the same rules,
# and `$'...'` and `$"..."` quote as bash reads them, so `$'sleep'` is the word sleep.
for c in "bash -c 'sleep 400'" 'sh -c "sleep 400"' "zsh -c 'sleep 300'" "eval 'sleep 400'" "env -S 'sleep 400'" \
  "\$'sleep' 400" '$"sleep" 400' "bash -lc 'sleep 400'" "timeout 900 bash -c 'sleep 400'" "bash -c \"bash -c 'sleep 400'\"" \
  "sleep 200; bash -c 'sleep 100'" "env -u X -S 'sleep 400'"; do
  check "worker: $c is refused" rc=2 "$(rc_wt "$c")"
done
check "worker: a sleep loop inside bash -c is refused as a loop" 1 \
  "$(run_wt "$(bg "bash -c 'for i in 1 2; do sleep 1; done'" false)" | grep -c 'inside a loop')"
check "worker: bash -c inside a loop is refused as a loop" rc=2 "$(rc_wt "for i in 1 2; do bash -c 'sleep 1'; done")"
for c in "bash -c 'sleep 100'" "bash -c 'echo hi'" "eval 'echo sleep 400'" "bash scripts/x.sh 'sleep 400'"; do
  check "worker: $c passes" rc=0 "$(rc_wt "$c")"
done
# The script of a shell string quoted $'...' or $"..." is read as bash reads it: shlex took the $ for part of the word.
for c in "bash -c \$'sleep 400'" 'bash -c $"sleep 400"' "env -S \$'sleep 400'" "sh -c \$'echo \\'hi\\'; sleep 400'" \
  "bash -c \$'sleep\\x20400'" "bash -c \"bash -c \$'sleep 400'\"" "echo 'cost \$'; bash -c 'sleep 400'" \
  "bash -c \$'sleep\\cI400'" "env -S \$'sleep\\cI400'" "bash -c \$'sleep\\ci400'"; do
  check "worker: $c is refused" rc=2 "$(rc_wt "$c")"
done
for c in "bash -c \$'echo sleep 400'" "bash -c \$'sleep 100'" 'bash -c $"sleep 100"' "bash -c \$'sleep\\cI100'" \
  "bash -c \$'echo \\x; sleep 100'"; do
  check "worker: $c passes" rc=0 "$(rc_wt "$c")"
done
check "worker: a shell string the hook cannot read is refused, and says why" 1 \
  "$(run_wt "$(bg "bash -c 'sleep \"400'" false)" | grep -c 'cannot read')"
# \c of a non-ASCII character: bash takes one byte of it, the decoder cannot say what; read as unread, not a crash that allows.
check "worker: bash -c \$'sleep 400; echo \\cß' is refused as unread" 1 \
  "$(run_wt "$(bg "bash -c \$'sleep 400; echo \\cß'" false)" | grep -c 'cannot read')"
check "worker: ... and the decoder rejects it, no traceback in the refusal" 0 \
  "$(run_wt "$(bg "bash -c \$'sleep 400; echo \\cß'" false)" | grep -c 'Traceback')"
check "worker: bash -c \$'echo \\cß' names no wait and passes" rc=0 "$(rc_wt "bash -c \$'echo \\cß'")"
# Any crash of the wait reader (the one `python3 -I`) is a wait not read: it printed nothing, which once allowed.
mkdir -p "$TEST_REPO/crashpy"
printf '#!/bin/sh\n[ "$1" = -I ] && exit 1\nexec %s "$@"\n' "$(command -v python3)" > "$TEST_REPO/crashpy/python3"
chmod +x "$TEST_REPO/crashpy/python3"
check "worker: a crashed wait reader refuses, not allows" 1 \
  "$(PATH="$TEST_REPO/crashpy:$PATH" run_wt "$(bg 'sleep 400' false)" | grep -c 'cannot read')"

# The wrapper that runs every self-test in the push gate asserts `0 failed` on
# stdout, so the summary is worded the way every sibling words it.
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
