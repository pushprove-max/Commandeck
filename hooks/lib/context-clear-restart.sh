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
# open_main <command> -- sets new to the pane create opened, or empty.
open_main() {
  local before created adopt_tries=""
  # Without a snapshot a leftover main pane is indistinguishable from the late one.
  before=$(main_panes) || adopt_tries=0
  created=$(orca-ide terminal create --worktree "path:$PP_MAIN" --title "$title" --command "$1" --json 2>>"$log")
  new=$(printf '%s' "$created" | jq -r '.. | objects | select(has("handle")) | .handle' 2>/dev/null | head -1)
  [ -z "$new" ] || return 0
  echo "$(date +%FT%T) restart: create answered no handle: $(printf '%s' "$created" | tr '\n' ' ' | cut -c1-400)" >>"$log"
  # Orca can open the pane after create has already timed out (2026-09-26); a
  # retry would then open a second main. Only a main pane absent before create is ours.
  for ((i = 0; i < ${adopt_tries:-${COMMANDECK_RESTART_ADOPT_TRIES:-15}}; i++)); do
    new=$(main_panes | grep -vxF -e "$before" -e '' | head -1)
    [ -n "$new" ] && { echo "$(date +%FT%T) restart: create answered no handle; adopted late pane $new" >>"$log"; return 0; }
    sleep "${COMMANDECK_RESTART_ADOPT_EVERY_S:-3}"
  done
}
# give_up <why> -- the typed prompt and the relaunch both failed, or a replacement that got no prompt could not be
# closed: no stop retries this session (context-clear-stop.sh
# reads the mark), and this one log line is what dashboard_limit.py main-events turns into the crit alert asking the
# owner to restart main by hand.
give_up() {
  : > "${cp%.md}.restart-failed"
  echo "$(date +%FT%T) restart: AUTO RESTART FAILED for $cp: $1; main waits for the owner to restart it by hand" >>"$log"
}
# The resume marker as context-clear-stop.sh wrote it (same slug expression): the first pane's SessionStart takes it,
# so a relaunch below must put it back for the second pane to resume.
mark="${cp%/*}/resume-pending.$(printf '%s' "$(git rev-parse --show-toplevel 2>/dev/null)" | tr -c 'A-Za-z0-9' '-')"
markbody=$(cat "$mark" 2>/dev/null)
open_main "$cmd"
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
prompt="resume from the checkpoint $cp (its text, board.sh and the run-use binding are already in your SessionStart context; do not fetch them again, except a part its RESUMED line names as cut); rebuild its Todo list with TaskCreate and keep it current on every step; arm nothing (main-watch.sh wakes you); then service whichever marker has landed. Your first line to the owner is: Handoff done: this is the new main session, resumed from $cp; the old pane $old closes now."
sent=$(orca-ide terminal send --terminal "$new" --text "$prompt" --enter --json 2>>"$log")
sent_ok=0
printf '%s' "$sent" | jq -e '.ok' >/dev/null 2>&1 && sent_ok=1
# While a paired phone has a pane open, Orca answers every typed send with ok:true, accepted:false and types nothing
# (host fix 3a7cc613), for minutes. Read as a success, the old main closed beside a new one that never got its prompt.
# The prompt then rides in a second pane's launch command. The proof that main took it is <cp>.delivered, which
# resume-context.sh writes only after it printed the checkpoint context, naming the token from the marker this helper
# put back: the replacement started with that token, and nothing older (removed here) counts.
jq -e 'any(.. | objects | select(has("accepted")) | .accepted; . == false)' >/dev/null 2>&1 <<<"$sent" && sent_ok=0 phone=1
# A pane whose close is refused stays up, so the refusal below names it; it never counts as a success.
if [ -n "${phone:-}" ] && pp_pane_close "$new" "restart: unprompted new"; then
  echo "$(date +%FT%T) restart: typed resume prompt not accepted by $new (accepted:false); relaunching with the prompt in the command" >>"$log"
  # Whole or not at all: a marker cut after its first line has no token, and resume-context.sh gives that to any main.
  [ -z "$markbody" ] || { printf '%s\n' "$markbody" > "$mark.$$" && mv "$mark.$$" "$mark"; } 2>>"$log" || rm -f "$mark.$$"
  token=$(sed -n 2p <<<"$markbody")
  rm -f "$cp.delivered"
  # Orca types the command into a shell: the prompt goes single-quoted, its own quotes closed and escaped.
  open_main "$cmd '${prompt//\'/\'\\\'\'}'"
  for ((i = 0; i < 40; i++)); do
    [ -n "$new" ] && [ -n "$token" ] || break
    [ "$(head -1 "$cp.delivered" 2>/dev/null)" = "$token" ] && { sent_ok=1; break; }
    sleep "${COMMANDECK_RESTART_SETTLE_S:-3}"
  done
  relaunched=1
  if [ "$sent_ok" = 0 ] && [ -z "$new" ]; then
    rm -f "$cp.restarted"; give_up "the relaunch with the prompt opened no pane"; exit 1
  fi
  [ "$sent_ok" = 1 ] || sent='{"error":{"code":"the relaunched main never confirmed it got this checkpoint context"}}'
