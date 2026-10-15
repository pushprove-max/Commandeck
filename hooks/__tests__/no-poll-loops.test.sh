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
check "while-loop with sleep blocks" 2 \
  "$(run_hook "$(json 'while true; do sleep 60; done')")"
check "until-loop with sleep blocks" 2 \
  "$(run_hook "$(json 'until test -f x; do sleep 5; done')")"
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
check "a background until-loop of orca-wait.sh blocks" 2 \
  "$(run_hook "$(bg 'until false; do bash scripts/orca-wait.sh; done' true)")"
check "a background loop of the raw check --wait blocks" 2 \
  "$(run_hook "$(bg 'while :; do orca-ide orchestration check --wait --json; done' true)")"
check "a loop that only SEARCHES for orca-wait.sh passes" 0 \
  "$(run_hook "$(bg 'for f in a.md b.md; do grep -n orca-wait.sh docs/$f; done' false)")"
check "a loop of a double-quoted wait path blocks" 2 \
  "$(run_hook "$(bg 'while true; do bash "scripts/orca-wait.sh"; done' true)")"
check "a loop of a single-quoted wait path blocks" 2 \
  "$(run_hook "$(bg "while true; do bash 'scripts/orca-wait.sh'; done" true)")"
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
check "a loop that is only in a comment passes" 0 \
  "$(run_hook "$(json 'printf done # while true; do sleep 1; done')")"
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
# word characters, and a command it still cannot split blocks when it names a wait.
check "a wait loop beside a quoted word ending in one backslash still blocks" 2 \
  "$(run_hook "$(bg $'while true; do bash scripts/orca-wait.sh; done; printf \'%s\' \'a\\\'' true)")"
# With the quote helper loaded its output holds no quote or backslash, so the
# parser has nothing to give up on; a copy of the hook WITHOUT the helper reads
# the raw command, and bash's $'a\'b' is text the parser cannot split.
mkdir -p "$TEST_REPO/nolib"; cp "$HOOK" "$TEST_REPO/nolib/no-poll-loops.sh"
bare_hook() { (cd "$TEST_REPO" && printf '%s\n' "$1" | env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR bash "$TEST_REPO/nolib/no-poll-loops.sh" 2>&1 >/dev/null); echo "rc=$?"; }
GIVEUP=$(bare_hook "$(bg $'bash scripts/orca-wait.sh; printf %s $\'a\\\'b\'' false)")
check "a command the parser cannot split blocks when it names a wait" 1 "$(grep -c '^rc=2$' <<<"$GIVEUP")"
check "and the refusal says it could not be read as shell words" 1 "$(grep -c 'could not be read as shell words' <<<"$GIVEUP")"
check "a command the parser cannot split passes when it names no wait" 1 \
  "$(bare_hook "$(bg $'orca-ide orchestration check --peek --json; printf %s $\'a\\\'b\'' false)" | grep -c '^rc=0$')"
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
run_wt() { (cd "$TEST_REPO/wt" && printf '%s\n' "$1" | env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR "$HOOK" 2>&1); echo "rc=$?"; }
for c in 'orca orchestration check' 'orca-ide orchestration check --json' 'cd /tmp && orca orchestration check --run r1'; do
  check "a bare check blocks: $c" 2 "$(run_hook "$(bg "$c" false)")"
done
check "a bare check blocks in a worker pane too" rc=2 "$(run_wt "$(bg 'orca orchestration check --json' false)" | tail -1)"
check "and the block names orca-wait.sh" 1 "$(run_wt "$(bg 'orca orchestration check --json' false)" | grep -c 'orca-wait.sh')"
for f in --peek --all --ack '--terminal term_1' --help '--wait --timeout-ms 1'; do
  check "a check with $f passes" 0 "$(run_hook "$(bg "orca orchestration check $f --json" true)")"
done
check "a bare check named in a commit message passes" 0 "$(run_hook "$(bg 'git commit -m "orca orchestration check"' false)")"
# #84: a Builder's hand-written poll on test output gets pointed at the background run and the one wait helper,
# which checks the runner is alive: a wait on a dead runner's output once ran 25 minutes.
NUDGE=$(run_wt "$(bg 'until grep -q passed /tmp/t.log; do sleep 5; done' false)")
check "a worker's sleep loop on a test log passes" rc=0 "$(tail -1 <<<"$NUDGE")"
check "with a nudge naming run_in_background and wait-test-run.sh" 1 "$(grep -c 'run_in_background.*wait-test-run.sh' <<<"$NUDGE")"
check "a worker's plain command gets no nudge" rc=0 "$(run_wt "$(bg 'sleep 1 && date' false)")"

# The wrapper that runs every self-test in the push gate asserts `0 failed` on
# stdout, so the summary is worded the way every sibling words it.
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
