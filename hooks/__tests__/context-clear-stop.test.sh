#!/usr/bin/env bash
# Self-test for context-clear-stop.sh's detached restart launch. Run directly.
#
# macOS has no setsid. The hook used to launch the helper with a bare setsid
# into /dev/null and mark the checkpoint restarted BEFORE the launch, so on the
# Mac the helper never ran and every later stop gave up as "already restarted".
# Pinned here: on a PATH without setsid the helper still starts; a restart whose
# checkpoint drops an open item, or that has no checkpoint, is blocked.
set -u

ROOT=$(git rev-parse --show-toplevel)
HOOK="$ROOT/hooks/context-clear-stop.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
mkdir -p "$BOX/bin" "$BOX/home/.claude/checkpoints" "$BOX/repo"
git -C "$BOX/repo" init -q
PSLUG=$(printf '%s' "$(git -C "$BOX/repo" rev-parse --show-toplevel)" | tr -c 'A-Za-z0-9' '-')  # the marker is per repo

# A PATH holding only what the hook and helper call, so setsid is absent on
# every host, the PC included.
for t in bash sh env jq git date stat dirname basename cat ps grep perl touch printf rm rmdir sleep head tr cut sed awk mkdir ls wc tail sort python3 cksum; do
  p=$(command -v "$t") && ln -s "$p" "$BOX/bin/$t"
done
[ ! -e "$BOX/bin/setsid" ] || { echo "FAIL setup: setsid leaked onto the test PATH"; exit 1; }

cat > "$BOX/bin/orca-ide" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  "terminal create") echo '{"result":{"terminal":{"handle":"new-pane"}}}' ;;
  "worktree ps") echo '{"result":{"worktrees":[]}}' ;;
  "terminal list") echo '{"result":{"terminals":[]}}' ;;
  "worktree list") echo '{"result":{"worktrees":[]}}' ;;
  *) echo '{"ok":true}' ;;
esac
STUB
chmod +x "$BOX/bin/orca-ide"

