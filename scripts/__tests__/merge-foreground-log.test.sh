#!/usr/bin/env bash
# Issue 317: in main's foreground a merge is queued BEFORE it detaches. A second request for the same unit at the
# same sha, made while the first is detached but has not yet started, is refused at once (exit 4): it never starts a
# detached run, so it never empties the first one's log (pp_detach truncates its log). Pinned: the second request
# exits 4 with no log written and no second detached run, and the first run's log keeps its STEP 1.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$REAL/scripts/__tests__/fixtures/merge-unit-local-setup.sh"
mk u; go u
[ "$FAIL" = 0 ] || exit 1
export REVIEW_GATE=$TMP
mkdir -p "$REPO/.claude"; printf '{"testCommand":"while [ ! -e %s/finish ]; do sleep 0.1; done"}\n' \
  "$TMP" > "$REPO/.claude/commandeck.json"

# Each detached run waits at nohup, before it takes the lock or opens its log, until the test lets it go.
cat > "$TMP/bin/nohup" <<'SH'
#!/usr/bin/env bash
if mkdir "$REVIEW_GATE/first" 2>/dev/null; then slot=first
else slot=second; mkdir -p "$REVIEW_GATE/second"; fi
echo $$ > "$REVIEW_GATE/$slot/pid"
while [ ! -e "$REVIEW_GATE/$slot/go" ]; do sleep 0.05; done
exec "$@"
SH
chmod +x "$TMP/bin/nohup"
await_file() {
  for ((i=0; i<200; i++)); do
    [ -e "$1" ] && return 0
    sleep 0.05
  done
  return 1
}
cleanup() {
  touch "$TMP/finish" "$TMP/first/go" "$TMP/second/go" 2>/dev/null
  for slot in first second; do
    [ ! -f "$TMP/$slot/pid" ] ||
      tail --pid="$(cat "$TMP/$slot/pid")" -f /dev/null
  done
  rm -rf "$TMP"
}
trap cleanup EXIT
request() {
  (cd "$REPO" &&
    env -u COMMANDECK_FOREGROUND CLAUDECODE=1 bash "$MERGE" u)
}
LOG=$COMMANDECK_SCRATCH/merge-u.log
request >/dev/null; check "the first request detaches" 0 $?
await_file "$TMP/first/pid" || exit 1
OUT=$(request); RC=$?
check "a second request while the first is queued is refused at once, saying so" "4 1" \
  "$RC $(grep -c 'already queued behind the running merge' <<<"$OUT")"
sleep 0.5 # a detached run the request did start reaches the nohup stub by now
check "the refused request wrote no log and started no detached run" "no no" \
  "$([ -e "$LOG" ] && echo yes || echo no) $([ -e "$TMP/second" ] && echo yes || echo no)"

touch "$TMP/first/go"
STATE=$REPO/.git/merge-unit-local.state
for ((i=0; i<200; i++)); do
  grep -qx 'stage=check' "$STATE" 2>/dev/null && break
  sleep 0.05
done
check "the first merge reaches its check" 1 "$(grep -cx 'stage=check' "$STATE")"
check "a request while the first merges is refused too" 4 "$(request >/dev/null; echo $?)"
check "the running merge's log keeps its STEP 1" 1 "$(grep -c '^STEP 1 preconditions:' "$LOG")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
