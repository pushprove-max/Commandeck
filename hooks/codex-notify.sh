#!/usr/bin/env bash
# Codex `notify` hook: when a Codex seat's turn completes, send an Orca message
# so the main session's `orchestration check --wait` wakes at once instead of at
# its timeout (ruling 2026-09-07). Codex passes one JSON argument:
# {"type":"agent-turn-complete", "last-assistant-message":"...", ...}. The run
# id comes from the file the main session writes at dispatch time; no run file,
# no message. $HOME/.claude/hooks/codex-notify.sh links here; keep in parity
# with its Claude twin, claude-worker-notify.sh.
# Issue 321: a turn sends at most one message, and only when it has something to
# act on: a line starting QUESTION: or BLOCKED:, always; a marker, only from a pane with no
# seat record (a seat's finish is its wait's, collect's or main-watch's to report;
# a Builder's pane has one, and its pass hands the Builder the verdict). The twin
# has a plan-marker block this hook cannot (Codex's notify cannot block a turn).
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
FULL=$(printf '%s' "$PAYLOAD" | jq -r '."last-assistant-message" // empty' 2>/dev/null)
MSG=$(printf '%s' "$FULL" | tail -c 600)
VERDICT=$(printf '%s' "$MSG" | grep -oE 'VERDICT: (NO-GO|GO|DONE)' | tail -1)
# A question or refusal on its own line always reaches main, once: no gate below silences it. Read from the whole
# reply, not the cropped body, and put ahead of the body when the crop lost it. A line quoted in a fence or a
# blockquote is an example, not an ask (pp_ask_lines). ASK is the first ask line, the one the subject and the gates use;
# every ask line the crop lost goes ahead of the body.
ASKS=$( . "$HERE/../scripts/paths.sh" >/dev/null 2>&1; pp_ask_lines "$FULL" ); ASK=${ASKS%%$'\n'*}
LOST=$(while IFS= read -r l; do [ -z "$l" ] || grep -qF -- "$l" <<<"$MSG" || printf '%s\n' "$l"; done <<<"$ASKS")
[ -z "$LOST" ] || MSG="$LOST"$'\n[...]\n'"$MSG"
# No marker and no ask line, no send: a mid-work turn end has nothing for main, and
# main-watch's and seat.sh wait's own timers catch a pane that stopped silently.
[ -n "$ASK" ] || printf '%s' "$MSG" | grep -qE -- '-DONE|VERDICT:|PLANFIX' || exit 0
# A NO-GO goes back to the Builder through its fix round, so main has nothing to act on. Only a NO-GO that is the
# last line is silent: one quoted earlier in a turn that ends on a DONE marker is still that turn's report. A turn
# with an ask line is never silenced: its question or refusal reaches main.
[ -z "$ASK" ] && printf '%s' "$MSG" | awk 'NF { l = $0 } END { gsub(/^[ \t]+|[ \t]+$/, "", l); exit l != "VERDICT: NO-GO" }' && exit 0
# Deliberate gap against the Claude twin: a Codex payload carries no transcript, so a Codex GO/DONE cannot tell
# whether the unit already sent worker_done and keeps this echo.
command -v orca-ide >/dev/null || exit 0
# A unit with a live drive, loop or run driver reports through that driver, and
# this send would wake main for nothing. Only a positive answer
# silences it: no driver, an unknown service state or no unit keeps the send.
HS=$HERE/../scripts/host-services.sh
[ -n "$ASK" ] || ! ( . "$HS" && hs_unit_driven "${ORCA_WORKTREE_ID##*/}" ) >/dev/null 2>&1 || exit 0
# One echo per pane per turn's marker or ask line: the hook re-fires on the same
# last text, and a later turn that ends on the same line is a new event. A
# marker turn from a pane a seat.sh wait watches (pp_waited_on), or from a seat
# pane (its record), sends nothing. No pane handle or no scratch keeps the send.
# The marker alone is not the turn: a reused pane ends its next task on the
# same line, so the turn's own id goes with it.
TURN=$(printf '%s' "$PAYLOAD" | jq -r '."turn-id" // empty' 2>/dev/null)
MARK=${ASK:-$(printf '%s' "$MSG" | grep -E -- '-DONE|VERDICT:|PLANFIX' | tail -1)}
MARK="$TURN $MARK"
SEEN=""
if [ -n "${ORCA_TERMINAL_HANDLE:-}" ]; then
  SCR=$( . "$HERE/../scripts/paths.sh" >/dev/null 2>&1 || exit 0
    if [ -z "$ASK" ] && { pp_waited_on "$ORCA_TERMINAL_HANDLE" "" "$MSG" "${TURN:+codex:$TURN}" || pp_seat_record "$ORCA_TERMINAL_HANDLE" >/dev/null; }
    then echo waited; else printf '%s' "$PP_SCRATCH"; fi )
  [ "$SCR" = waited ] && exit 0
  SEEN=${SCR:+$SCR/notified-$ORCA_TERMINAL_HANDLE}
  [ -n "$SEEN" ] && [ "$(cat "$SEEN" 2>/dev/null)" = "$MARK" ] && exit 0
fi
# Type is `question`, not `worker_done`: Orca refuses a worker_done that carries
# no task id and a notify hook has none, so every report was thrown away
# silently. `question` is a wake orca-wait.sh already drains. Failures print
# instead of vanishing -- the old `|| true` is how this stayed broken.
WHAT=${ASK%%:*}; WHAT=${WHAT:-$VERDICT}
OUT=$(orca-ide orchestration send --run "$RUN" --to "run:$RUN" --type question \
  --subject "codex turn complete${WHAT:+: $WHAT} (${ORCA_WORKTREE_ID##*/})" \
  --body "$MSG" --json 2>&1)
. "$HERE/lib/wake-log.sh" 2>/dev/null
if printf '%s' "$OUT" | jq -e '.ok' >/dev/null 2>&1; then [ -z "$SEEN" ] || printf '%s\n' "$MARK" > "$SEEN"; hook_wake_log codex-notify "run:$RUN" "codex turn complete${WHAT:+: $WHAT}" sent
else HOOK_FIRE_ADVISE=1; hook_wake_log codex-notify "run:$RUN" "codex turn complete${WHAT:+: $WHAT}" refused "${OUT:0:200}"; echo "codex-notify: Orca refused the report: $OUT" >&2; fi
exit 0
