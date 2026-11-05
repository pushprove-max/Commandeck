#!/usr/bin/env bash
# covers: hooks/context-clear-stop.sh
# Issue 615: main ran past its restart line and nothing said why. When the hook cannot read main's context size, it
# must say so in one line, on stderr and in clear-hook.log, not stop silently: a silent stop looks like "below the line".
# Another session in main's checkout stays silent, as before. Its own file: context-clear-stop.test.sh runs near the
# 500-line cap.
set -u
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
HOOK="$(cd "$(dirname "$0")/.." && pwd)/context-clear-stop.sh"
mkdir -p "$BOX/bin" "$BOX/home/.claude/checkpoints" "$BOX/repo"
git -C "$BOX/repo" init -q
for t in bash sh env jq git date stat dirname basename cat ps grep perl touch printf rm rmdir sleep head tr cut sed awk mkdir ls wc tail sort python3 cksum mv paste timeout iconv comm; do
  p=$(command -v "$t") && ln -s "$p" "$BOX/bin/$t"
done
# Orca names run_a as the current run and <coordinator file> as its coordinator.
cat > "$BOX/bin/orca-ide" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "orchestration run-current") echo '{"result":{"run":{"id":"run_a"}}}' ;;
  "orchestration run-list") printf '{"result":{"runs":[{"id":"run_a","coordinator_handle":"%s"}]}}\n' "\$(cat "$BOX/coordinator")" ;;
  *) echo '{"ok":true}' ;;
esac
STUB
chmod +x "$BOX/bin/orca-ide"
LOG="$BOX/home/.claude/checkpoints/clear-hook.log"
# A transcript with no usage row: context_size returns 1.
echo '{}' > "$BOX/transcript.jsonl"
unreadable() { # <coordinator>: "<stderr lines> <log lines>" naming an unreadable context size, for one stop of old-pane
  echo "$1" > "$BOX/coordinator"; : > "$LOG"
  local err
  err=$(cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/transcript.jsonl" \
    | env -i PATH="$BOX/bin" HOME="$BOX/home" ORCA_TERMINAL_HANDLE=old-pane COMMANDECK_SCRATCH="$BOX" bash "$HOOK" 2>&1 >/dev/null)
  echo "$(grep -c 'context size cannot be read' <<<"$err") $(grep -c 'context size cannot be read' "$LOG")"
}

check "an unreadable context size on main says why in one line" "1 1" "$(unreadable old-pane)"
check "an unreadable context size in another session of main's checkout says nothing" "0 0" "$(unreadable other-pane)"

# Issue 615: a session past the line, with a fresh filled checkpoint and nothing holding it, must start the restart (the
# helper is a stub that leaves a marker), and a hold must leave one line saying why: owner and relay see it, not just stderr.
CPD="$BOX/home/.claude/checkpoints"
cat > "$BOX/helper.sh" <<STUB
#!/usr/bin/env bash
echo "\$2" > "$BOX/restarted"
STUB
echo '{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":208000,"cache_creation_input_tokens":800,"output_tokens":0}}}' > "$BOX/over.jsonl"
past_line() { # <stderr file>: one stop of old-pane (main) at 208.8K, past the 200K line, checkpoint fresh
  echo old-pane > "$BOX/coordinator"; : > "$LOG"; rm -f "$BOX/restarted" "$CPD"/sid.md* "$CPD"/restart-inflight.*
  printf '# Checkpoint\n\nGoal: ship the cut\n' > "$CPD/sid.md"
  (cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/over.jsonl" \
    | env -i PATH="$BOX/bin" HOME="$BOX/home" ORCA_TERMINAL_HANDLE=old-pane COMMANDECK_SCRATCH="$BOX" COMMANDECK_CLEAR_LINE=200000 \
        COMMANDECK_RESTART_HELPER="$BOX/helper.sh" timeout 20 bash "$HOOK" 2>"$1" >/dev/null)
}
past_line "$BOX/err1"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$BOX/restarted" ] && break; sleep 0.5; done
check "session past the line restarts" "$CPD/sid.md" "$(cat "$BOX/restarted" 2>/dev/null)"

# Held: this checkpoint was already restarted for (a pinned tab), so no new pane opens. One HELD line, naming the
# checkpoint, the session and the reason, lands in the log; the same reason goes to stderr.
held_run() {
  past_line "$BOX/err2" # starts the stub helper once; the marker below then makes the next stop a hold
  sleep 1; rm -f "$BOX/restarted"; rmdir "$CPD"/restart-inflight.* 2>/dev/null; : > "$LOG"
  cksum < "$CPD/sid.md" > "$CPD/sid.md.restarted"
  (cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/over.jsonl" \
    | env -i PATH="$BOX/bin" HOME="$BOX/home" ORCA_TERMINAL_HANDLE=old-pane COMMANDECK_SCRATCH="$BOX" COMMANDECK_CLEAR_LINE=200000 \
        COMMANDECK_RESTART_HELPER="$BOX/helper.sh" timeout 20 bash "$HOOK" 2>"$BOX/err3" >/dev/null)
  echo "$(grep -c ' restart: HELD: cp=sid.md session=sid cwd=.*: ' "$LOG") $(grep -c 'already restarted' "$BOX/err3")"
}
check "held restart logs one why line" "1 1" "$(held_run)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
