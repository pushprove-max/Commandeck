#!/usr/bin/env bash
# PostToolUse hook: when a session has spent three turns in a row on ONE
# read-only look each, say that independent looks ride together.
#
# WHY. Every tool call replays the whole accumulated context, so a turn with one
# call and a turn with six cost about the same. On 2026-09-15 main made 1,976 tool
# calls across 1,820 tool-bearing turns -- 1.09 calls a turn, with 1,659 turns
# carrying exactly one. At a 124K median context that single habit is roughly
# half of main's 248M input tokens for the day. A rule nothing measures is a
# rule nothing follows; this is the counter behind it.
#
# ONLY READ-ONLY LOOKS COUNT. Edits, writes, test runs and waits are
# legitimately sequential (edit -> verify -> edit), so one of them resets the
# streak. At the old count of ten, nine round trips were already paid, so it
# fires on the third.
#
# HOW A TURN IS DETECTED. A tool call ends a turn, so every call is either the
# first of a new turn or a sibling inside one parallel block. The two are
# minutes and milliseconds apart respectively: siblings in one block fire this
# hook back to back, while a new turn waits out a whole model round trip. So the
# gap since the previous call is the signal, and nothing else has to be parsed.
#
# ponytail: a wall-clock gap stands in for a turn id the hook payload does not
# carry; key on it directly if the payload ever grows one.
#
# Advisory, so it EXITS 0 and carries its advice as native additionalContext
# (staged-index-warn.sh set that shape). A non-zero advisory shows a Codex seat
# `Script failed` with no text at all, and the seat then redoes the very work it
# was being advised about -- about 14 of one day's 81 dead calls.
# The calls already happened, so the demanded action is about the next ones.
# Main and worker worktrees alike hear it on every fresh streak: one cut ran 379
# single-call turns of 397 after a single nudge, and main 484 of 565 (2026-09-18).
set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh). A planner seat (seat.sh exports
# COMMANDECK_SEAT=<role>) hears it either way: it is almost all reads, and it never ran under the default tier.
case "${COMMANDECK_SEAT-}" in plan-*) ;; *) { . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0 ;; esac

# A FAILED call is still a turn -- the context was replayed either way -- so
# unlike script-over-reads.sh this does not skip errors.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
STATE="/tmp/claude-batch-${SID:-$PPID}"

# Both overridable so the self-test does not have to sleep through real gaps.
SIBLING_MS=${BATCH_SIBLING_MS:-1500}
THRESHOLD=${BATCH_STREAK_THRESHOLD:-3}

NOW=$(date +%s%3N 2>/dev/null) || exit 0
case "$NOW" in ''|*[!0-9]*) exit 0 ;; esac

PREV=0; STREAK=0
[ -f "$STATE" ] && read -r PREV STREAK < "$STATE" 2>/dev/null
case "${PREV:-x}${STREAK:-x}" in *[!0-9]*) PREV=0; STREAK=0 ;; esac

