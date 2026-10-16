#!/usr/bin/env bash
# dispatch-task.sh <task> <to> [--keep-task] -- hand an Orca task to a pane.
# worker-start --terminal, not dispatch --inject: on the Mac Orca refuses inject
# into a pane we created ("no recognized agent", even for plain claude), while
# worker-start accepts it and keeps the pane's own command and flags.
# It also takes over a pane still holding an earlier task.
# Orca never binds a Codex pane on the Mac: worker-start answers ok, then its
# dispatch ends failed/timeout with no assignee about 60 s later (0 of 6 since
# the switch to worker-start; the PC bound 3 of 3, 2026-08-25..09-06). So a Mac
# Codex pane skips worker-start and gets one pointer to the task's spec file at
# once; on the PC a refusal or that timeout types the same pointer. The pointer
# counts only once a Codex rollout for the pane's worktree names that file; the
# task stays open, as --keep-task leaves it. A delivered dispatch is never typed
# over: the Mac starts none, the PC types only after Orca failed it. Any other refusal, or a pointer with no proof, prints why, marks <task>
# failed and exits 1: an unproven spec sends no worker_done and main idles (12
# minutes, 2026-09-23). --keep-task leaves the task open for a caller that
# delivers it another way (seat.sh).
set -uo pipefail
TK=${1:?task}; TO=${2:?to}; KEEP=${3:-}
. "$(dirname "$0")/codex-helpers.sh"
# The sender is re-read here, not inherited: a /clear can move main to a new
# pane between the task's creation and this delivery, and Orca refuses the old
# handle (orca-task-create.sh does the same). Best effort: no run, no change.
refresh_sender() { local h; h=$("$(dirname "$0")/run-bound.sh" 2>/dev/null) && [ -n "$h" ] && export ORCA_TERMINAL_HANDLE=$h; return 0; }
refresh_sender
# Main can rebind during the waits above a failure, so the sender is re-read
# right before closing the task; a rejected close leaves it open, so say so.
fail() { # why [task-result]
  local out
  echo "dispatch of $TK to $TO refused: $1" >&2
  if [ "$KEEP" != --keep-task ]; then
    refresh_sender
    out=$(orca-ide orchestration task-update --id "$TK" --status failed --result "${2:-dispatch to $TO refused}" --json 2>&1) \
      || echo "task-update marking $TK failed was rejected, the task stays open: $out" >&2
  fi
  exit 1
}
rc=0; pane_is_busy "$TO" || rc=$?
if [ "$rc" != 1 ]; then
  if [ "$rc" = 0 ]; then why="is mid-turn"; else why="has an agent state Orca cannot report"; fi
  echo "REFUSED: ${TO#terminal:} $why; $TK was not dispatched into it" >&2
  fail "pane busy" "dispatch to $TO refused: pane busy"
fi
H=${TO#terminal:}
# worker-start reusing a pane must be told that pane's worktree.
IFS=$'\t' read -r WTID WTPATH AGENT < <(orca-ide terminal list --json 2>/dev/null | jq -r --arg h "$H" '
  first((.result | if type == "array" then . else (.terminals // []) end)[] | select(.handle == $h)
    | [.worktreeId, .worktreePath, .agentIdentity // ""] | @tsv) // empty' 2>/dev/null)
[ -n "${WTID:-}" ] || fail "pane $H is not in Orca's terminal list"
# A pane seconds old has no agentIdentity yet; the launcher knows what it started.
[ -n "$AGENT" ] || AGENT=${COMMANDECK_DISPATCH_AGENT:-}

# Type the pointer once and wait up to 60 s for the Codex turn it starts.
type_pointer() {
  local run spec f mark
  run=${COMMANDECK_RUN:-$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE" || true)}
  spec=$(orca-ide orchestration task-list ${run:+--run "$run"} --json 2>/dev/null \
    | jq -r --arg t "$TK" 'first(.result.tasks[]? | select(.id == $t) | .spec) // empty' 2>/dev/null)
  [ -n "$spec" ] || fail "$1; its spec could not be read back from Orca to type instead"
  f=$PP_SCRATCH/dispatch-specs/$TK.md; mark=$f.sent
  mkdir -p "${f%/*}" && printf '%s\n' "$spec" > "$f" && touch "$mark" || fail "$1; cannot write $f"
  orca-ide terminal send --terminal "$H" --text "Read $f and follow it in full; it is your whole task. Send no heartbeats, whatever the preamble above asks: main never reads one and each costs you a turn." --enter --json 2>/dev/null \
    | jq -e '.ok' >/dev/null 2>&1 || fail "$1; typing the pointer failed too"
  # Review panes run with CODEX_HOME=~/.codex-review, so their rollouts land there.
  for _ in $(seq 20); do
    grep -q . <<<"$({ find "$HOME/.codex/sessions" "$HOME/.codex-review/sessions" -name 'rollout-*.jsonl' -newer "$mark" -print0 2>/dev/null || true; } \
      | xargs -0r grep -lF "$f" 2>/dev/null | xargs -r grep -lF "\"cwd\":\"$WTPATH\"" 2>/dev/null)" \
      && { echo "NO-WAKE: $TK was typed into $H as a pointer to $f ($1); Orca sends no worker_done for it" >&2; exit 0; }
    sleep 3
  done
  fail "$1; typed a pointer to $f but no Codex turn named it within 60 s -- read the pane before sending anything"
}

[ "$AGENT" = codex ] && [ "$(uname -s)" = Darwin ] && type_pointer "worker-start skipped: Orca never binds a Codex pane on the Mac"
out=$(orca-ide orchestration worker-start --task "$TK" --terminal "$H" --worktree "id:$WTID" --json 2>&1 || true)
# Main moved while this pane booted: one retry as the refreshed coordinator.
if ! jq -e '.ok' <<<"$out" >/dev/null 2>&1 && grep -qiE 'no longer bound|no_active_sender' <<<"$out"; then
  refresh_sender
  out=$(orca-ide orchestration worker-start --task "$TK" --terminal "$H" --worktree "id:$WTID" --json 2>&1 || true)
fi
if ! jq -e '.ok' <<<"$out" >/dev/null 2>&1; then
  why=$(jq -r '.error.message // .' <<<"$out" 2>/dev/null || echo "$out")
  [ "$AGENT" = codex ] || fail "$why"
  type_pointer "$why"
fi
[ "$AGENT" = codex ] || exit 0
# Accepted (PC only): wait for Orca to bind the pane or to give up.
for _ in $(seq 40); do
  d=$(orca-ide orchestration dispatch-show --task "$TK" --json 2>/dev/null | jq -c '.result.dispatch // {}' 2>/dev/null)
  [ "$(jq -r '.assignee_handle // empty' <<<"$d")" = "" ] || exit 0
  [ "$(jq -r '.status' <<<"$d")" != failed ] || type_pointer "dispatch $(jq -r '.last_failure // "failed"' <<<"$d") with no assignee"
  sleep 3
done
fail "worker-start was accepted but Orca neither bound $H nor failed the dispatch within 120 s"
