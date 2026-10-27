#!/usr/bin/env bash
# Self-test for bgrun.sh: a worker's slow generic command comes back through one printed wait line with its own
# exit code and output, test footer or not (wait-test-run.sh cannot do that: it never returns the command's code).
# Run: bash scripts/run-shell-tests.sh scripts/__tests__/bgrun.test.sh
set -u
REAL=$(cd "$(dirname "$0")/../.." && pwd)
BG=$REAL/scripts/bgrun.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'pkill -f "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
git init -q "$TMP/proj"
export COMMANDECK_MAIN=$TMP/proj COMMANDECK_WORKSPACES=$TMP/ws COMMANDECK_SCRATCH=$TMP/scratch
bg() { env -u CLAUDE_CODE_PROMPT_CACHE_TTL bash "$BG" "$@" > "$TMP/out" 2>&1; echo $?; }
cnt() { grep -c -- "$1" "$TMP/out"; }
waitline() { sed -n 's/.*wait with: bash .*bgrun.sh wait //p' "$TMP/out" | head -1; }
sleep 300 & UNREL=$!

check "quick job prints rc and tail inline" "0 1 1" "$(bg --max 10 -- bash -c 'echo hello; echo world') $(cnt '^rc=0') $(cnt '^world')"
check "quick job exits with the command's code and --lines caps the tail" "5 1 0" \
  "$(bg --max 10 --lines 1 -- bash -c 'echo first; echo last; exit 5') $(cnt '^last') $(cnt '^first')"
check "any command: exit 7 and its output come back through the printed wait line" "3 1 7 1 1" \
  "$(bg --max 1 -- bash -c 'sleep 2; echo finished; exit 7') $(cnt 'still running pid=') $(L=$(waitline); bg wait "$L" --max 20) $(cnt '^rc=7') $(cnt '^finished')"
check "the printed wait line names this script's own path" "1" "$(bg --max 0 -- sleep 5 >/dev/null; grep -c "wait with: bash $BG wait " "$TMP/out")"
check "wait on a job still running at its limit: exit 3 and the same line" "3 1" \
  "$(bg --max 0 -- sleep 30 >/dev/null; L=$(waitline); bg wait "$L" --max 1) $(cnt 'still running')"
check "a child killed before it wrote an exit code: exit 1, died" "1 1" \
  "$(bg --max 0 -- sleep 300 >/dev/null; L=$(waitline); P=$(cat "$L.pid"); C=$(pgrep -P "$P"); kill -KILL "$P"; kill -KILL $C 2>/dev/null; bg wait "$L" --max 5) $(cnt 'died with no exit code')"
# .pid is the wrapper's; the command is its child and outlives a killed wrapper. A retry on "died" would repeat its side effects.
T=$TMP/live; mkdir -p "$T"
bg --max 0 -- bash -c 'echo "$BASHPID" > "$1/job.pid"; while [ ! -e "$1/release" ]; do sleep 0.02; done; echo survived > "$1/survived"' _ "$T" >/dev/null
L=$(waitline)
for _ in $(seq 1 250); do [ -s "$T/job.pid" ] && break; sleep 0.02; done
kill -KILL "$(cat "$L.pid")" 2>/dev/null
check "a killed wrapper whose command lives on reads still running, never died" "3 1 0" \
  "$(bg wait "$L" --max 0) $(cnt 'still running') $(cnt 'died with no exit code')"
touch "$T/release"
for _ in $(seq 1 250); do [ -e "$T/survived" ] && break; sleep 0.02; done
check "the command that outlived its wrapper ran to the end" "survived" "$(cat "$T/survived" 2>/dev/null)"
check "once that command ends with no exit code recorded: exit 1, died" "1 1" \
  "$(bg wait "$L" --max 5) $(cnt 'died with no exit code')"
check "wait on a log that never existed: exit 1" "1" "$(bg wait "$TMP/nope.log")"
# A .pid with no number in it names no child: it reads dead, never as `kill -0 0`, which is the caller's own group.
check "an empty pid file reads died, never still running" "1 1" \
  "$(: > "$TMP/empty.log"; : > "$TMP/empty.log.pid"; bg wait "$TMP/empty.log" --max 2) $(cnt 'died with no exit code')"
check "no command is a usage error" "2" "$(bg --max 5)"
check "the exit code file is never half written" "0" "$(bg --max 10 -- true >/dev/null; ls "$COMMANDECK_SCRATCH"/bgrun/*.rc.tmp 2>/dev/null | wc -l | tr -d ' ')"
check "the wait limit is wait-test-run's own: 270 s, 540 s on the 1-hour cache" "1 1" \
  "$(bash "$BG" --help | grep -c 'default 270') $(CLAUDE_CODE_PROMPT_CACHE_TTL=1h bash "$BG" --help | grep -c 'default 540')"
check "--help is answered before anything is sourced: no project, no scratch" "0 1" \
  "$(cd "$TMP" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR bash "$BG" --help >/dev/null 2>&1; echo $?) $(bash "$BG" -h | grep -c usage)"
check "an unrelated sleep started by the test is never killed by the runs above" "alive" \
  "$(kill -0 "$UNREL" 2>/dev/null && echo alive || echo killed)"
kill "$UNREL" 2>/dev/null

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
