#!/usr/bin/env bash
# post-fix-checks.sh [<test file>...] -- the post-fix checks at once: `run-shell-tests.sh` on the named test files
# (shell) and, in a plugin checkout (.claude-plugin/plugin.json at the top), `claude plugin validate .` (validate)
# and `claude plugin test .` (mods). They are independent, and run one after another each fix waits for their sum.
#
# Start all, then `wait` on each pid and keep each status in its own slot. The exit code is computed once, after the
# last one ends, so an early failure cannot be hidden by later passes. Exit 0: all green. 1: any red, timed out or
# interrupted. 2: nothing started. Every check runs under `timeout` (540 s, below the Bash tool's 600 s ceiling);
# POST_FIX_CHECK_TIMEOUT_S overrides the cap so a test reaches the timeout in seconds. Logs stay in
# $PP_SCRATCH/post-fix.XXXXXX/ for the evidence.
set -u

case "${1:-}" in
  -h|--help) echo "usage: post-fix-checks.sh [<test file>...]"; echo "example: bash scripts/post-fix-checks.sh hooks/__tests__/git-safety.test.sh"; exit 0 ;;
esac

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) && cd "$ROOT" || { echo "post-fix: not inside a git checkout" >&2; exit 2; }
. "$HERE/paths.sh" >/dev/null || exit 2
CAP=${POST_FIX_CHECK_TIMEOUT_S:-540}
NAMES=() CMDS=()
# Each command runs as `exec`, so the timeout's TERM reaches the check itself.
[ $# -eq 0 ] || { NAMES+=(shell); CMDS+=("exec bash $(printf '%q' "$HERE/run-shell-tests.sh")$(printf ' %q' "$@")"); }
[ -f .claude-plugin/plugin.json ] && { NAMES+=(validate mods); CMDS+=("exec claude plugin validate ." "exec claude plugin test ."); }
[ ${#NAMES[@]} -gt 0 ] || { echo "post-fix: nothing to check: no test files named and no .claude-plugin/plugin.json here" >&2; exit 2; }
mkdir -p "$PP_SCRATCH" 2>/dev/null
DIR=$(mktemp -d "$PP_SCRATCH/post-fix.XXXXXX") || { echo "post-fix: cannot make a run directory under $PP_SCRATCH" >&2; exit 2; }

PIDS=() T0=() RC=() SECS=() DONE=()
interrupted() {
  local i
  kill -TERM "${PIDS[@]}" 2>/dev/null
  wait "${PIDS[@]}" 2>/dev/null
  for i in "${!NAMES[@]}"; do [ "${DONE[i]}" = 1 ] || echo "post-fix: interrupted: ${NAMES[i]} cut off ($DIR/${NAMES[i]}.log)"; done
  exit 1
}
trap interrupted INT TERM HUP

for i in "${!NAMES[@]}"; do
  timeout --kill-after=10s "${CAP}s" bash -c "${CMDS[i]}" >"$DIR/${NAMES[i]}.log" 2>&1 &
  PIDS+=($!); T0+=($SECONDS); DONE+=(0)
done

# Poll so each check's seconds are its own end time, then `wait` once per pid for its status.
while :; do
  LEFT=0
  for i in "${!NAMES[@]}"; do
    [ "${DONE[i]}" = 1 ] && continue
    if kill -0 "${PIDS[i]}" 2>/dev/null; then LEFT=1
    else
      wait "${PIDS[i]}"; RC[i]=$?; SECS[i]=$((SECONDS - T0[i])); DONE[i]=1
    fi
  done
  [ "$LEFT" = 0 ] && break
  sleep 0.5
done

FAILED=()
for i in "${!NAMES[@]}"; do
  N=${NAMES[i]}
  case "${RC[i]}" in
    124|137) echo "post-fix: $N timed out after ${CAP}s (exit ${RC[i]}) $DIR/$N.log" ;;
    *) echo "post-fix: $N exit ${RC[i]} (${SECS[i]}s) $DIR/$N.log" ;;
  esac
  [ "${RC[i]}" = 0 ] && continue
  FAILED+=("$N")
  echo "--- $N: last 30 lines ---"; tail -n 30 "$DIR/$N.log"
done

if [ "${#FAILED[@]}" = 0 ]; then echo "post-fix: all green"; exit 0; fi
echo "post-fix: ${#FAILED[@]} of ${#NAMES[@]} failed: $(IFS=,; echo "${FAILED[*]}")"
exit 1
