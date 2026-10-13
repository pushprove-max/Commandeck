#!/usr/bin/env bash
# Self-test for context-clear-restart.sh. Run directly.
#
# The old pane is the only thing holding main's context, so the thing worth
# pinning is that it survives every failure: a refused resume prompt and a failed
# create must both leave it up.
set -u

ROOT=$(git rev-parse --show-toplevel)
SCRIPT="$ROOT/hooks/lib/context-clear-restart.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
mkdir -p "$BOX/bin"

# $SEND_OK and $CREATE_OK pick which failure the stub reproduces (CREATE_OK=late:
# create answers no handle but Orca opens the pane anyway); every call is
# appended to $CALLS so the test can prove the close never ran. `terminal list`
# prints $LIST_PRE until create has been called, then $LIST_POST.
cat > "$BOX/bin/orca-ide" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  "terminal create")
    [ "${CREATE_OK:-1}" = late ] && { echo '{"ok":false,"error":{"code":"timeout"}}'; exit 1; }
    [ "${CREATE_OK:-1}" = 1 ] || { echo '{"ok":false,"error":{"code":"create-refused"}}'; exit 1; }
    echo '{"result":{"terminal":{"handle":"new-pane"}}}' ;;
  "terminal wait")  echo '{"ok":true}' ;;
  "terminal send")
    [ "${SEND_OK:-1}" = 1 ] || { echo '{"ok":false,"error":{"code":"input-refused"}}'; exit 1; }
    echo '{"ok":true}' ;;
  "terminal close") echo '{"ok":true}' ;;
  # The done-pane sweep's reads; $SWEEP_OK=0 makes the sweep fail.
  "worktree ps")
    [ "${SWEEP_OK:-1}" = 1 ] || { echo 'orca unreachable' >&2; exit 1; }
    echo '{"result":{"worktrees":[]}}' ;;
  "terminal list")
    [ "${LIST_PRE:-}" = fail ] && ! grep -q '^terminal create' "$CALLS" && { echo 'orca unreachable' >&2; exit 1; }
    if grep -q '^terminal create' "$CALLS"; then l=${LIST_POST:-}; else l=${LIST_PRE:-}; fi
    [ -n "$l" ] && echo "$l" || echo '{"result":{"terminals":[]}}' ;;
  "worktree list") echo '{"result":{"worktrees":[]}}' ;;
  *) echo '{"ok":true}' ;;
esac
STUB
chmod +x "$BOX/bin/orca-ide"

run() {
  CALLS="$BOX/calls"; : > "$CALLS"; : > "$BOX/log"
  PATH="$BOX/bin:$PATH" CALLS="$CALLS" SEND_OK="$1" CREATE_OK="$2" SWEEP_OK="${3:-1}" \
    COMMANDECK_RESTART_SETTLE_S=0 COMMANDECK_RESTART_TUI_FALLBACK_S=0 \
    COMMANDECK_RESTART_ADOPT_TRIES=3 COMMANDECK_RESTART_ADOPT_EVERY_S=0 \
    COMMANDECK_MAIN="$BOX/main" LIST_PRE="${LIST_PRE:-}" LIST_POST="${LIST_POST:-}" \
    COMMANDECK_SCRATCH="$BOX" COMMANDECK_DRIVERS=none.service \
    bash "$SCRIPT" old-pane "$BOX/checkpoint.md" "claude" "$BOX/log"
  echo "$?"
}

touch "$BOX/checkpoint.handoff"
rc=$(run 1 1)
check "a accepted resume prompt exits 0" 0 "$rc"
check "a accepted resume prompt consumes the /handoff request" "no" \
  "$([ -e "$BOX/checkpoint.handoff" ] && echo yes || echo no)"
# The owner names main main (2026-10-09); every restarted main pane must carry that title.
check "the new main pane is titled main" "yes" \
  "$(grep -q '^terminal create .*--title Main Orchestrator' "$BOX/calls" && echo yes || echo no)"
check "a accepted resume prompt closes the old pane" "yes" \
  "$(grep -q '^terminal close' "$BOX/calls" && echo yes || echo no)"
check "the success path logs the close" "yes" \
  "$(grep -q 'closing old-pane' "$BOX/log" && echo yes || echo no)"

check "the done-pane sweep runs after the old-pane close (the old main is gone first)" "yes" \
  "$(awk '/^terminal close/ {c=NR} /^worktree ps/ {p=NR} END {print (c && p > c) ? "yes" : "no"}' "$BOX/calls")"
check "the sweep's result is logged" "yes" \
  "$(grep -q 'done-pane sweep: nothing to close' "$BOX/log" && echo yes || echo no)"

rc=$(run 1 1 0)
check "a failing sweep still leaves the handoff successful" 0 "$rc"
check "a failing sweep does not undo the old-pane close" "yes" \
  "$(grep -q '^terminal close' "$BOX/calls" && echo yes || echo no)"
