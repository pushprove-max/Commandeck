#!/usr/bin/env bash
# wait-test-run.sh <runner-pid> <output-file> [max-seconds] -- wait on a
# background test run. Ends when the runner exits or the limit (default
# 270 s, under the 300 s the prompt cache lives, so a wait never outlasts it) is reached, and checks the runner is
# alive whenever it stops: a Builder once started a second wait on the output
# of a runner that had died with no result, and waited 25 minutes on it.
#   0  the runner is gone and its output ends with a result; the tail is printed
#   1  the runner is gone with no result at the end: rerun the needed file alone
#   3  the runner is still running at the limit: waiting again is allowed
# A result is run-shell-tests.sh's or a self-test's "<n> passed, <n> failed"
# summary as the last line (or before the runner's "failed:" file list), or node:test's summary block from "ℹ pass <n>"
# through its closing "ℹ duration_ms", followed only by its failing-tests
# listing and npm's error lines.
# Self-test: bash scripts/__tests__/wait-test-run.test.sh
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
USAGE="usage: wait-test-run.sh <runner-pid> <output-file> [max-seconds]"
PID=${1:-} OUT=${2:-} MAX=${3:-270}
[[ $PID =~ ^[0-9]+$ && -n $OUT && $MAX =~ ^[0-9]+$ ]] || { echo "$USAGE" >&2; exit 2; }
END=$((SECONDS + MAX))
while kill -0 "$PID" 2>/dev/null && [ "$SECONDS" -lt "$END" ]; do sleep 1; done
if kill -0 "$PID" 2>/dev/null; then
  echo "runner $PID is still running after ${MAX}s; $OUT so far: $(wc -l 2>/dev/null < "$OUT" | tr -d ' ') lines"
  exit 3
fi
# Only the output's last block counts: a summary from an earlier suite followed
# by a later suite that died is no result.
if awk '/^[0-9]+ passed, [0-9]+ failed/ {r=1; n=0; s=1; next}
  s && /^failed:$/ {next}
  s && /^  / {next}
  /^ℹ pass [0-9]+/ {r=0; n=1; s=0; next}
  n && /^ℹ duration_ms / {r=1; next}
  /^[[:space:]]*$/ {next}
  n && (/^ℹ / || /^✖ / || /^test at / || /^[[:space:]]/ || /^npm (error|ERR!) /) {next}
  {r=0; n=0; s=0}
  END {exit !r}' "$OUT" 2>/dev/null; then
  tail -20 "$OUT"
  exit 0
fi
echo "runner $PID died with no result at the end of $OUT; rerun the needed test file alone" >&2
tail -5 "$OUT" 2>/dev/null >&2
exit 1
