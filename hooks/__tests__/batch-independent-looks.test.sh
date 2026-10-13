#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
# Self-test for batch-independent-looks.sh.
#
# The hook's whole claim is that a wall-clock gap separates a new turn from a
# sibling inside one parallel block. Each case below drives that boundary
# directly, so a change to the gap logic cannot pass silently.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOOK="$ROOT/hooks/batch-independent-looks.sh"
PASS=0; FAIL=0

# A tiny sibling window so the test can separate turns with a real sleep that
# costs milliseconds rather than seconds.
export BATCH_SIBLING_MS=200
export BATCH_STREAK_THRESHOLD=3

# Main (git dir == common dir) and a linked worker worktree are both told on
# every fresh streak. The default cases run as main; 3b runs as a worktree.
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
git init -q "$BOX/m" && git -C "$BOX/m" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init \
  && git -C "$BOX/m" worktree add -q "$BOX/lw" >/dev/null 2>&1
export CLAUDE_PROJECT_DIR="$BOX/m"

# ADVISORY MEANS EXIT 0. A non-zero advisory shows a Codex seat
# `Script failed` with no text, so the seat redoes the work it was being advised
# about. Any non-zero rc is printed as itself and fails the case that expects
# `nudge` or `quiet`, which is how this test catches a regression to exit 2.
# Only a read-only call counts toward the streak, so the default call is
# a Read; `turn_as` sends any other tool payload.
READ_CALL='"tool_name":"Read","tool_input":{"file_path":"x.md"}'
call() {  # <session-id> [tool json] -- one tool call; prints nudge, quiet, or rc=<n>
  local out rc
  out=$(printf '{"session_id":"%s",%s}' "$1" "${2:-$READ_CALL}" | bash "$HOOK" 2>&1 >/dev/null); rc=$?
  [ "$rc" -eq 0 ] || { echo "rc=$rc"; return; }
  case "$out" in *"BATCHING:"*) echo nudge ;; *) echo quiet ;; esac
}
turn() { sleep 0.3; call "$1"; }        # a gap wider than the sibling window
turn_as() { sleep 0.3; call "$1" "$2"; }
bash_call() { jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | sed 's/^{//; s/}$//'; }
sibling() { call "$1"; }                 # back to back, no gap

check() {  # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1));
  else FAIL=$((FAIL+1)); echo "FAIL: $1 -- expected rc=$2, got rc=$3"; fi
}

fresh() { S="t$RANDOM$RANDOM"; rm -f "/tmp/claude-batch-$S"; echo "$S"; }

# 1. Three single-call turns in a row trip the nudge on the third.
S=$(fresh)
check "first single-call turn is silent"  quiet "$(turn "$S")"
check "second single-call turn is silent" quiet "$(turn "$S")"
check "third trips the nudge"             nudge "$(turn "$S")"

# 1b. The advice must reach the model, not just the terminal: on exit 0 the
#     stdout JSON is the only channel a session actually reads.
S=$(fresh)
turn "$S" >/dev/null; turn "$S" >/dev/null
sleep 0.3
JSON=$(printf '{"session_id":"%s",%s}' "$S" "$READ_CALL" | bash "$HOOK" 2>/dev/null)
check "the nudge is native additionalContext" 0 \
  "$(jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"
            and (.hookSpecificOutput.additionalContext | contains("BATCHING:"))' \
     <<<"$JSON" >/dev/null 2>&1 && echo 0 || echo 1)"

# 2. A parallel block clears the streak, so the next turns start from zero.
#    This is the case that matters: batching must actually buy silence.
S=$(fresh)
turn "$S" >/dev/null; turn "$S" >/dev/null   # streak 2, one short of the nudge
sibling "$S" >/dev/null                       # same block -> streak cleared
check "batched turn clears the streak"    quiet "$(turn "$S")"
check "still counting up from zero"       quiet "$(turn "$S")"
check "nudge lands three turns later"     nudge "$(turn "$S")"

# 3. Main hears it on every fresh streak too, and the count resets after each
#    nudge so it does not fire on every call past the threshold.
S=$(fresh)
turn "$S" >/dev/null; turn "$S" >/dev/null
check "main: first streak nudges"         nudge "$(turn "$S")"
check "main: streak resets after it"      quiet "$(turn "$S")"
turn "$S" >/dev/null
check "main: second streak nudges again"  nudge "$(turn "$S")"

# 3b. A worker worktree runs hundreds of calls: it is told on every fresh
#     streak, and the streak resets after each nudge so it does not fire on
#     every call past the threshold.
S=$(fresh)
export CLAUDE_PROJECT_DIR="$BOX/lw"
turn "$S" >/dev/null; turn "$S" >/dev/null
check "worktree: first streak nudges"     nudge "$(turn "$S")"
check "worktree: streak resets after it"  quiet "$(turn "$S")"
turn "$S" >/dev/null
check "worktree: next streak nudges again" nudge "$(turn "$S")"
export CLAUDE_PROJECT_DIR="$BOX/m"