CPD="$BOX/home/.claude/checkpoints"
run_hook() { # $1 = helper path override (empty = the real helper)
  rm -f "$CPD"/sid.* "$BOX/calls"; : > "$BOX/calls"
  echo '# checkpoint' > "$CPD/sid.md"; touch "$CPD/sid.handoff"
  echo '{}' > "$BOX/transcript.jsonl"
  stop_hook "$@"
}
stop_hook() { # one stop of the same pane, the checkpoint files left as they are
  (cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/transcript.jsonl" \
    | env -i PATH="$BOX/bin" HOME="$BOX/home" CALLS="$BOX/calls" ORCA_TERMINAL_HANDLE=old-pane \
        COMMANDECK_RESTART_SETTLE_S=0 COMMANDECK_RESTART_TUI_FALLBACK_S=0 \
        COMMANDECK_SCRATCH="$BOX" COMMANDECK_DRIVERS=none.service \
        ${1:+COMMANDECK_RESTART_HELPER="$1"} ${2:+COMMANDECK_PARENT_ARGS="$2"} bash "$HOOK" >/dev/null 2>&1)
}
# Up to 30 s, returning as soon as the condition holds: a loaded chain host took
# longer than the old 5 s to start the detached helper, and a timeout is its own
# failure rather than an empty read further down.
wait_for() { for _ in $(seq 1 300); do eval "$1" && return 0; sleep 0.1; done; FAIL=$((FAIL+1)); echo "FAIL timed out waiting for: $1"; return 1; }
# The helper's LAST call. A case waits for it before the next case starts: a
# helper still running removes the next case's .handoff trigger (it spends the
# handoff once its pane is prompted), and the next stop then launches nothing.
INFLIGHT="$CPD/restart-inflight.old-pane"
helper_done='grep -q "^terminal close --terminal old-pane" "$BOX/calls" && [ ! -e "$INFLIGHT" ]'

run_hook ""
wait_for "$helper_done"
check "without setsid the detached helper still runs and opens a new pane" "yes" \
  "$(grep -q '^terminal create' "$BOX/calls" && echo yes || echo no)"
check "a started helper leaves the restarted marker" "yes" \
  "$([ -e "$CPD/sid.md.restarted" ] && echo yes || echo no)"
# /handoff: the owner sees the new main confirm it took over, or this pane says why it did not.
check "the new main's first line to the owner confirms the handoff and names the old pane" 1 \
  "$(grep '^terminal send --terminal new-pane' "$BOX/calls" | grep -c 'first line to the owner is: Handoff done: .*old pane old-pane closes now')"
prompt_line() { (cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","prompt":"hi"}' "$BOX/transcript.jsonl" \
  | env -i PATH="$BOX/bin" HOME="$BOX/home" ORCA_TERMINAL_HANDLE=old-pane bash "$ROOT/hooks/context-line.sh" 2>/dev/null); }
check "a spent handoff leaves no line at the next prompt" "" "$(prompt_line)"
touch "$CPD/sid.handoff"
echo "2026-10-14T10:00:00 restart: terminal create failed; old pane old-pane left up, next stop retries" >> "$CPD/clear-hook.log"
check "one that did not finish says so at the next prompt, with the helper's reason" 1 \
  "$(prompt_line | grep -c '^HANDOFF NOT DONE: this pane is still main\. .*terminal create failed; old pane old-pane left up')"
rm -f "$CPD/sid.handoff"

# Carry-over: a resumed main's next checkpoint must keep, or explicitly
# close, every open item of the checkpoint it resumed from. A restart that
# silently drops one loses that work for good, so it is refused BEFORE anything
# is published or launched, on every stop in the chain and on both triggers.
cat > "$BOX/stub-helper.sh" <<STUB
#!/usr/bin/env bash
touch "$BOX/launched"
STUB
cat > "$BOX/base.md" <<'MD'
# Checkpoint old -- 2026-10-03 09:00 ET

## Waiting on
- VERDICT: GO from term_rev1 -> run merge-unit-local.sh alpha

## Rulings this session not yet in memory or a rule file (list only what could not be saved)
- The owner: keep the 0.70 auto-tuning bar for
  widget sorting until the fix lands

## Queue (in order)
1. unit-gamma, blocked on the alpha merge

## Todo list (the owner's on-screen checklist; the resumed main rebuilds it first)
- [x] finished step one
- [>] rebase delta onto main
- [ ] push after certification

## Gotchas learned this session
- none
MD
W='VERDICT: GO from term_rev1 -> run merge-unit-local.sh alpha'
R='The owner: keep the 0.70 auto-tuning bar for widget sorting until the fix lands'
Q='unit-gamma, blocked on the alpha merge'
T1='rebase delta onto main'
T2='push after certification'
carry() { # new checkpoint file [stop_hook_active] [line|handoff] -> blocked | published | neither
  rm -f "$CPD"/sid.* "$CPD/resume-pending.$PSLUG" "$BOX/launched"
  cp "${BASE:-$BOX/base.md}" "$CPD/old.md"; cp "$1" "$CPD/sid.md"
  [ "${ANC-x}" = none ] || echo "${ANC:-$CPD/old.md}" > "$CPD/sid.resumed-from"
  if [ "${3:-handoff}" = line ]; then
    printf '%s\n' '{"message":{"usage":{"cache_read_input_tokens":500,"input_tokens":1}}}' > "$BOX/transcript.jsonl"
  else
    echo '{}' > "$BOX/transcript.jsonl"; touch "$CPD/sid.handoff"
  fi
  (cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":%s}' "$BOX/transcript.jsonl" "${2:-false}" \
    | env -i PATH="$BOX/bin" HOME="$BOX/home" CALLS="$BOX/calls" ORCA_TERMINAL_HANDLE=old-pane \
        COMMANDECK_CLEAR_LINE="$([ "${3:-}" = line ] && echo 10 || echo 999999999)" \
        COMMANDECK_RESTART_HELPER="$BOX/stub-helper.sh" bash "$HOOK" > "$BOX/carry.out" 2>/dev/null)
  if jq -e '.decision == "block"' "$BOX/carry.out" >/dev/null 2>&1; then
    [ -e "$CPD/resume-pending.$PSLUG" ] || [ -e "$CPD/sid.md.restarted" ] && { echo "blocked-but-published"; return; }
    echo blocked
  elif [ -e "$CPD/resume-pending.$PSLUG" ]; then echo published
  else echo neither; fi
}
names() { jq -r '.reason' "$BOX/carry.out" 2>/dev/null | grep -qF -- "$1" && echo yes || echo no; }
variant() { grep -vF -- "$1" "$BOX/base.md" > "$BOX/v.md"; echo "$BOX/v.md"; }

check "carrying every item unchanged restarts" published "$(carry "$BOX/base.md")"
# The launch is detached: wait for it, or it lands inside the next case.
wait_for '[ -e "$BOX/launched" ]'
check "dropping the wrapped ruling blocks the restart" blocked "$(carry "$(grep -v 'auto-tuning bar' "$BOX/base.md" | grep -v 'widget sorting until' > "$BOX/v.md"; echo "$BOX/v.md")")"
check "and the block names the whole wrapped item" yes "$(names "$R")"
check "and the baseline it compared against" yes "$(names "$CPD/old.md")"
check "and nothing was launched" no "$([ -e "$BOX/launched" ] && echo yes || echo no)"

# NO FRESH CHECKPOINT: the refusal carries the template's headings, so
# the agent writes the checkpoint in one Write instead of first Reading the
# 4.5 KB template (3.5 turns per block before this).
rm -f "$CPD"/sid.* "$CPD/resume-pending.$PSLUG"
printf '%s\n' '{"message":{"usage":{"cache_read_input_tokens":500,"input_tokens":1}}}' > "$BOX/transcript.jsonl"
(cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/transcript.jsonl" \
  | env -i PATH="$BOX/bin" HOME="$BOX/home" CALLS="$BOX/calls" ORCA_TERMINAL_HANDLE=old-pane COMMANDECK_CLEAR_LINE=10 \
      COMMANDECK_RESTART_HELPER="$BOX/stub-helper.sh" bash "$HOOK" > "$BOX/carry.out" 2>/dev/null)
check "no checkpoint: the stop is blocked" block "$(jq -r .decision "$BOX/carry.out" 2>/dev/null)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
