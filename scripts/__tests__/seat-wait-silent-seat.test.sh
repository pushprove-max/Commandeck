#!/usr/bin/env bash
# A silent read-only review seat is closed and relaunched once, then the wait
# ends. Four brief-review seats sat open 402-412 minutes on 2026-09-14
# against a 6-7 minute median and nothing closed them. The fake pane here
# shows the same screen forever under an animated status line (glyph, verb and
# clock all change on every read) -- so it
# must trigger exactly one relaunch, then a failed wait carrying its last
# lines, which the driver hands to main. A writable seat is never relaunched.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# seat.sh takes its root from `git rev-parse`, so the stubs only get picked up
# from inside a real repo.
git init -q "$TMP/repo"
mkdir -p "$TMP/repo/scripts" "$TMP/repo/config" "$TMP/ws/fake-unit" "$TMP/bin" "$TMP/scratch"
cp "$REAL/scripts/seat.sh" "$REAL/scripts/paths.sh" "$REAL/scripts/project-main.sh" "$REAL/scripts/requirements.sh" "$REAL/scripts/codex-helpers.sh" "$REAL/scripts/read-verdict.sh" "$REAL/scripts/orca-task-create.sh" "$TMP/repo/scripts/"
jq -f "$REAL/scripts/__tests__/fixtures/routing-seats.jq" "$REAL/config/routing.json" > "$TMP/repo/config/routing.json"
for s in run-bound.sh worktree-setup.sh; do
  printf '#!/bin/sh\nexit 0\n' > "$TMP/repo/scripts/$s"; chmod +x "$TMP/repo/scripts/$s"
done

# Each `terminal create` hands out the next handle; `terminal list` shows every
# handle ever created, so the dead-pane check never fires; the screen is a
# stuck spinner whose seconds change on every read.
cat > "$TMP/bin/orca-ide" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "${1:-} ${2:-}" in
  "terminal create") n=$(( $(cat "$TMP/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$TMP/n"
    echo "term_$n" >> "$TMP/handles"; echo "{\"handle\":\"term_$n\"}" ;;
  "terminal list") case " $* " in *" --worktree "*) echo '{"result":{"terminals":[]}}' ;; *) cat "$TMP/handles" 2>/dev/null ;; esac ;;
  "worktree ps") echo '{"result":{"worktrees":[]}}' ;;
  "orchestration task-create") echo "{\"id\":\"task_$(cat "$TMP/n")\"}" ;;
  "orchestration dispatch") echo '{"ok":true}' ;;
  # Real Orca refuses the update while the task's supervised dispatch is active.
  "orchestration task-update") if [ -e "$TMP/abandoned" ]; then echo '{"ok":true}'
    else echo '{"ok":false,"error":{"code":"task_not_startable"}}'; fi ;;
  "orchestration dispatch-show") echo '{"result":{"dispatch":{"id":"ctx_silent"}}}' ;;
  "orchestration worker-abandon") : > "$TMP/abandoned"; echo '{"ok":true}' ;;
  "terminal read")
    # RELOG: once the seat has been relaunched, its replacement finishes in its
    # session log only, under the tag the relaunch wrote to the record.
    R=$COMMANDECK_SCRATCH/seat-fake-unit-luna-reviewer.txt; L=$HOME/.codex/sessions/relaunched.jsonl
    if [ -n "${RELOG:-}" ] && grep -qx 'relaunched=1' "$R" 2>/dev/null && [ ! -e "$L" ]; then
      mkdir -p "${L%/*}"; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      { jq -cn --arg t "$now" --arg cwd "$COMMANDECK_WORKSPACES/fake-unit" '{timestamp: $t, type: "session_meta", payload: {type: "session_meta", cwd: $cwd}}'
        jq -cn --arg t "$now" --arg x "Your task spec is the file $TMP/spec.md. Seat tag $(sed -n 's/^tag=//p' "$R")." \
          '{timestamp: $t, type: "response_item", payload: {type: "message", role: "user", content: [{type: "input_text", text: $x}]}}'
        jq -cn --arg t "$now" '{timestamp: $t, type: "event_msg", payload: {type: "task_started", turn_id: "t1"}}'
        jq -cn --arg t "$now" '{timestamp: $t, type: "event_msg", payload: {type: "task_complete", turn_id: "t1", last_agent_message: "Reviewed.\nBRIEF-REVIEW-DONE"}}'
      } > "$L"
    fi
    [ -z "${BLANK:-}" ] || { echo '{"result":{"terminal":{"tail":[]}}}'; exit 0; }
    [ -z "${STATUSONLY:-}" ] || { echo '{"result":{"terminal":{"tail":["✻ Working… (1m 2s · esc to interrupt)"]}}}'; exit 0; }
    g=('✻' '✢' '·' '✶'); v=(Cogitating Pondering Working Musing)
    printf '{"result":{"terminal":{"tail":["reading the brief","%s %s… (%sm %ss · esc to interrupt)"]}}}\n' \
      "${g[RANDOM % 4]}" "${v[RANDOM % 4]}" "$RANDOM" "$RANDOM" ;;
  *) echo '{"ok":true}' ;;