# 4. Sessions are independent: one session's warning must not mute another.
S=$(fresh); T=$(fresh)
turn "$S" >/dev/null; turn "$S" >/dev/null; turn "$S" >/dev/null   # S warned
turn "$T" >/dev/null; turn "$T" >/dev/null
check "a second session still warns"      nudge "$(turn "$T")"

# 4b. A REAL PARALLEL TURN, COUNTED FROM THE TRANSCRIPT. The gap
#     heuristic cannot see one whose calls finish far apart -- a slow command
#     beside a fast read -- and it fired on genuine three-call turns. The
#     assistant message that asked for the calls says how many there were.
tx() {  # <tool_use-count> -- a transcript whose last assistant turn had N calls
  local n=$1
  local f="$BOX/transcript-$n.jsonl" i uses=""
  for ((i=0; i<n; i++)); do uses+=$(printf '{"type":"tool_use","id":"t%d"},' "$i"); done
  printf '{"type":"user","message":{"role":"user"}}\n' > "$f"
  printf '{"type":"assistant","message":{"role":"assistant","content":[%s{"type":"text","text":"x"}]}}\n' "$uses" >> "$f"
  printf '%s' "$f"
}
call_tx() {  # <session-id> <transcript> -- one call carrying a transcript path
  local out rc
  out=$(jq -cn --arg s "$1" --arg t "$2" '{session_id:$s,tool_name:"Read",tool_input:{file_path:"x.md"},transcript_path:$t}' \
    | bash "$HOOK" 2>&1 >/dev/null); rc=$?
  [ "$rc" -eq 0 ] || { echo "rc=$rc"; return; }
  case "$out" in *"BATCHING:"*) echo nudge ;; *) echo quiet ;; esac
}
S=$(fresh)
T3=$(tx 3)
sleep 0.3; call_tx "$S" "$T3" >/dev/null
sleep 0.3; call_tx "$S" "$T3" >/dev/null
sleep 0.3
check "a three-call turn never nudges"    quiet "$(call_tx "$S" "$T3")"
# And a one-call turn still does, so the transcript read is not just "stay quiet".
S=$(fresh)
T1=$(tx 1)
sleep 0.3; call_tx "$S" "$T1" >/dev/null
sleep 0.3; call_tx "$S" "$T1" >/dev/null
sleep 0.3
check "single-call turns still nudge"     nudge "$(call_tx "$S" "$T1")"
# Back-to-back single-call turns are single-call turns, whatever the clock says:
# the transcript count must beat the gap guess, not merely add to it.
S=$(fresh)
call_tx "$S" "$T1" >/dev/null; call_tx "$S" "$T1" >/dev/null
check "no gap between one-call turns still nudges" nudge "$(call_tx "$S" "$T1")"

# 4c. THE REAL TRANSCRIPT SHAPE. Claude Code writes each content block
#     of one assistant message as its OWN line, all sharing message.id, so the
#     last line alone always showed one tool_use. On 2026-09-23 main was nudged
#     straight after turns of 5 and 7 parallel calls because of it.
tx_split() {  # <tool_use-count> -- one message split one block per line
  local n=$1 f="$BOX/split-$1.jsonl" i
  printf '{"type":"user","message":{"role":"user"}}\n' > "$f"
  printf '{"type":"assistant","message":{"id":"msg_prev","content":[{"type":"tool_use","id":"p"}]}}\n' >> "$f"
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result"}]}}\n' >> "$f"
  printf '{"type":"assistant","message":{"id":"msg_B","content":[{"type":"thinking","thinking":"x"}]}}\n' >> "$f"
  for ((i=0; i<n; i++)); do
    printf '{"type":"assistant","message":{"id":"msg_B","content":[{"type":"tool_use","id":"t%d"}]}}\n' "$i" >> "$f"
  done
  printf '%s' "$f"
}
S=$(fresh)
T5=$(tx_split 5)
sleep 0.3; call_tx "$S" "$T5" >/dev/null
sleep 0.3; call_tx "$S" "$T5" >/dev/null
sleep 0.3
check "a split five-call message counts as one batched turn" quiet "$(call_tx "$S" "$T5")"
S=$(fresh)
TS1=$(tx_split 1)
sleep 0.3; call_tx "$S" "$TS1" >/dev/null
sleep 0.3; call_tx "$S" "$TS1" >/dev/null
sleep 0.3
check "a split one-call message is still a single-call turn" nudge "$(call_tx "$S" "$TS1")"