check "a failing sweep is logged" "yes" \
  "$(grep -q 'done-pane sweep FAILED, handoff unaffected' "$BOX/log" && echo yes || echo no)"

touch "$BOX/checkpoint.md.restarted"
rc=$(run 0 1)
check "a refused resume prompt exits non-zero" 1 "$rc"
check "a refused resume prompt NEVER closes the old pane" "no" \
  "$(grep -q '^terminal close --terminal old-pane' "$BOX/calls" && echo yes || echo no)"
# Left open, the unprompted pane is a second main beside the one the retry opens.
check "a refused resume prompt closes the unprompted new pane" "yes" \
  "$(grep -q '^terminal close --terminal new-pane' "$BOX/calls" && echo yes || echo no)"
check "a refused resume prompt clears the restarted marker so the next stop retries" "no" \
  "$([ -e "$BOX/checkpoint.md.restarted" ] && echo yes || echo no)"
check "a refused resume prompt says the old pane is left up" "yes" \
  "$(grep -q 'LEFT UP' "$BOX/log" && echo yes || echo no)"
check "a refused resume prompt records the refusal reason" "yes" \
  "$(grep -q 'input-refused' "$BOX/log" && echo yes || echo no)"
check "a refused resume prompt does not claim the restart succeeded" "no" \
  "$(grep -q 'closing old-pane' "$BOX/log" && echo yes || echo no)"

touch "$BOX/checkpoint.md.restarted" "$BOX/checkpoint.handoff"
rc=$(run 1 0)
check "a failed create exits non-zero" 1 "$rc"
# This helper marks the checkpoint restarted as soon as it runs. Left
# behind after a failed create, the marker made every later stop claim "already
# restarted", so main never restarted (2026-09-23, Orca down before a WSL reboot).
check "a failed create clears the restarted marker so the next stop retries" "no" \
  "$([ -e "$BOX/checkpoint.md.restarted" ] && echo yes || echo no)"
# Below the line the /handoff request is the only trigger, so the retry needs it.
check "a failed create keeps the /handoff request so the next stop retries" "yes" \
  "$([ -e "$BOX/checkpoint.handoff" ] && echo yes || echo no)"
check "a failed create NEVER closes the old pane" "no" \
  "$(grep -q '^terminal close' "$BOX/calls" && echo yes || echo no)"
check "a failed create says the old pane is left up" "yes" \
  "$(grep -q 'left up' "$BOX/log" && echo yes || echo no)"

# 2026-09-26: create answered no handle after ~11 s, Orca opened the pane ~14 s
# later, and the next stop's retry opened a second main: two mains on one run.
# Orca lists the LIVE title, which Claude rewrites as it boots, so a booted
# replacement no longer carries the title create gave it.
bob() { printf '{"result":{"terminals":[{"handle":"%s","title":"✳ Claude Code","worktreePath":"%s"}]}}' "$1" "$BOX/main"; }
touch "$BOX/checkpoint.md.restarted"
rc=$(LIST_POST=$(bob late-pane) run 1 late)
check "a late-opened main pane is adopted (exit 0)" 0 "$rc"
check "the resume prompt goes to the late pane" "yes" \
  "$(grep -q '^terminal send --terminal late-pane' "$BOX/calls" && echo yes || echo no)"
check "adopting the late pane closes the old pane" "yes" \
  "$(grep -q '^terminal close --terminal old-pane' "$BOX/calls" && echo yes || echo no)"
check "adopting the late pane keeps the restarted marker (no second main)" "yes" \
  "$([ -e "$BOX/checkpoint.md.restarted" ] && echo yes || echo no)"
check "the adoption is logged" "yes" \
  "$(grep -q 'adopted late pane late-pane' "$BOX/log" && echo yes || echo no)"
check "the raw create output is logged" "yes" \
  "$(grep -q '"code":"timeout"' "$BOX/log" && echo yes || echo no)"

# A main already up before create is a leftover, never the pane create opened.
touch "$BOX/checkpoint.md.restarted"
rc=$(LIST_PRE=$(bob stale-pane) LIST_POST=$(bob stale-pane) run 1 late)
check "a main pane listed before create is not adopted (exit 1)" 1 "$rc"
check "a pre-existing main pane never gets the resume prompt" "no" \
  "$(grep -q '^terminal send' "$BOX/calls" && echo yes || echo no)"
check "no adoption leaves the old pane up" "no" \
  "$(grep -q '^terminal close' "$BOX/calls" && echo yes || echo no)"
check "no adoption clears the restarted marker so the next stop retries" "no" \
  "$([ -e "$BOX/checkpoint.md.restarted" ] && echo yes || echo no)"

# No pre-create snapshot means no way to tell a leftover main from ours.
rc=$(LIST_PRE=fail LIST_POST=$(bob maybe-stale) run 1 late)
check "a failed pre-create list disables adoption (exit 1)" 1 "$rc"
check "a failed pre-create list never prompts an unproven main" "no" \
  "$(grep -q '^terminal send' "$BOX/calls" && echo yes || echo no)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
