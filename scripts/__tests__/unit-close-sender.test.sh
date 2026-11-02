#!/usr/bin/env bash
# unit-close-sender.test.sh (#567): a task-update from a pane Orca cannot attribute answers no_active_sender_terminal.
# pp_task_close then retries the update once with --from <the sender pp_sender names>, so a unit's close from a service
# or a bare shell still lands. What this pins: the retry carries the sender and closes the task; with no sender handle
# (no pane, no main seat, no live coordinator) the close is not retried and fails loud; a close Orca accepts at once
# is sent once with no --from. orca-ide is a stub first on PATH; the shared stub in unit-close.test.sh is not used,
# as it never refuses an update.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }

CALLS=$T/calls M=$T/main
mkdir -p "$T/bin" "$M/.claude" "$T/home" "$T/scratch"
git init -q -b main "$M"
# task-update answers no_active_sender_terminal until it is sent with --from (NOFROM=1: it never accepts one).
cat > "$T/bin/orca-ide" <<'EOS'
#!/usr/bin/env bash
echo "$*" >> "$CALLS"
case "$1 $2" in
  "orchestration task-update")
    if [[ " $* " == *" --from "* ]] && [ "${NOFROM:-}" != 1 ]; then echo '{"ok":true}'
    elif [ "${ACCEPT:-}" = 1 ]; then echo '{"ok":true}'
    else echo '{"ok":false,"error":{"code":"no_active_sender_terminal","message":"no sender"}}'; fi ;;
  "orchestration run-list") echo '{"result":{"runs":[]}}' ;;
  "terminal list") echo '{"result":{"terminals":[]}}' ;;
esac
exit 0
EOS
chmod +x "$T/bin/orca-ide"
export PATH=$T/bin:$PATH CALLS HOME=$T/home COMMANDECK_MAIN=$M COMMANDECK_SCRATCH=$T/scratch COMMANDECK_RUN=run_t
unset CLAUDE_PROJECT_DIR ORCA_TERMINAL_HANDLE
# close <env...> -- pp_task_close for task_a as a script that sources paths.sh; sets RC, the call log and stderr.
close() { : > "$CALLS"; RC=0; env "$@" bash -c '. "$1/scripts/paths.sh"; pp_task_close task_a completed' _ "$REAL" > "$T/out" 2> "$T/err" || RC=$?; }
updates() { grep -c 'orchestration task-update' "$CALLS"; }

close ORCA_TERMINAL_HANDLE=term_x
check "a no-sender close is retried once with --from" "0 2 1 0" \
  "$RC $(updates) $(grep -c 'task-update .*--from term_x' "$CALLS") $(sed -n '1p' "$CALLS" | grep -c -- '--from')"

close NOFROM=1 ORCA_TERMINAL_HANDLE=term_x
check "a retry that is refused again is not repeated and fails loud" "1 2 1" \
  "$RC $(updates) $(grep -c 'no_active_sender_terminal' "$T/err")"

close X=1
check "with no sender handle the close is not retried" "1 1 1" \
  "$RC $(updates) $(grep -c 'no_active_sender_terminal' "$T/err")"

close ACCEPT=1 ORCA_TERMINAL_HANDLE=term_x
check "a close Orca accepts at once is sent once with no --from" "0 1 0" \
  "$RC $(updates) $(grep -c -- '--from' "$CALLS")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
