#!/usr/bin/env bash
# Self-test for context-clear-stop.sh's hold on running background agents
#. Run directly.
#
# In-harness background agents live inside main's pane, so the restart kills
# them: on 2026-10-08 it killed 2 of 42 helpers mid-run and both were paid for
# twice. Pinned here: a launched agent with no notification holds the restart,
# the hold ends once every agent has notified, and past the ceiling a hung
# agent no longer holds main but is named in the log.
set -u

ROOT=$(git rev-parse --show-toplevel)
HOOK="$ROOT/hooks/context-clear-stop.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
mkdir -p "$BOX/bin" "$BOX/home/.claude/checkpoints" "$BOX/repo"
git -C "$BOX/repo" init -q
PSLUG=$(printf '%s' "$(git -C "$BOX/repo" rev-parse --show-toplevel)" | tr -c 'A-Za-z0-9' '-')  # the marker is per repo
printf '#!/usr/bin/env bash\necho "{\\"ok\\":true}"\n' > "$BOX/bin/orca-ide"
printf '#!/usr/bin/env bash\ntouch "%s/launched"\n' "$BOX" > "$BOX/helper.sh"
chmod +x "$BOX/bin/orca-ide"
CPD="$BOX/home/.claude/checkpoints"

launch() { printf '{"type":"user","message":{"content":[{"type":"tool_result","content":[{"type":"text","text":"Async agent launched successfully.\\nagentId: %s (internal ID)"}]}]}}\n' "$1"; }
notify() { printf '{"type":"user","message":{"content":"<task-notification>\\n<task-id>%s</task-id>\\n<status>completed</status>\\n</task-notification>"}}\n' "$1"; }
# Context of the transcript below is 501 tokens: over a clear line of 10.
usage='{"message":{"usage":{"cache_read_input_tokens":500,"input_tokens":1}}}'

stop() { # $1 = ceiling; transcript body on stdin -> restarted | passed | blocked
  rm -f "$CPD"/sid.* "$CPD/resume-pending.$PSLUG" "$CPD/clear-hook.log"
  { echo "$usage"; cat; } > "$BOX/transcript.jsonl"
  echo '# checkpoint' > "$CPD/sid.md"
  (cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/transcript.jsonl" \
    | env -i PATH="$BOX/bin:$PATH" HOME="$BOX/home" ORCA_TERMINAL_HANDLE=old-pane \
        COMMANDECK_CLEAR_LINE=10 COMMANDECK_CLEAR_CEILING="$1" COMMANDECK_RESTART_HELPER="$BOX/helper.sh" \
        bash "$HOOK" > "$BOX/out" 2>/dev/null)
  if jq -e '.decision == "block"' "$BOX/out" >/dev/null 2>&1; then echo blocked
  elif [ -e "$CPD/resume-pending.$PSLUG" ]; then echo restarted
  else echo passed; fi
}
logged() { grep -qF -- "$1" "$CPD/clear-hook.log" && echo yes || echo no; }

check "2 launched, 1 notified: the restart is held and the stop passes" passed \
  "$({ launch aaa1; launch bbb2; notify aaa1; } | stop 480000)"
check "the hold is logged with the running agent" yes "$(logged 'held: 1 background agents running (bbb2 )')"

check "2 launched, 2 notified: main restarts" restarted \
  "$({ launch aaa1; launch bbb2; notify aaa1; notify bbb2; } | stop 480000)"
check "a restart with every agent finished logs no hold" no "$(logged 'held:')"

# Above the ceiling a hung agent must not hold main into the 500K auto-compact.
check "2 launched, 1 notified, above the ceiling: main restarts anyway" restarted \
  "$({ launch aaa1; launch bbb2; notify aaa1; } | stop 100)"
check "the ceiling restart names the agent it kills" yes "$(logged 'restart kills background agents: bbb2')"

# A foreground Agent call returns inline and is never running at a stop.
check "a foreground agent id never holds the restart" restarted \
  "$(printf '{"type":"user","message":{"content":"result text\\nagentId: ccc3"}}\n' | stop 480000)"

# Main printing a line of a Builder's session log puts that Builder's launch
# text in main's transcript as command output. No notification for it can ever
# arrive here, so it must not hold main (2026-10-13: held main at 230K).
quoted() { printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"log line: Async agent launched successfully.\\nagentId: %s (internal ID)"}]},"toolUseResult":{"stdout":"Async agent launched successfully. agentId: %s","stderr":""}}\n' "$1" "$1"; }
check "another session's launch quoted in command output never holds the restart" restarted \
  "$(quoted ddd4 | stop 480000)"
check "a quoted launch beside a real one: only the real one holds" passed \
  "$({ quoted ddd4; launch eee5; } | stop 480000)"
check "the hold names the real agent only" yes "$(logged 'held: 1 background agents running (eee5 )')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