fi
if [ "$sent_ok" = 0 ]; then
  pp_wake_log context-restart "$new" "resume prompt" refused "$(printf '%s' "$sent" | jq -r '.error.code // .error // "unknown"' 2>/dev/null)"
  echo "$(date +%FT%T) restart: resume prompt REFUSED by $new ($(printf '%s' "$sent" | jq -r '.error.code // .error // "unknown"' 2>/dev/null)); old pane $old LEFT UP" >>"$log"
  # Only a closed replacement re-arms the retry (as a failed create does);
  # left open, it would stand as a second main beside the retry's pane.
  # A refused close leaves that pane and its .restarted standing, so no stop retries either way: the helper gives up.
  if ! pp_pane_close "$new" "restart: unprompted new"; then
    echo "$(date +%FT%T) restart: close of unprompted $new REFUSED; close it by hand" >>"$log"
    give_up "$new got no resume prompt and Orca refused to close it"
  elif [ -n "${relaunched:-}" ]; then
    rm -f "$cp.restarted"; give_up "Orca did not accept the typed resume prompt and the relaunched main never resumed"
  else
    rm -f "$cp.restarted"; echo "$(date +%FT%T) restart: closed unprompted $new; next stop retries" >>"$log"
  fi
  exit 1
fi
pp_wake_log context-restart "$new" "resume prompt" sent
# The /handoff request (context-clear-stop.sh) is spent only now that a new main holds the prompt.
rm -f "${cp%.md}.handoff"
# `main` names the new pane from here, before the old one closes: a send in the gap, or after a drain that never
# ran, goes to the live pane and not the closed one.
pp_handle_record main "$new"
echo "$(date +%FT%T) restart: new pane $new resumed from $cp; closing $old" >>"$log"
pp_pane_close "$old" "restart: old main" \
  || echo "$(date +%FT%T) restart: close of $old REFUSED ($(printf '%s' "$PP_CLOSE_RES" | jq -r '.error.code // .error // "unknown"' 2>/dev/null)); unpin and close it by hand" >>"$log"
# Finished panes otherwise pile up across restarts (ruling 2026-09-23). The
# new main sits in the main checkout, which the sweep never touches. The handoff
# is already done, so a failed sweep is only logged.
if swept=$(bash "$(dirname "$0")/../../scripts/close-done-panes.sh" --close 2>&1); then
  echo "$(date +%FT%T) restart: done-pane sweep: $(printf '%s' "${swept:-nothing to close}" | tr '\n' ';')" >>"$log"
else
  echo "$(date +%FT%T) restart: done-pane sweep FAILED, handoff unaffected: $(printf '%s' "$swept" | tr '\n' ';' | cut -c1-400)" >>"$log"
fi
