#!/usr/bin/env bash
# On 2026-09-19 a script from a closed main pane re-bound the run, every `check`
# main's waiter made came back consumer_fenced, and orca-wait.sh sent that to
# /dev/null and looped: 12 minutes deaf with three wakes queued. The
# rule under test: a fenced check re-binds once and the queued message still
# arrives; any other error is printed and ends the wait instead of spinning.
#
# orca-ide and systemctl are stubbed on PATH; the script is copied into a
# throwaway repo, the same convention as orca-wait-filter.test.sh.
set -euo pipefail

SOURCE=$(git rev-parse --show-toplevel)
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
fail() { echo "FAIL: $*" >&2; printf 'stdout:\n%s\nstderr:\n%s\n' "${OUT:-}" "$(cat "$SCRATCH/err" 2>/dev/null)" >&2; exit 1; }

REPO=$SCRATCH/repo
mkdir -p "$REPO/scripts" "$SCRATCH/bin" "$SCRATCH/ws"
git -C "$REPO" init -q
cp "$SOURCE/scripts/orca-wait.sh" "$SOURCE/scripts/paths.sh" "$SOURCE/scripts/project-main.sh" "$SOURCE/scripts/host-services.sh" "$REPO/scripts/"
mkdir -p "$REPO/hooks/lib"; cp "$SOURCE/hooks/lib/project.sh" "$REPO/hooks/lib/"
export COMMANDECK_HOST_OS=Linux  # the systemctl stubs are the service manager under test
printf '#!/usr/bin/env bash\nexit 0\n' > "$SCRATCH/bin/systemctl"

# The startup run-use is bind 1. MODE decides what `check` answers:
#   fence         JSON consumer_fenced until the pane is bound a second time
#   fence-stderr  the same refusal, as the plain message on stderr only
#   always-fenced consumer_fenced no matter how often the pane re-binds
#   other         a non-fence error
cat > "$SCRATCH/bin/orca-ide" <<'ORCA'
#!/usr/bin/env bash
case "$1 $2" in
  "orchestration run-use") echo bind >> "$ST/binds"; exit 0 ;;
  "orchestration task-list") echo '{"result":{"tasks":[]}}'; exit 0 ;;
  "orchestration gate-list") echo '{"result":{"gates":[]}}'; exit 0 ;;
  "terminal list") echo '{"result":{"terminals":[]}}'; exit 0 ;;
  "worktree ps") echo '{"result":{"worktrees":[]}}'; exit 0 ;;
  "orchestration check") echo "$*" >> "$ST/checks" ;;
  *) exit 0 ;;
esac
binds=$(wc -l < "$ST/binds" 2>/dev/null || echo 0)
case "$MODE" in
  fence) [ "$binds" -ge 2 ] || { echo '{"ok":false,"error":{"code":"consumer_fenced","message":"This coordinator terminal is no longer bound to Run run_test."}}'; exit 1; } ;;
  fence-stderr) [ "$binds" -ge 2 ] || { echo 'This coordinator terminal is no longer bound to Run run_test.' >&2; exit 1; } ;;
  always-fenced) echo '{"ok":false,"error":{"code":"consumer_fenced","message":"This coordinator terminal is bound to run_other, not run_test."}}'; exit 1 ;;
  other) echo '{"ok":false,"error":{"code":"runtime_unavailable","message":"Orca is not running"}}'; exit 1 ;;
esac
case " $* " in
  *" --ack "*) echo '{"ok":true,"result":{"deliveryId":null,"messages":[]}}' ;;
  *) echo '{"ok":true,"result":{"deliveryId":"del_1","messages":[{"id":"msg_1","type":"worker_done","from_handle":"term_worker","subject":"STOP class mismatch","body":"driver stopped"}]}}' ;;
esac
ORCA
chmod +x "$SCRATCH/bin/orca-ide" "$SCRATCH/bin/systemctl"

run() {  # run <mode> -- sets OUT and RC; stderr lands in $SCRATCH/err
  rm -f "$SCRATCH/binds" "$SCRATCH/checks"; mkdir -p "$SCRATCH/scratch-$1"
  RC=0
  OUT=$(cd "$REPO" && ST=$SCRATCH MODE=$1 PATH=$SCRATCH/bin:$PATH COMMANDECK_WORKSPACES=$SCRATCH/ws \
    COMMANDECK_SCRATCH=$SCRATCH/scratch-$1 HOME=$SCRATCH \
    timeout 30 bash scripts/orca-wait.sh --run run_test 2>"$SCRATCH/err") || RC=$?
}
binds() { wc -l < "$SCRATCH/binds"; }
rebind_lines() { grep -c 're-bound this pane to run_test' "$SCRATCH/err" || true; }

# 1. THE BUG. A fenced check re-binds once, says so once, and the message that
#    was queued behind the fence reaches main.
run fence
[ "$RC" = 0 ] || fail "a fenced check must end in the queued message, exit 0 (got $RC)"
case $OUT in *"STOP class mismatch"*) ;; *) fail "the message queued behind the fence was not printed" ;; esac
[ "$(binds)" = 2 ] || fail "expected the startup bind plus ONE re-bind, got $(binds)"
[ "$(rebind_lines)" = 1 ] || fail "the re-bind must be said exactly once on stderr, got $(rebind_lines)"

# 2. Orca's plain form puts the refusal on stderr with nothing on stdout; that
#    is a fence too, not an empty inbox.
run fence-stderr
[ "$RC" = 0 ] || fail "a stderr-only fence must re-bind and deliver, exit 0 (got $RC)"
case $OUT in *"STOP class mismatch"*) ;; *) fail "the stderr-only fence swallowed the queued message" ;; esac
[ "$(binds)" = 2 ] || fail "a stderr-only fence must re-bind once, got $(binds) binds"

# 3. Any other error is printed and ends the wait: retrying it forever is the
#    same deafness with a different code.
run other
[ "$RC" = 4 ] || fail "a non-fence error must end the wait with exit 4 (got $RC)"
grep -q 'runtime_unavailable' "$SCRATCH/err" || fail "the non-fence error code was swallowed"
[ "$(wc -l < "$SCRATCH/checks")" = 1 ] || fail "a non-fence error was retried ($(wc -l < "$SCRATCH/checks") checks)"
[ "$(binds)" = 1 ] || fail "a non-fence error must not re-bind the run"

# 4. A fence that survives the re-bind means something keeps taking the run.
#    One re-bind, then say so and stop, never a bind war in a tight loop.
run always-fenced
[ "$RC" = 4 ] || fail "a fence that survives the re-bind must end the wait with exit 4 (got $RC)"
[ "$(binds)" = 2 ] || fail "expected exactly one re-bind before giving up, got $(binds) binds"
grep -q 'check failed.*consumer_fenced' "$SCRATCH/err" || fail "the surviving fence was not printed"

echo "ok: orca-wait.sh re-bind -- 4 cases"