# THE TRUE COUNT, WHENEVER THE TRANSCRIPT IS THERE. Every tool call of
# one turn belongs to one assistant message, so that message's `tool_use` blocks
# answer "was this turn batched?" exactly. The wall-clock gap below only guesses,
# and it guessed wrong on real three-call turns: parallel tools FINISH minutes
# apart when one of them is slow, and this hook fires on finish. It stays as the
# fallback for a seat whose payload carries no transcript (a Codex pane).
# Claude Code writes each content block of one message as its OWN line, all
# sharing message.id, so the last line alone always showed one call and a
# seven-call block read as single-call (2026-09-23). Count the whole message.
# The transcript also LAGS the hook: a call's line can land after its hook
# runs, so the last message on disk may be the previous turn's. The call's own
# tool_use_id finds its message; 0 (not on disk yet) hands over to the gap.
CALLS=0
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
TUID=$(printf '%s' "$INPUT" | jq -r '.tool_use_id // empty' 2>/dev/null)
count_calls() {
  local N
  N=$(tail -n 400 "$TRANSCRIPT" | grep -F '"type":"assistant"' | jq -s --arg u "$TUID" '
    (if $u == "" then last
     else map(select(any((.message.content // [])[]; .type == "tool_use" and .id == $u))) | last end) as $m
    | if $m == null then 0
      else [(if $m.message.id == null then [$m] else map(select(.message.id == $m.message.id)) end)[]
            | (.message.content // [])[] | select(.type == "tool_use")] | length end' 2>/dev/null)
  case "${N:-x}" in ''|*[!0-9]*) N=0 ;; esac
  echo "$N"
}
if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then CALLS=$(count_calls); fi

# Read-only: Read/Grep/Glob, serena and codebase-memory lookups, and a Bash
# call whose every segment is a look (rg/grep, ls, git log/show/diff/status,
# board/status scripts, and the read filters they pipe into).
# ponytail: an allowlist, so an unlisted look resets instead of counting; add
# it here when a token review shows it streaking.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
read_only() {
  local CMD SEG
  case "$TOOL" in
    Read|Grep|Glob|LS) return 0 ;;
    mcp__serena__find_*|mcp__serena__get_symbols_overview|mcp__serena__get_diagnostics_for_file) return 0 ;;
    mcp__codebase-memory__index_repository|mcp__codebase-memory__delete_project|mcp__codebase-memory__ingest_traces|mcp__codebase-memory__manage_adr) return 1 ;;
    mcp__codebase-memory__*) return 0 ;;
    Bash) ;;
    *) return 1 ;;
  esac
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -n "$CMD" ] || return 1
  CMD=${CMD//2>\/dev\/null/}; CMD=${CMD//2>&1/}
  case "$CMD" in *'>'*|*'`'*|*'$('*) return 1 ;; esac
  while IFS= read -r SEG; do
    SEG=${SEG#"${SEG%%[![:space:]]*}"}
    [ -n "$SEG" ] || continue
    [[ $SEG =~ ^(cd|rg|grep|ls|cat|head|tail|wc|sort|uniq|cut|jq|stat)([[:space:]]|$) ]] && continue
    [[ $SEG =~ ^sed[[:space:]]+-n[[:space:]] ]] && continue
    [[ $SEG =~ ^git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(log|show|diff|status)([[:space:]]|$) ]] && continue
    [[ $SEG =~ ^(bash[[:space:]]+)?([^[:space:]]*/)?scripts/(board|[a-z-]*status[a-z-]*)\.sh([[:space:]]|$) ]] && continue
    return 1
  done < <(printf '%s\n' "$CMD" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/[;|&]/\n/g')
  return 0
}

GAP=$((NOW - PREV))
if [ "$CALLS" -ge 2 ] \
  || { [ "$CALLS" -eq 0 ] && [ "$PREV" -gt 0 ] && [ "$GAP" -lt "$SIBLING_MS" ]; }; then
  # A sibling in a parallel block. The turn that opened the streak was batched
  # after all, so the streak is not just paused, it is wrong: clear it.
  STREAK=0
elif read_only; then
  STREAK=$((STREAK + 1))
else
  STREAK=0
fi
printf '%s %s\n' "$NOW" "$STREAK" > "$STATE" 2>/dev/null || exit 0

[ "$STREAK" -ge "$THRESHOLD" ] || exit 0
# The FIRST call of a parallel block can finish before its siblings are even
# written, so it cannot see them. Only on the call that would nudge, wait one
# sibling window and count again; a sibling by then means a batched turn.
# ponytail: a block whose next call streams for longer than the window still
# nudges; key on a message-complete marker if the transcript ever grows one.
if [ -n "$TUID" ] && [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
  sleep "$((SIBLING_MS / 1000)).$(printf '%03d' $((SIBLING_MS % 1000)))"
  if [ "$(count_calls)" -ge 2 ]; then
    printf '%s 0\n' "$NOW" > "$STATE" 2>/dev/null || true
    exit 0
  fi
fi
# Reset either way: a session that has been told once should get its next
# streak counted afresh rather than firing on every call past the threshold.
printf '%s 0\n' "$NOW" > "$STATE" 2>/dev/null || true
ADVICE=$(cat <<EOF
BATCHING: that is $THRESHOLD turns in a row carrying one read-only look each.
Each turn replays the whole context, so $THRESHOLD single-call turns cost about
$THRESHOLD times what one turn with $THRESHOLD calls costs, for the same information.

Issue demonstrably independent inspections in ONE turn, using the native
parallel tool interface -- not a shell chain and not a throwaway script.
Batch only what has all its inputs already: a call built on a guessed value
gets discarded and redone, which costs more than running it sequentially.

Keep sequential: dependencies, waits, approvals, interdependent edits, anything
irreversible, and adaptive investigation where each result picks the next
question. If this streak was all of those, it was the right shape -- carry on.

Said again after every $THRESHOLD single-call read-only turns in a row.
EOF
)
HOOK_FIRE_ADVISE=1
printf '%s\n' "$ADVICE" >&2
jq -cn --arg message "$ADVICE" '{
  systemMessage:$message,
  hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$message}
}' 2>/dev/null || true
exit 0
