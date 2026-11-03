#!/usr/bin/env bash
# Stop hook (strict tier): an owned, actionable phase queue prevents a turn from ending.
#
# WHY THIS EXISTS. A green commit FEELS like a natural place to report and hand
# back, so the turn ends there even when the instruction was "work through all
# of them". Multi-phase work then costs one prompt per phase to re-issue an
# instruction the owner already gave once.
#
# The task list cannot enforce this -- it lives in the harness, not on disk, so
# no shell hook can read it. This file is the on-disk contract instead.
#
# USAGE. When the owner says "continue through all phases" / "work through the list"
# / anything meaning "do not stop between items", write the queue first:
#
#   .claude/phase-queue.md
#     - [ ] wire the barcode detector into the pipeline
#     - [ ] widen the abstention guard
#     - [x] fix the four dead test files
#
# Then work top to bottom, flipping [ ] to [x] as each lands GREEN. Stopping is
# refused until every box is ticked or the file is deleted. The plugin's one
# prompt to write the queue is the global-rules line; a session that never writes
# it is never held.
#
# ESCAPE HATCHES, because a hook that cannot be stopped is worse than the drift:
#   - Delete .claude/phase-queue.md          (the work is genuinely finished)
#   - Add `BLOCKED: <reason>` to any line    (needs a decision only the owner can make)
#   - `touch .claude/phase-queue.paused`     (the owner redirected mid-queue)
# A blocked or paused queue reports instead of blocking, so a real question
# still reaches the owner immediately -- it SAYS which state it is in, because a
# paused queue and no queue at all are different facts and used to look the
# same from here.
#
# THE QUEUE BELONGS TO ONE SESSION. The first session to end a turn with the
# queue on disk owns it, and only that session is held to it. A queue is one
# instruction the owner gave one session; left behind, it used to refuse the Stop of
# every unrelated session in the same checkout, including the one sent to clean
# it up. Ownership is recorded outside the tree (no file to gitignore, nothing
# to commit) and is re-adopted whenever the queue itself is rewritten, so the
# next session the owner hands a queue to is its owner. The first-observer rule is
# copied as is: an unrelated session that stops first is held, and the instructed
# one then passes, until the queue is rewritten.
# Retire when: no commit has touched .claude/phase-queue.md for 60 days

set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0

queue_check() {
  # The turn's own directory, not the hook process's: they are the same today
  # and the payload is the one that is actually true.
  local BASE QUEUE SID OWNER_DIR OWNER_FILE OWNER
  BASE=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  [ -n "$BASE" ] && [ -d "$BASE" ] || BASE=$PWD
  QUEUE="$BASE/.claude/phase-queue.md"
  [ ! -f "$QUEUE" ] && return 0

  # The owner redirected -- never argue with a live instruction.
  if [ -f "$BASE/.claude/phase-queue.paused" ]; then
    HOOK_FIRE_ADVISE=1
    echo "Phase queue PAUSED ($QUEUE); not holding this turn. Remove .claude/phase-queue.paused to resume it." >&2
    return 0
  fi

  # Whose queue is this? The first session to see it takes it; a queue rewritten
  # since then is a new instruction and is adopted again.
  SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
  if [ -n "$SID" ]; then
    OWNER_DIR="${COMMANDECK_PHASE_QUEUE_DIR:-$HOME/.commandeck/phase-queue}"
    if mkdir -p "$OWNER_DIR" 2>/dev/null; then
      OWNER_FILE="$OWNER_DIR/$(printf '%s' "$BASE" | sha1sum | cut -c1-40)"
      if [ ! -f "$OWNER_FILE" ] || [ "$QUEUE" -nt "$OWNER_FILE" ]; then
        printf '%s\n' "$SID" > "$OWNER_FILE" 2>/dev/null
      else
        read -r OWNER < "$OWNER_FILE"
        if [ -n "$OWNER" ] && [ "$OWNER" != "$SID" ]; then
          echo "A phase queue is open in $QUEUE, but it belongs to another session; not holding this turn." >&2
          return 0
        fi
      fi
    fi
  fi

  # No `|| echo 0` here: grep -c ALREADY prints 0 when it matches nothing, and
  # it also exits non-zero, so the fallback appended a SECOND zero and the
  # numeric test then failed on a two-line value -- blocking a queue that was
  # fully ticked. Caught by testing the all-done path, not only the blocking one.
  local OPEN BLOCKED NEXT
  OPEN=$(grep -cE '^\s*[-*]\s*\[ \]' "$QUEUE" 2>/dev/null)
  [ "${OPEN:-0}" -eq 0 ] 2>/dev/null && return 0

  # An item that needs the owner is not drift; surface it and let the turn end.
  BLOCKED=$(grep -E '^\s*[-*]\s*\[ \].*BLOCKED:' "$QUEUE" 2>/dev/null)
  if [ -n "$BLOCKED" ]; then
    HOOK_FIRE_ADVISE=1
    printf 'Phase queue BLOCKED on an item that needs the owner; not holding this turn:\n%s\n' "$BLOCKED" >&2
    return 0
  fi

  NEXT=$(grep -E '^\s*[-*]\s*\[ \]' "$QUEUE" 2>/dev/null | head -1 | sed -E 's/^\s*[-*]\s*\[ \]\s*//')

  cat >&2 <<EOT
DO NOT STOP -- $OPEN phase(s) still open in $QUEUE.

Next: $NEXT

The owner asked once for the whole queue. Re-asking per phase is the exact cost
this hook exists to remove. Keep going: implement it, verify it green, commit
it, tick its box, move to the next.

If you genuinely cannot proceed, do not just stop -- say why on the item:
  \`- [ ] <the item>  BLOCKED: <the specific decision or fact you need from the owner>\`
That releases the hook AND puts a real question in front of the owner.

Remaining:
$(grep -E '^\s*[-*]\s*\[ \]' "$QUEUE" | head -12)
EOT
  return 2
}

queue_check || { HOOK_FIRE_REASON=phase-queue-open; exit 2; }

exit 0
