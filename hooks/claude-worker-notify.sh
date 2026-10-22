#!/usr/bin/env bash
# Stop hook for Claude panes in Orca worktrees: when a seat finishes a turn,
# send an Orca message so the main session's `orchestration check --wait` wakes
# at once (ruling 2026-09-07, the Claude twin of codex-notify.sh; keep the
# two in parity). Main is exempt: it is not a linked
# worktree. The last assistant text comes from the transcript the hook is
# handed; the run id from the file main writes at dispatch time.
# Issue 321: a turn sends at most one message, and only when it has something to
# act on: a QUESTION:/BLOCKED: line, always; a marker, only from a pane with no
# seat record (a seat's finish is its wait's, collect's or main-watch's to report).
# Issue 320: a plan seat whose plan is committed but whose turn ended without
# PLAN-DONE is blocked once and asked for it. No Codex twin of the block: the
# parity breaks on purpose.
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
# The latest reply's text blocks, joined: Claude Code writes one record per block, under one message id.
key=None; texts=[]
for l in open(sys.argv[1]):
    try: o=json.loads(l)
    except Exception: continue
    if o.get("type")!="assistant": continue
    t=[c["text"] for c in o.get("message",{}).get("content",[]) if c.get("type")=="text" and c.get("text","").strip()]
    if not t: continue
    k=o.get("message",{}).get("id") or o.get("uuid")
    if k!=key: key,texts=k,[]
    texts+=t
print("\n".join(texts))
EOF
)
fi
FULL=$MSG; MSG=$(printf '%s' "$FULL" | tail -c 600)
VERDICT=$(printf '%s' "$MSG" | grep -oE 'VERDICT: (NO-GO|GO|DONE)' | tail -1)
# A question or refusal on its own line always reaches main, once: no gate below silences it. Read from the whole
# reply, not the cropped body, and put ahead of the body when the crop lost it. A line quoted in a fence or a
# blockquote is an example, not an ask (pp_ask_lines). ASK is the first ask line, the one the subject and the gates use;
# every ask line the crop lost goes ahead of the body.
ASKS=$( . "$HERE/../scripts/paths.sh" >/dev/null 2>&1; pp_ask_lines "$FULL" ); ASK=${ASKS%%$'\n'*}
LOST=$(while IFS= read -r l; do [ -z "$l" ] || grep -qF -- "$l" <<<"$MSG" || printf '%s\n' "$l"; done <<<"$ASKS")
[ -z "$LOST" ] || MSG="$LOST"$'\n[...]\n'"$MSG"
# The plan is committed and the marker is missing: ask for it, once (stop_hook_active is the second stop), unless the
# turn ended on a question, a refusal, PLAN-BLOCKED or a verdict line (pp_failed_text), or the seat reported a failure by
# message, or the inbox does not answer in full (pp_seat_clear): that is the seat's word, never rewritten to a finish. Only when
# the session log answers that no background command is live (pp_turn_quiet); running is accepted, as Claude Code
# writes the turn's end after its Stop hooks run.
if [ -z "$ASK" ] && [ -n "${ORCA_TERMINAL_HANDLE:-}" ] && [ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" != true ] \
   && ! printf '%s\n' "$MSG" | sed -E 's/^[[:space:]*`•]+//; s/[[:space:]*`"]+$//' | grep -qx PLAN-DONE; then
  PU=$( . "$HERE/../scripts/paths.sh" >/dev/null 2>&1 || exit 0
    r=$(pp_seat_record "$ORCA_TERMINAL_HANDLE") && pp_plan_committed "$r" && pp_turn_quiet "$(pp_seat_turn "$r")" 'running|complete' \
      && ! pp_failed_text "$FULL" && pp_seat_clear "$r" && sed -n 's/^unit=//p' "$r" | tail -1 )
  [ -z "$PU" ] || { jq -nc --arg r "Your plan .claude/plans/$PU.md is committed since this seat started, but your turn ended without its marker. Print this line alone as your last line, with nothing after it: PLAN-DONE" \
    '{decision: "block", reason: $r}'; HOOK_FIRE_BLOCK=1; exit 0; }
fi
# No marker and no ask line, no send: a mid-work turn end has nothing for main, and
# main-watch's and seat.sh wait's own timers catch a pane that stopped silently.
[ -n "$ASK" ] || printf '%s' "$MSG" | grep -qE -- '-DONE|VERDICT:|PLANFIX' || exit 0
command -v orca-ide >/dev/null || exit 0
# A unit with a live drive, loop or run driver reports through that driver, and
# this send would wake main for nothing. Only a positive answer
# silences it: no driver, an unknown service state or no unit keeps the send.
HS=$HERE/../scripts/host-services.sh
[ -n "$ASK" ] || ! ( . "$HS" && hs_unit_driven "${ORCA_WORKTREE_ID##*/}" ) >/dev/null 2>&1 || exit 0
# One echo per pane per turn's marker or ask line: the Stop hook re-fires on the
# same last text, and a later turn that ends on the same line is a new event. A
# marker turn from a pane a seat.sh wait watches (pp_waited_on), or from a seat
# pane (its record), sends nothing. No pane handle or no scratch keeps the send.
# The marker alone is not the turn: a reused pane ends its next task on the
# same line, so the turn's own id goes with it.
TURN=$(jq -Rr 'fromjson? | select(.type == "assistant" and any(.message.content[]?; .type == "text" and (.text | test("\\S")))) | .uuid // empty' "$T" 2>/dev/null | tail -1)
MARK=${ASK:-$(printf '%s' "$MSG" | grep -E -- '-DONE|VERDICT:|PLANFIX' | tail -1)}
MARK="$TURN $MARK"
SEEN=""
if [ -n "${ORCA_TERMINAL_HANDLE:-}" ]; then
  SCR=$( . "$HERE/../scripts/paths.sh" >/dev/null 2>&1 || exit 0
    if [ -z "$ASK" ] && { pp_waited_on "$ORCA_TERMINAL_HANDLE" "" "$MSG" "${TURN:+claude:$TURN}" || pp_seat_record "$ORCA_TERMINAL_HANDLE" >/dev/null; }
    then echo waited; else printf '%s' "$PP_SCRATCH"; fi )
  [ "$SCR" = waited ] && exit 0
  SEEN=${SCR:+$SCR/notified-$ORCA_TERMINAL_HANDLE}
  [ -n "$SEEN" ] && [ "$(cat "$SEEN" 2>/dev/null)" = "$MARK" ] && exit 0
fi
# Type is `question`, not `worker_done`: Orca refuses a worker_done that carries
# no task id ("worker_done requires taskId") and a Stop hook has none, so every
# report was thrown away silently. `question` is a wake orca-wait.sh already
# drains. Failures print instead of vanishing -- the old `|| true` is how this
# stayed broken (2026-09-13).
WHAT=${ASK%%:*}; WHAT=${WHAT:-$VERDICT}
OUT=$(orca-ide orchestration send --run "$RUN" --to "run:$RUN" --type question \
  --subject "claude turn complete${WHAT:+: $WHAT} (${ORCA_WORKTREE_ID##*/})" \
  --body "$MSG" --json 2>&1)
if printf '%s' "$OUT" | jq -e '.ok' >/dev/null 2>&1; then [ -z "$SEEN" ] || printf '%s\n' "$MARK" > "$SEEN"
else HOOK_FIRE_ADVISE=1; echo "worker-notify: Orca refused the report: $OUT" >&2; fi
exit 0
