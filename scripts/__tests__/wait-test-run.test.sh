#!/usr/bin/env bash
# wait-test-run.sh: a Builder waited 25 minutes on a
# suite whose runner had died with no result, starting a second wait on the
# same output file. The helper checks the runner is alive whenever it stops
# waiting, so a dead runner ends the wait at once and says what to do.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
WAIT=$REAL/scripts/wait-test-run.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'kill "${LIVE:-}" 2>/dev/null; rm -rf "$TMP"' EXIT

# A runner that dies mid-run, its output cut off before any result line.
printf -- '-- ok   a.test.sh 3s\n' > "$TMP/dead.out"
sleep 1 & DEAD=$!
OUT=$(bash "$WAIT" "$DEAD" "$TMP/dead.out" 20 2>&1); RC=$?
check "a runner that died with no result ends the wait non-zero, naming the runner and the rerun" "1 1" \
  "$RC $(grep -c "runner $DEAD died with no result at the end of $TMP/dead.out; rerun the needed test file alone" <<<"$OUT")"

# A runner still running at the limit: the wait ends, and says the runner is alive.
: > "$TMP/live.out"
sleep 60 & LIVE=$!
OUT=$(bash "$WAIT" "$LIVE" "$TMP/live.out" 1 2>&1); RC=$?
check "a live runner at the limit gets its own exit code and the word that it is alive" "3 1" \
  "$RC $(grep -c "runner $LIVE is still running" <<<"$OUT")"
kill "$LIVE" 2>/dev/null

# A runner that finished with its summary line: the wait ends 0 and shows the end of the output.
printf -- '-- ok   a.test.sh 3s\n\n3 passed, 0 failed, 0 parked\n' > "$TMP/done.out"
true & DONE=$!; wait "$DONE"
OUT=$(bash "$WAIT" "$DONE" "$TMP/done.out" 20 2>&1); RC=$?
check "a finished runner with a result ends the wait 0 and prints the result" "0 1" "$RC $(grep -c '^3 passed, 0 failed' <<<"$OUT")"
# node:test's summary is a result too.
printf 'ℹ tests 4\nℹ suites 0\nℹ pass 4\nℹ fail 0\nℹ cancelled 0\nℹ skipped 0\nℹ todo 0\nℹ duration_ms 46\n' > "$TMP/node.out"
bash "$WAIT" "$DONE" "$TMP/node.out" 20 >/dev/null 2>&1
check "a node:test summary counts as a result" 0 "$?"
# duration_ms closes node:test's block: a runner killed inside the block has not
# printed its fail count, so a lone pass count is no result.
for cut in 'ℹ tests 4\nℹ suites 0\nℹ pass 1\n' 'ℹ pass 1\nℹ fail 3\nℹ cancelled 0\n'; do
  printf "$cut" > "$TMP/nodecut.out"
  bash "$WAIT" "$DONE" "$TMP/nodecut.out" 20 >/dev/null 2>&1; rc=$?
  check "a node:test summary cut before duration_ms is no result ($(tail -1 "$TMP/nodecut.out"))" 1 "$rc"
done
# node:test prints its failing-tests listing after the summary; the run still ended.
printf 'ℹ pass 1\nℹ fail 1\nℹ duration_ms 46\n\n✖ failing tests:\n\ntest at a.test.js:1:51\n✖ b (0.1ms)\n  Error: x\n      at a.test.js:1:71\nnpm error Lifecycle script `test:unit` failed with error:\nnpm error code 1\n' > "$TMP/nodefail.out"
bash "$WAIT" "$DONE" "$TMP/nodefail.out" 20 >/dev/null 2>&1
check "a node:test summary followed by its failing-tests listing counts as a result" 0 "$?"
# A summary from an earlier suite is no result when a later suite started and died.
printf 'ℹ pass 1\nsecond suite started\n' > "$TMP/nodelater.out"
bash "$WAIT" "$DONE" "$TMP/nodelater.out" 20 >/dev/null 2>&1
check "a node:test summary with a later suite after it is no result" 1 "$?"
# run-shell-tests.sh lists its failed files after the summary; the run still ended.
printf -- '1 passed, 1 failed, 0 parked\nfailed:\n  /repo/a.test.sh\n' > "$TMP/shellfail.out"
bash "$WAIT" "$DONE" "$TMP/shellfail.out" 20 >/dev/null 2>&1
check "a passed/failed summary followed by its failed-files list counts as a result" 0 "$?"
printf -- '3 passed, 0 failed, 0 parked\n-- ok   b.test.sh 2s\n' > "$TMP/shelllater.out"
bash "$WAIT" "$DONE" "$TMP/shelllater.out" 20 >/dev/null 2>&1
check "a passed/failed summary with later output after it is no result" 1 "$?"

bash "$WAIT" "$DONE" 2>/dev/null
check "a call without an output file is refused" 2 "$?"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
