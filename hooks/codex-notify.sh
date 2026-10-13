#!/usr/bin/env bash
# Codex `notify` hook: when a Codex seat's turn completes, send an Orca message
# so the main session's `orchestration check --wait` wakes at once instead of at
# its timeout (ruling 2026-09-07). Codex passes one JSON argument:
# {"type":"agent-turn-complete", "last-assistant-message":"...", ...}. The run
# id comes from the file the main session writes at dispatch time; no run file,
# no message. $HOME/.claude/hooks/codex-notify.sh links here; keep in parity
# with its Claude twin, claude-worker-notify.sh (worker-notify.test.sh).
PAYLOAD=${1:-}
HERE=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# Codex launches this outside the dispatcher, so its fire-log row is Codex's.
AGENT_KIND=codex
. "$HERE/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$PAYLOAD" Notify
# The project's own run file, never Orca's machine-wide one (lib/project.sh).
RUN_FILE=$(. "$HERE/lib/project.sh" && pp_run_file) || exit 0
[ -s "$RUN_FILE" ] || exit 0
RUN=$(cat "$RUN_FILE")
TYPE=$(printf '%s' "$PAYLOAD" | jq -r '.type // empty' 2>/dev/null)
[ "$TYPE" = "agent-turn-complete" ] || exit 0
MSG=$(printf '%s' "$PAYLOAD" | jq -r '."last-assistant-message" // empty' 2>/dev/null | tail -c 600)
VERDICT=$(printf '%s' "$MSG" | grep -oE 'VERDICT: (NO-GO|GO|DONE)' | tail -1)
# No marker, no send: the unread message alone wakes main, and orca-wait.sh drops
# a markerless turn (same regex), so main woke to "nothing was queued".
printf '%s' "$MSG" | grep -qE -- '-DONE|VERDICT:|PLANFIX' || exit 0
command -v orca-ide >/dev/null || exit 0
# A unit with a live drive, loop or run driver reports through that driver, and
# this send would wake main for nothing. Only a positive answer
# silences it: no driver, an unknown service state or no unit keeps the send.
HS=$HERE/../scripts/host-services.sh
( . "$HS" && hs_unit_driven "${ORCA_WORKTREE_ID##*/}" ) >/dev/null 2>&1 && exit 0
# One echo per pane per turn's marker: the hook re-fires on the same last text,
# and a later turn that ends on the same marker line is a new event. A pane
# a seat.sh wait watches reports through that wait (pp_waited_on). No pane
# handle or no scratch keeps the send.
# The marker alone is not the turn: a reused pane ends its next task on the
# same line, so the turn's own id goes with it.
TURN=$(printf '%s' "$PAYLOAD" | jq -r '."turn-id" // empty' 2>/dev/null)
MARK=$(printf '%s' "$MSG" | grep -E -- '-DONE|VERDICT:|PLANFIX' | tail -1)
MARK="$TURN $MARK"
SEEN=""
if [ -n "${ORCA_TERMINAL_HANDLE:-}" ]; then
  SCR=$( . "$HERE/../scripts/paths.sh" >/dev/null 2>&1 || exit 0
    if pp_waited_on "$ORCA_TERMINAL_HANDLE" "" "$MSG" "${TURN:+codex:$TURN}"; then echo waited; else printf '%s' "$PP_SCRATCH"; fi )
  [ "$SCR" = waited ] && exit 0
  SEEN=${SCR:+$SCR/notified-$ORCA_TERMINAL_HANDLE}
  [ -n "$SEEN" ] && [ "$(cat "$SEEN" 2>/dev/null)" = "$MARK" ] && exit 0
fi
# Type is `question`, not `worker_done`: Orca refuses a worker_done that carries
# no task id and a notify hook has none, so every report was thrown away
# silently. `question` is a wake orca-wait.sh already drains. Failures print
# instead of vanishing -- the old `|| true` is how this stayed broken.
OUT=$(orca-ide orchestration send --run "$RUN" --to "run:$RUN" --type question \
  --subject "codex turn complete${VERDICT:+: $VERDICT} (${ORCA_WORKTREE_ID##*/})" \
  --body "$MSG" --json 2>&1)
if printf '%s' "$OUT" | jq -e '.ok' >/dev/null 2>&1; then [ -z "$SEEN" ] || printf '%s\n' "$MARK" > "$SEEN"
else HOOK_FIRE_ADVISE=1; echo "codex-notify: Orca refused the report: $OUT" >&2; fi
exit 0
