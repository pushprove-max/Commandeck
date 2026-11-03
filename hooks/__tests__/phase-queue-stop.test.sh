#!/usr/bin/env bash
# Self-test phase-queue-stop.sh: structured phase state controls Stop.
#
# THE QUEUE'S OWNER. A queue is one instruction the owner gave one session. The first
# session to end a turn with it on disk owns it and is the only one held to it;
# a queue rewritten since then is a new instruction and is adopted again. Left
# behind, the old queue refused the Stop of every unrelated session in the same
# checkout, including one sent to clean it up.
#
# The cases run in a throwaway cwd so the repo's own phase queue is never read
# or written, and ownership is recorded in a throwaway cache dir.
set -u
export COMMANDECK_HOOK_TIER=strict

ROOT=$(git rev-parse --show-toplevel)
HOOK="$ROOT/hooks/phase-queue-stop.sh"
PASS=0 FAIL=0

check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected '$2', got '$3')"; fi }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude"

# $1 = last assistant message. Runs with the repo as CLAUDE_PROJECT_DIR but the
# throwaway as cwd (the queue is read from it).
run() {
  ( cd "$TMP" && CLAUDE_PROJECT_DIR="$ROOT" bash "$HOOK" >/dev/null 2>&1 \
      <<<"$(jq -cn --arg m "$1" '{hook_event_name:"Stop", last_assistant_message:$m}')" )
  echo $?
}
err() {
  ( cd "$TMP" && CLAUDE_PROJECT_DIR="$ROOT" bash "$HOOK" 2>&1 >/dev/null \
      <<<"$(jq -cn --arg m "$1" '{hook_event_name:"Stop", last_assistant_message:$m}')" )
}
export COMMANDECK_PHASE_QUEUE_DIR="$TMP/owners"
# Same as run(), with a session id on the payload and the cwd stated the way
# the harness states it.
run_sid() { # session id, message
  ( cd "$TMP" && CLAUDE_PROJECT_DIR="$ROOT" bash "$HOOK" >/dev/null 2>&1 \
      <<<"$(jq -cn --arg s "$1" --arg m "${2:-ok}" --arg c "$TMP" \
            '{hook_event_name:"Stop", session_id:$s, cwd:$c, last_assistant_message:$m}')" )
  echo $?
}
err_sid() { # session id, message
  ( cd "$TMP" && CLAUDE_PROJECT_DIR="$ROOT" bash "$HOOK" 2>&1 >/dev/null \
      <<<"$(jq -cn --arg s "$1" --arg m "${2:-ok}" --arg c "$TMP" \
            '{hook_event_name:"Stop", session_id:$s, cwd:$c, last_assistant_message:$m}')" )
}
queue() { printf '%s\n' "$@" > "$TMP/.claude/phase-queue.md"; }
noqueue() { rm -f "$TMP/.claude/phase-queue.md" "$TMP/.claude/phase-queue.paused"; }

# --- part 1: the phase queue --------------------------------------------------
noqueue
check "no queue and a clean reply: the turn may end" 0 "$(run 'Done -- the suite is green.')"

queue '- [ ] wire the detector' '- [x] fix the dead tests'
# Catches a green commit ending a turn with boxes still open.
check "an open box refuses Stop" 2 "$(run 'Done.')"
check "the block names the next item"          0 "$(err 'Done.' | grep -qF 'wire the detector' && echo 0 || echo 1)"

queue '- [x] wire the detector' '- [x] fix the dead tests'
check "a fully ticked queue passes"            0 "$(run 'Done.')"

queue '- [ ] wire the detector  BLOCKED: need the owner to pick the threshold'
check "a BLOCKED item releases the hook"       0 "$(run 'Done.')"

queue '- [ ] wire the detector'
touch "$TMP/.claude/phase-queue.paused"
check "a paused queue releases the hook"       0 "$(run 'Done.')"
rm -f "$TMP/.claude/phase-queue.paused"

