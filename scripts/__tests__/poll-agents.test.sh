#!/usr/bin/env bash
# Self-test for poll-agents.sh. Run: bash scripts/run-shell-tests.sh scripts/__tests__/poll-agents.test.sh
#
# Why each case matters: the drain reads each worker report's task id out of its payload, and prints the report only
# while that task is open. Orca 1.4.246 prints a concise check with no payload string unless --full is given, so every
# report drained as taskless and vanished. A concise reply must stop the script loud, with the consumed rows on stderr.
# `orca-ide` is a stub first on PATH, answering from the captured 1.4.246 views.
set -u
SOURCE=$(git rev-parse --show-toplevel)
SCRIPT=$SOURCE/scripts/poll-agents.sh
export ORCA_VIEWS=$SOURCE/scripts/__tests__/fixtures/orca-1.4.246-views.json
BOX=$(mktemp -d "${TMPDIR:-/tmp}/poll-agents-test.XXXXXX")
trap 'rm -rf "$BOX"' EXIT
PASS=0 FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi
}
mkdir -p "$BOX/bin" "$BOX/home" "$BOX/scratch"
cat > "$BOX/bin/orca-ide" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$BOX/calls"
if [ "${FAKE_ORCA_CONCISE:-0}" = 1 ] || [[ " $* " != *" --full "* ]]; then case "$1 $2" in
  "orchestration check") jq -c '.check.concise' "$ORCA_VIEWS"; exit 0 ;;
esac; fi
case "$1 $2" in
  "orchestration task-list") echo '{"ok":true,"result":{"tasks":[{"id":"task_probe","status":"dispatched"}]}}' ;;
  "orchestration check") jq -c '.check.full' "$ORCA_VIEWS" ;;
  "terminal list") echo '{"result":{"terminals":[]}}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$BOX/bin/orca-ide"
run() { env BOX="$BOX" PATH="$BOX/bin:$PATH" HOME="$BOX/home" COMMANDECK_SCRATCH="$BOX/scratch" "$@" bash "$SCRIPT" >"$BOX/out" 2>"$BOX/err"; echo $? > "$BOX/rc"; }

# Bug caught: a check read without --full has no payload string, so the report's task id was lost and the report vanished.
: > "$BOX/calls"
run
check "drain reads full payload task ids" "0 1 1" \
  "$(cat "$BOX/rc") $(grep -c '^ *\[task_probe\] probe' "$BOX/out") $(grep -c '^orchestration check --full' "$BOX/calls")"

# Bug caught: a concise batch drained as taskless and exited 0 with the consumed report unmentioned.
run FAKE_ORCA_CONCISE=1
check "concise check exits 2 loud" "2 1 1" \
  "$(cat "$BOX/rc") $(grep -c 'ORCA CONCISE VIEW' "$BOX/err") $(grep -c 'consumed: .*: probe' "$BOX/err")"

# A trailing --save with no folder made `shift 2` fail and shift nothing: the argument loop spun forever.
check "a trailing --save with no folder exits 2" 2 "$(timeout 5 bash "$SCRIPT" --save >/dev/null 2>&1; echo $?)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