# 4c-2. THE TRANSCRIPT LAGS THE HOOK (2026-09-23, seen live in this unit's own
#     pane). The harness can run a call's hook before that call's line is on
#     disk, so the last message there is the PREVIOUS turn's: an Edit right
#     after a 3-call turn read calls=3. The call's own tool_use_id finds its
#     message; when it is not on disk yet, the gap decides.
call_tu() {  # <session-id> <transcript> <tool_use_id> -- a call as the harness sends it
  local out rc
  out=$(jq -cn --arg s "$1" --arg t "$2" --arg u "$3" '{session_id:$s,tool_name:"Read",tool_input:{file_path:"x.md"},transcript_path:$t,tool_use_id:$u}' \
    | bash "$HOOK" 2>&1 >/dev/null); rc=$?
  [ "$rc" -eq 0 ] || { echo "rc=$rc"; return; }
  case "$out" in *"BATCHING:"*) echo nudge ;; *) echo quiet ;; esac
}
S=$(fresh)
TSTALE=$(tx_split 3)
sleep 0.3; call_tu "$S" "$TSTALE" new1 >/dev/null
sleep 0.3; call_tu "$S" "$TSTALE" new2 >/dev/null
sleep 0.3
check "a stale transcript does not lend the last turn's count" nudge "$(call_tu "$S" "$TSTALE" new3)"
# The first call of a parallel block can finish before its siblings are
# written, so it cannot see them; on the call that would nudge, the hook waits
# one sibling window and counts again.
TL="$BOX/late.jsonl"
S=$(fresh)
printf '{"type":"assistant","message":{"id":"m1","content":[{"type":"tool_use","id":"a"}]}}\n' > "$TL"
sleep 0.3; call_tu "$S" "$TL" a >/dev/null
printf '{"type":"assistant","message":{"id":"m2","content":[{"type":"tool_use","id":"b"}]}}\n' >> "$TL"
sleep 0.3; call_tu "$S" "$TL" b >/dev/null
printf '{"type":"assistant","message":{"id":"m3","content":[{"type":"tool_use","id":"c0"}]}}\n' >> "$TL"
sleep 0.3
( sleep 0.1; printf '{"type":"assistant","message":{"id":"m3","content":[{"type":"tool_use","id":"c1"}]}}\n' >> "$TL" ) &
check "a block's first call waits for its siblings before nudging" quiet "$(BATCH_SIBLING_MS=600 call_tu "$S" "$TL" c0)"
wait

# 4d. ONLY READ-ONLY LOOKS COUNT. Edit -> verify -> edit is the right
#     sequential shape and must never be nudged, and a mutating call resets.
EDIT_CALL='"tool_name":"Edit","tool_input":{"file_path":"x.md"}'
S=$(fresh)
turn_as "$S" "$EDIT_CALL" >/dev/null; turn_as "$S" "$EDIT_CALL" >/dev/null
check "three single Edit turns never nudge"      quiet "$(turn_as "$S" "$EDIT_CALL")"
S=$(fresh)
turn "$S" >/dev/null; turn "$S" >/dev/null
check "an Edit after two reads resets, not nudges" quiet "$(turn_as "$S" "$EDIT_CALL")"
check "the read after the Edit starts from one"    quiet "$(turn "$S")"
for c in 'npm run test:unit' 'git commit -qm x' 'bash scripts/orca-wait.sh'; do
  S=$(fresh)
  turn "$S" >/dev/null; turn "$S" >/dev/null
  check "a single '$c' turn resets the streak" quiet "$(turn_as "$S" "$(bash_call "$c")")"
done
S=$(fresh)
turn_as "$S" "$(bash_call 'rg -n x src')" >/dev/null
turn_as "$S" "$(bash_call 'git log --oneline -3 | head')" >/dev/null
check "read-only Bash looks count"                 nudge "$(turn_as "$S" '"tool_name":"mcp__serena__find_symbol","tool_input":{}')"
S=$(fresh)
turn "$S" >/dev/null; turn "$S" >/dev/null
check "a Bash chain with a write in it resets"     quiet "$(turn_as "$S" "$(bash_call 'ls src && rm -f x')")"

# 4e. The default is three, and the variable still overrides it.
S=$(fresh)
turn "$S" >/dev/null; turn "$S" >/dev/null
check "the default threshold is three" nudge "$(unset BATCH_STREAK_THRESHOLD; turn "$S")"
S=$(fresh)
for _ in 1 2 3; do BATCH_STREAK_THRESHOLD=4 turn "$S" >/dev/null; done
check "BATCH_STREAK_THRESHOLD still overrides"     nudge "$(BATCH_STREAK_THRESHOLD=4 turn "$S")"

# 5. A malformed state file must not wedge the session.
S=$(fresh)
printf 'garbage\n' > "/tmp/claude-batch-$S"
check "garbage state recovers silently"   quiet "$(turn "$S")"

# 6. No session id still works, keyed on the parent pid.
check "missing session_id is handled"     0 "$(printf '{"tool_name":"Bash"}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
rm -f "/tmp/claude-batch-$PPID"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
