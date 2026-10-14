#!/usr/bin/env bash
# Stop hook for Claude panes in Orca worktrees: when a seat finishes a turn,
# send an Orca message so the main session's `orchestration check --wait` wakes
# at once (ruling 2026-09-07, the Claude twin of codex-notify.sh; keep the
# two in parity). Main is exempt: it is not a linked
# worktree. The last assistant text comes from the transcript the hook is
# handed; the run id from the file main writes at dispatch time.
# $HOME/.claude/hooks/claude-worker-notify.sh links here.
INPUT=$(cat)
HERE=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$HERE/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT" Stop
if [ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ]; then exit 0; fi
# The project's own run file, never Orca's machine-wide one (lib/project.sh).
RUN_FILE=$(. "$HERE/lib/project.sh" && pp_run_file) || exit 0
[ -s "$RUN_FILE" ] || exit 0
RUN=$(cat "$RUN_FILE")
T=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
MSG=""
if [ -n "$T" ] && [ -f "$T" ]; then
  MSG=$(python3 - "$T" <<'EOF' 2>/dev/null
import json,sys
last=""
for l in open(sys.argv[1]):
    try: o=json.loads(l)
    except Exception: continue
    if o.get("type")!="assistant": continue
    for c in o.get("message",{}).get("content",[]):
        if c.get("type")=="text" and c.get("text","").strip(): last=c["text"]
print(last[-600:])
EOF
)
fi
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
# One echo per pane per turn's marker: the Stop hook re-fires on the same last
# text, and a later turn that ends on the same marker line is a new event. A
# pane a seat.sh wait watches reports through that wait (pp_waited_on). No pane
# handle or no scratch keeps the send.
# The marker alone is not the turn: a reused pane ends its next task on the
# same line, so the turn's own id goes with it.
TURN=$(jq -Rr 'fromjson? | select(.type == "assistant" and any(.message.content[]?; .type == "text" and (.text | test("\\S")))) | .uuid // empty' "$T" 2>/dev/null | tail -1)
MARK=$(printf '%s' "$MSG" | grep -E -- '-DONE|VERDICT:|PLANFIX' | tail -1)
MARK="$TURN $MARK"
SEEN=""
if [ -n "${ORCA_TERMINAL_HANDLE:-}" ]; then
  SCR=$( . "$HERE/../scripts/paths.sh" >/dev/null 2>&1 || exit 0
    if pp_waited_on "$ORCA_TERMINAL_HANDLE" "" "$MSG" "${TURN:+claude:$TURN}"; then echo waited; else printf '%s' "$PP_SCRATCH"; fi )
  [ "$SCR" = waited ] && exit 0
  SEEN=${SCR:+$SCR/notified-$ORCA_TERMINAL_HANDLE}
  [ -n "$SEEN" ] && [ "$(cat "$SEEN" 2>/dev/null)" = "$MARK" ] && exit 0
fi
# Type is `question`, not `worker_done`: Orca refuses a worker_done that carries
# no task id ("worker_done requires taskId") and a Stop hook has none, so every
# report was thrown away silently. `question` is a wake orca-wait.sh already
# drains. Failures print instead of vanishing -- the old `|| true` is how this
# stayed broken (2026-09-13).
OUT=$(orca-ide orchestration send --run "$RUN" --to "run:$RUN" --type question \
  --subject "claude turn complete${VERDICT:+: $VERDICT} (${ORCA_WORKTREE_ID##*/})" \
  --body "$MSG" --json 2>&1)
if printf '%s' "$OUT" | jq -e '.ok' >/dev/null 2>&1; then [ -z "$SEEN" ] || printf '%s\n' "$MARK" > "$SEEN"
else HOOK_FIRE_ADVISE=1; echo "worker-notify: Orca refused the report: $OUT" >&2; fi
exit 0