esac
STUB
chmod +x "$TMP/bin/orca-ide"
echo 'Review the brief. End with BRIEF-REVIEW-DONE.' > "$TMP/spec.md"
export PATH=$TMP/bin:$PATH TMP CALLS=$TMP/calls HOME=$TMP/home
export COMMANDECK_WORKSPACES=$TMP/ws COMMANDECK_SCRATCH=$TMP/scratch COMMANDECK_SEAT_SETTLE_SECONDS=0
export COMMANDECK_SEAT_SILENT_SECONDS=2 COMMANDECK_LOOP_POLL_SECONDS=1 COMMANDECK_ROUTING_LOG=$TMP/routing-log
seat() { ( cd "$TMP/repo" && COMMANDECK_DRIVER=1 timeout 60 bash scripts/seat.sh "$@" ) 2>&1; }

# 1. A read-only brief reviewer: one relaunch, then the wait fails.
seat launch luna-reviewer fake-unit "$TMP/spec.md" >/dev/null || fail "the fixture seat did not launch"
: > "$CALLS"
OUT=$(seat wait luna-reviewer fake-unit --marker BRIEF-REVIEW-DONE --timeout-s 40); rc=$?
[ "$rc" -eq 1 ] || fail "a silent seat's wait did not fail after the relaunch (rc $rc): $OUT"
[ "$(grep -c '^terminal create' "$CALLS")" -eq 1 ] || fail "expected exactly one relaunch; got $(grep -c '^terminal create' "$CALLS")"
grep -q '^terminal close --terminal term_1' "$CALLS" || fail "the silent pane was not closed"
grep -q '^orchestration task-update --id task_1 --status failed' "$CALLS" || fail "the silent pane's task was not closed"
grep -q '^orchestration worker-abandon --dispatch ctx_silent' "$CALLS" \
  || fail "the silent pane's active dispatch was not ended, so Orca refused the task close"
grep -q '^handle=term_2$' "$TMP/scratch/seat-fake-unit-luna-reviewer.txt" || fail "the record does not follow the relaunched pane"
grep -q 'relaunched pane term_2 showed nothing new for 2s either' <<<"$OUT" || fail "no second-timeout line: $OUT"
grep -q '^reading the brief$' <<<"$OUT" || fail "the wait did not carry the pane's last lines: $OUT"
[ "$(grep -c '^terminal close' "$CALLS")" -eq 1 ] || fail "the relaunched pane was closed too; main must be able to read it"

# 2. A fresh wait on an already-relaunched seat does not relaunch again.
: > "$CALLS"
seat wait luna-reviewer fake-unit --marker BRIEF-REVIEW-DONE --timeout-s 40 >/dev/null
grep -q '^terminal create' "$CALLS" && fail "a seat relaunched once was relaunched again"

# 3. A pane whose screen reads back blank is silent too, and gets its relaunch.
rm -f "$TMP/scratch/seat-fake-unit-luna-reviewer.txt"
seat launch luna-reviewer fake-unit "$TMP/spec.md" >/dev/null || fail "the blank fixture seat did not launch"
: > "$CALLS"
BLANK=1 seat wait luna-reviewer fake-unit --marker BRIEF-REVIEW-DONE --timeout-s 40 >/dev/null
[ "$(grep -c '^terminal create' "$CALLS")" -eq 1 ] || fail "a blank silent pane was not relaunched once"

# 3a. The replacement's session is read under the replacement's own tag: its
#    finish, visible only in its session log, releases the wait.
rm -f "$TMP/scratch/seat-fake-unit-luna-reviewer.txt"
seat launch luna-reviewer fake-unit "$TMP/spec.md" >/dev/null || fail "the relaunch-log fixture seat did not launch"
OUT=$(BLANK=1 RELOG=1 seat wait luna-reviewer fake-unit --marker BRIEF-REVIEW-DONE --timeout-s 40); rc=$?
[ "$rc" -eq 0 ] || fail "a relaunched seat that finished in its session log did not release the wait (rc $rc): $OUT"
rm -f "$TMP/home/.codex/sessions/relaunched.jsonl"

# 3b. So is a pane showing nothing but its status line: every line is filtered
#    out, and the wait used to die on the filter's exit code before it judged anything.
rm -f "$TMP/scratch/seat-fake-unit-luna-reviewer.txt"
seat launch luna-reviewer fake-unit "$TMP/spec.md" >/dev/null || fail "the status-only fixture seat did not launch"
: > "$CALLS"
STATUSONLY=1 seat wait luna-reviewer fake-unit --marker BRIEF-REVIEW-DONE --timeout-s 40 >/dev/null
[ "$(grep -c '^terminal create' "$CALLS")" -eq 1 ] || fail "a pane showing only its status line was not relaunched once"

# 4. A writable seat (companion writes the brief) is never relaunched: its
#    wait runs to its own timeout.
seat launch companion fake-unit "$TMP/spec.md" >/dev/null || fail "the writable fixture seat did not launch"
: > "$CALLS"
seat wait companion fake-unit --marker PLAN-DONE --timeout-s 6 >/dev/null
grep -q '^terminal create' "$CALLS" && fail "a writable seat was relaunched"

echo "PASS seat-wait-silent-seat: 17 assertions"