# --- response prose is advisory; structured queue state is authoritative ------
noqueue
check "banned wording with no queue may end" 0 "$(run 'That is out of scope for this unit.')"
check "the retired diagnostic is absent"                   1 \
  "$(err 'That is out of scope.' | grep -qF 'Deferral language detected' && echo 0 || echo 1)"
check "the retired phrase diagnostic is absent"                  1 \
  "$(err 'That is out of scope.' | grep -qF 'out of scope' && echo 0 || echo 1)"

# Checked and explicitly BLOCKED queues release Stop regardless of response prose.
queue '- [x] all done'
check "banned wording with a checked queue may end"    0 "$(run 'That part is out of scope.')"
queue '- [ ] a thing  BLOCKED: waiting on the owner'
check "banned wording with a BLOCKED queue may end"    0 "$(run 'This is good enough for now.')"

noqueue

check "an empty payload passes"                        0 "$(run '')"

# An actionable open queue remains authoritative.
queue '- [ ] wire the detector'
touch "$TMP/.claude/phase-queue.paused"
check "banned wording with a paused queue may end" 0 "$(run 'That part is out of scope.')"
rm -f "$TMP/.claude/phase-queue.paused"
check "banned wording cannot complete an owned open phase" 2 \
  "$(run 'Everything is done; the remaining item is out of scope.')"
check "an open queue reports the queue, not the phrase" 0 \
  "$(err 'out of scope' | grep -qF 'DO NOT STOP' && echo 0 || echo 1)"

noqueue
TRANSCRIPT="$TMP/transcript.jsonl"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"The pre-existing issue is out of scope."}]}}' > "$TRANSCRIPT"
check "Claude transcript wording with no queue may end" 0 \
  "$( ( cd "$TMP" && CLAUDE_PROJECT_DIR="$ROOT" bash "$HOOK" >/dev/null 2>&1 \
      <<<"$(jq -cn --arg p "$TRANSCRIPT" '{hook_event_name:"Stop", transcript_path:$p}')" ); echo $?)"

# --- the queue belongs to one session -----------------------------------------
rm -rf "$TMP/owners"
noqueue
queue '- [ ] wire the detector' '- [ ] widen the guard'

# Catches the first session to Stop escaping its own queue.
check "the first Stop adopts the queue: held" 2 "$(run_sid session-a)"
check "and is held again on its next turn"            2 "$(run_sid session-a)"
# Catches an unrelated session being refused by a queue it does not own.
check "a later visitor is not held" 0 "$(run_sid session-b)"
check "and is told whose queue it is"                 0 \
  "$(err_sid session-b | grep -qF 'belongs to another session' && echo 0 || echo 1)"
check "another session may use banned wording" 0 \
  "$(run_sid session-b 'That is out of scope.')"
check "the owner is still held after that"            2 "$(run_sid session-a)"

# A rewritten queue is a new instruction, so it is adopted again.
sleep 1
queue '- [ ] a different list entirely'
check "a rewritten queue is adopted by whoever sees it" 2 "$(run_sid session-b)"
check "and the previous owner is now the visitor"       0 "$(run_sid session-a)"

# A payload with no session id keeps the old behaviour: held, no ownership.
check "a payload with no session id is still held"    2 "$(run '')"

# --- pause and block are states, and they say so ------------------------------
noqueue
queue '- [ ] wire the detector'
touch "$TMP/.claude/phase-queue.paused"
check "a paused queue does not hold the turn"         0 "$(run_sid session-c)"
check "a paused queue says it is paused"              0 \
  "$(err_sid session-c | grep -qF 'PAUSED' && echo 0 || echo 1)"
rm -f "$TMP/.claude/phase-queue.paused"

rm -rf "$TMP/owners"
queue '- [ ] wire the detector  BLOCKED: which ring does this land in?'
check "a blocked queue does not hold the turn"        0 "$(run_sid session-d)"
check "a blocked queue names the item"                0 \
  "$(err_sid session-d | grep -qF 'which ring does this land in?' && echo 0 || echo 1)"
noqueue

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
