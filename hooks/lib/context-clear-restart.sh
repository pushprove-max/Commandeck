#!/usr/bin/env bash
# context-clear-restart.sh <old-handle> <checkpoint> <command> <log>
#
# Opens a fresh main pane, types the resume prompt into it, and only then closes
# the pane that is over the context line. Runs detached from the Stop hook so the
# hook can exit while this waits for the new pane's TUI.
#
# Keystrokes sent to main's own pane never reach its input box (proved with a
# probe on 2026-09-12: the same send lands in any other Claude pane), so a typed
# /clear cannot work at any moment. owner ruling 2026-09-12: "you can do it as a
# restart".
#
# The old pane is the ONLY thing holding the session's context, so every step
# that can fail leaves it up: a failed create, and a refused resume prompt.
old=$1; cp=$2; cmd=$3; log=$4
. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/paths.sh" 2>>"$log" || exit 1
# The Stop hook's one-restart-per-checkpoint marker. Written here, not by the
# hook, so it exists only once this helper actually runs. It holds the
# checkpoint's checksum, so only this write of the checkpoint counts as restarted.
cksum < "$cp" > "$cp.restarted"
# Overridable so the self-test does not wait half a minute.
sleep "${COMMANDECK_RESTART_SETTLE_S:-5}"
title="Main Orchestrator"
# Matched by checkout, not title: Orca lists the live title, which Claude
# rewrites as it boots. Only main sessions run in the main checkout.
main_panes() {
  local l; l=$(orca-ide terminal list --json 2>>"$log") || return 1
  printf '%s' "$l" | jq -r --arg w "$PP_MAIN" --arg o "$old" "$PP_PNORM"'
    ($w | pnorm) as $w | (.result.terminals // .result // .)[]
    | select((.worktreePath | pnorm) == $w and .handle != $o) | .handle' 2>>"$log"
}
# Issue 316: a main that cannot read GitHub is not opened. The old pane is the only one holding the context, so it stays.
why=$(pp_gh_read orchestrator "$PP_MAIN" 2>&1) \
  || { rm -f "$cp.restarted"; echo "$(date +%FT%T) restart: REFUSED: main cannot read GitHub: $why; old pane $old left up, next stop retries" >>"$log"; exit 1; }
# Without a snapshot a leftover main pane is indistinguishable from the late one.
before=$(main_panes) || adopt_tries=0
created=$(orca-ide terminal create --worktree "path:$PP_MAIN" --title "$title" --command "$cmd" --json 2>>"$log")
new=$(printf '%s' "$created" | jq -r '.. | objects | select(has("handle")) | .handle' 2>/dev/null | head -1)
if [ -z "$new" ]; then
  echo "$(date +%FT%T) restart: create answered no handle: $(printf '%s' "$created" | tr '\n' ' ' | cut -c1-400)" >>"$log"
  # Orca can open the pane after create has already timed out (2026-09-26); a
  # retry would then open a second main. Only a main pane absent before create is ours.
  for ((i = 0; i < ${adopt_tries:-${COMMANDECK_RESTART_ADOPT_TRIES:-15}}; i++)); do
    new=$(main_panes | grep -vxF -e "$before" -e '' | head -1)
    [ -n "$new" ] && { echo "$(date +%FT%T) restart: create answered no handle; adopted late pane $new" >>"$log"; break; }
    sleep "${COMMANDECK_RESTART_ADOPT_EVERY_S:-3}"
  done
fi
if [ -z "$new" ]; then
  # No new pane exists, so the Stop hook's "already restarted" marker is false;
  # left behind, it blocked every later restart of this checkpoint.
  rm -f "$cp.restarted"
  echo "$(date +%FT%T) restart: terminal create failed; old pane $old left up, next stop retries" >>"$log"; exit 1
fi
orca-ide terminal wait --terminal "$new" --for tui-idle --timeout-ms 120000 --json >/dev/null 2>&1 \
  || sleep "${COMMANDECK_RESTART_TUI_FALLBACK_S:-20}"
sleep "${COMMANDECK_RESTART_SETTLE_S:-3}"
# The restart is complete only once the replacement ACCEPTS the prompt. A refused
# send used to be logged as a success and the old pane closed anyway, which
# destroyed the only pane holding the context.
sent=$(orca-ide terminal send --terminal "$new" \
  --text "resume from the checkpoint $cp (its text, board.sh and the run-use binding are already in your SessionStart context; do not fetch them again, except a part its RESUMED line names as cut); rebuild its Todo list with TaskCreate and keep it current on every step; arm nothing (main-watch.sh wakes you); then service whichever marker has landed. Your first line to the owner is: Handoff done: this is the new main session, resumed from $cp; the old pane $old closes now." \
  --enter --json 2>>"$log")
if ! printf '%s' "$sent" | jq -e '.ok' >/dev/null 2>&1; then
  echo "$(date +%FT%T) restart: resume prompt REFUSED by $new ($(printf '%s' "$sent" | jq -r '.error.code // .error // "unknown"' 2>/dev/null)); old pane $old LEFT UP" >>"$log"
  # Only a closed replacement re-arms the retry (as a failed create does);
  # left open, it would stand as a second main beside the retry's pane.
  if orca-ide terminal close --terminal "$new" --json 2>>"$log" | jq -e '.ok' >/dev/null 2>&1; then
    rm -f "$cp.restarted"
    echo "$(date +%FT%T) restart: closed unprompted $new; next stop retries" >>"$log"
  else
    echo "$(date +%FT%T) restart: close of unprompted $new REFUSED; close it by hand, then delete $cp.restarted to retry" >>"$log"
  fi
  exit 1
fi
# The /handoff request (context-clear-stop.sh) is spent only now that a new main holds the prompt.
rm -f "${cp%.md}.handoff"
echo "$(date +%FT%T) restart: new pane $new resumed from $cp; closing $old" >>"$log"
res=$(orca-ide terminal close --terminal "$old" --json 2>&1)
printf '%s' "$res" | jq -e '.ok' >/dev/null 2>&1 \
  || echo "$(date +%FT%T) restart: close of $old REFUSED ($(printf '%s' "$res" | jq -r '.error.code // .error // "unknown"' 2>/dev/null)); unpin and close it by hand" >>"$log"
# Finished panes otherwise pile up across restarts (ruling 2026-09-23). The
# new main sits in the main checkout, which the sweep never touches. The handoff
# is already done, so a failed sweep is only logged.
if swept=$(bash "$(dirname "$0")/../../scripts/close-done-panes.sh" --close 2>&1); then
  echo "$(date +%FT%T) restart: done-pane sweep: $(printf '%s' "${swept:-nothing to close}" | tr '\n' ';')" >>"$log"
else
  echo "$(date +%FT%T) restart: done-pane sweep FAILED, handoff unaffected: $(printf '%s' "$swept" | tr '\n' ';' | cut -c1-400)" >>"$log"
fi
