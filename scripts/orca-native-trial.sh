#!/usr/bin/env bash
# orca-native-trial.sh <wake|send|submit> <phase> -- a Builder runs this live against Orca (#584 #585 #586) and the
# result lands in docs/orca-native-trial.json, which the removal cuts and their tests read.
#   wake   start | restart | finish        Orca's own wake of the coordinator, with no poller running (#584)
#   send   <claude|codex> [closed]         orchestration send to a finished (or closed) worker (#585)
#   submit                                 three wakes typed into a busy pane, none resent (#586)
# record_result is the only writer of the record. Anything but an exact lowercase `pass` reads `unrun`.
# Why not doctor.sh, proof-run.sh or hook-probe.sh: they are read-only, stubbed or one-hook; this file drives orca-ide.
# Sourced (by the test), it defines the functions and runs nothing.
ONT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ONT_POLLERS='cos-watch-inbox await-agents watch-agents poll-agents'

ont_record() { echo "${ONT_RECORD:-$ONT_ROOT/docs/orca-native-trial.json}"; }

# read_result <trial> -- pass, fail or unrun. <trial>: wake, submit, send.<agent>.<host>, send.<agent>.<host>.closed.
read_result() {
  local r; r=$(jq -r --arg p "$1" 'try (getpath($p | split(".")) | .result) catch null' "$(ont_record)" 2>/dev/null)
  case $r in pass|fail) echo "$r" ;; *) echo unrun ;; esac
}

# trial_unlocked <trial> -- 0 only on an exact pass: the gate a removal tests.
trial_unlocked() { [ "$(read_result "$1")" = pass ]; }

pollers_running() { local n; for n in $ONT_POLLERS; do pgrep -f "$n" >/dev/null 2>&1 && { echo "$n"; return 0; }; done; return 1; }

# record_result <trial> <pass|fail> <why> [form] -- the one writer. A wake pass is refused while a poller runs: the
# poller, not Orca, would have woken the pane. The write goes to a temp file, then renames over the record.
record_result() {
  local f tmp cur p; f=$(ont_record)
  case $2 in pass|fail) ;; *) echo "record_result: result must be pass or fail, got '$2'" >&2; return 1 ;; esac
  # The form is what pp_send_form (paths.sh) reads back: only handle or dispatch, never Orca's flag text.
  case ${4:-} in ''|handle|dispatch) ;; *) echo "record_result: form must be handle or dispatch, got '$4'" >&2; return 1 ;; esac
  if [ "$1" = wake ] && [ "$2" = pass ] && p=$(pollers_running); then
    echo "record_result: wake pass refused, $p is running; stop it and run the trial again" >&2; return 1
  fi
  cur=$(cat "$f" 2>/dev/null); jq -e 'type == "object"' <<<"$cur" >/dev/null 2>&1 || cur='{}'
  mkdir -p "$(dirname "$f")" && tmp=$(mktemp "$f.XXXXXX") || return 1
  if jq --arg p "$1" --arg r "$2" --arg w "$3" --arg form "${4:-}" --arg o "$(orca-ide --version 2>/dev/null | head -1)" \
      --arg d "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '($p | split(".")) as $k
        | .orca = $o | .date = $d
        | setpath($k + ["result"]; $r) | setpath($k + ["why"]; $w)
        | if $form != "" then setpath($k + ["form"]; $form) else . end' <<<"$cur" > "$tmp"; then
    mv "$tmp" "$f"
  else rm -f "$tmp"; return 1; fi
}

# ---- live trials: need a running Orca; the stub test does not reach them ----
ont_load() { . "$ONT_ROOT/scripts/paths.sh"; ONT_SC=$PP_SCRATCH/native-trial; mkdir -p "$ONT_SC"; }
ont_id() { jq -r "$1" 2>/dev/null; }

# A worker whose whole task is to report and end, on a cheap model.
ont_worker() { # <agent> <spec> -> receipt json
  orca-ide orchestration worker-start --agent "$1" --model "${ONT_MODEL:-haiku}" --spec "$2" --json
}

trial_wake() {
  local ph=$1 w p stamp; ont_load; w=$ONT_SC/wake.json
  case $ph in
    start|restart)
      if [ "$ph" = restart ]; then
        trial_unlocked wake || { echo "restart runs only after the first wake passed" >&2; return 2; }
        pp_pane_close "$ORCA_TERMINAL_HANDLE" native-trial-restart
        bash "$ONT_ROOT/hooks/lib/context-clear-restart.sh" || return 1
      else orca-ide orchestration run-create --json >/dev/null || return 1; fi
      local rc; rc=$(ont_worker claude 'Send worker_done succeeded with orchestration send, then end your turn.') || return 1
      jq -n --argjson r "$rc" --arg h "${ORCA_TERMINAL_HANDLE:-}" --arg e "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{receipt: $r, coordinator: $h, stamp: $e}' > "$w.tmp" && mv "$w.tmp" "$w"
      if p=$(pollers_running); then echo "NOT CLEAN: $p is running; stop it, the trial would prove the poller" >&2; return 1; fi
      echo "end your turn now" ;;
    finish)
      stamp=$(jq -r .stamp "$w" 2>/dev/null) || { echo "no wake.json; run start first" >&2; return 2; }
      local why=""
      orca-ide orchestration check --peek --json 2>/dev/null | grep -q worker_done || why="no worker_done in the inbox (check --peek)"
      [ -n "$why" ] || { [ -n "${PP_SESSION_LOG:-}" ] && jq -e --arg s "$stamp" 'select((.timestamp // "") > $s)' "$PP_SESSION_LOG" >/dev/null 2>&1; } \
        || why="no turn row after the worker report in the session log"
      if p=$(pollers_running); then why="$p is running"; fi
      if [ -z "$why" ]; then record_result wake pass "worker_done in the inbox, a turn after it, no poller"
      else record_result wake fail "$why"; fi ;;
    *) echo "usage: orca-native-trial.sh wake start|restart|finish" >&2; return 2 ;;
  esac
}

trial_send() { # <agent> [closed]
  local a=${1:-} key d h s; ont_load; key=send.$a.$(uname -s)
  case $a in claude|codex) ;; *) echo "usage: orca-native-trial.sh send claude|codex [closed]" >&2; return 2 ;; esac
  [ "${2:-}" != closed ] || { trial_send_closed "$a" "$key.closed"; return; }
  s=$(ont_worker "$a" 'Send worker_done succeeded, then end your turn.') || { record_result "$key" fail "worker-start failed"; return 1; }
  d=$(ont_id '.result.dispatch.id // .result.dispatchId' <<<"$s"); h=$(ont_id '.result.handle // .result.terminal.handle' <<<"$s")
  local n=${ONT_TRIES:-60} z=${ONT_SLEEP:-5} settled= tag
  for _ in $(seq "$n"); do orca-ide orchestration worker-show --dispatch "$d" --json 2>/dev/null | grep -q settled && { settled=1; break; }; sleep "$z"; done
  [ -n "$settled" ] || { record_result "$key" fail "the worker never settled, so a send would prove nothing"; return 1; }
  # An accepted send is not a delivery (pass 1): the pass needs the follow-up typed into the pane and a turn that answers
  # it, seen as its one-off word twice in the pane's text (the prompt, then the reply).
  tag=ack-$RANDOM$RANDOM
  orca-ide orchestration send --to "handle:$h" --type dispatch --subject trial --body "Reply with the word $tag, then end." --json >/dev/null 2>&1 \
    || { record_result "$key" fail "orchestration send to the settled worker was refused"; return 1; }
  ont_seen "$h" "$tag" && { record_result "$key" pass "the follow-up reached the settled worker's prompt and a turn answered it" handle; return; }
  record_result "$key" fail "send accepted, but no turn answering the follow-up was seen in the worker's pane"
}

# trial_send_closed <agent> <key> -- DG8: a seat-shaped pane is opened, settled and closed, then pp_follow_up (the
# production route, PP_FOLLOW_UP_TRIAL=1) reaches it by its task's dispatch. Pass only when the record names the
# reopened pane, that pane is listed in the trial's worktree, and its tag is seen twice there (prompt, then reply).
trial_send_closed() {
  local a=$1 key=$2 wt name t h d rec cmd new tag n=${ONT_TRIES:-60} z=${ONT_SLEEP:-5} settled= rc=0
  wt=$(git rev-parse --show-toplevel 2>/dev/null); name=${wt##*/}
  [ -n "$name" ] && [ "$(cd "$PP_WORKSPACES/$name" 2>/dev/null && pwd -P)" = "$(cd "$wt" && pwd -P)" ] \
    || { record_result "$key" fail "trial worktree not under workspaces"; return 1; }
  case $a in claude) cmd="claude --model ${ONT_MODEL:-haiku}" ;; codex) cmd=codex ;; esac
  rec=$PP_SCRATCH/seat-native-trial-send-trial.txt
  t=$(bash "$ONT_ROOT/scripts/orca-task-create.sh" --spec 'Send worker_done succeeded, then end your turn.') \
    || { record_result "$key" fail "task-create failed"; return 1; }
  h=$(orca-ide terminal create --worktree "path:$wt" --title native-trial-send --command "$cmd" --json 2>/dev/null \
    | jq -r 'first(.. | objects | select(has("handle")) | .handle) // empty' 2>/dev/null)
  [ -n "$h" ] || { record_result "$key" fail "terminal create returned no handle"; return 1; }
  printf 'handle=%s\ntask=%s\nrole=trial\nunit=native-trial-send\nworktree=%s\ncmd=%s\n' "$h" "$t" "$name" "$cmd" > "$rec"
  bash "$ONT_ROOT/scripts/dispatch-task.sh" "$t" "terminal:$h" --keep-task >/dev/null 2>&1 \
    || { record_result "$key" fail "dispatch-task.sh could not start the task in $h"; rm -f "$rec"; return 1; }
  d=$(orca-ide orchestration dispatch-show --task "$t" --json 2>/dev/null | jq -r '.result.dispatch.id // empty' 2>/dev/null)
  for _ in $(seq "$n"); do orca-ide orchestration worker-show --dispatch "$d" --json 2>/dev/null | grep -q settled && { settled=1; break; }; sleep "$z"; done
  [ -n "$settled" ] || { record_result "$key" fail "the worker never settled, so a send would prove nothing"; rm -f "$rec"; return 1; }
  pp_task_close "$t" completed >/dev/null 2>&1 || true # a dispatch Orca already settled may refuse; the pane closes either way
  pp_pane_close "$h" native-trial-closed || { record_result "$key" fail "the trial pane did not close: $PP_CLOSE_RES"; rm -f "$rec"; return 1; }
  tag=ack-$RANDOM$RANDOM
  PP_FOLLOW_UP_TRIAL=1 pp_follow_up "$h" trial "Reply with the word $tag, then end." || rc=$?
  new=${PP_FOLLOW_UP_HANDLE:-}
  if [ "$rc" != 0 ] || [ -z "$new" ]; then record_result "$key" fail "pp_follow_up did not reopen $h (rc $rc)"
  elif ! grep -qx "handle=$new" "$rec" || ! pp_worktree_panes "$wt" | grep -qxF "$new"; then
    record_result "$key" fail "the record or Orca's list does not name the reopened pane $new"
  elif ont_seen "$new" "$tag"; then record_result "$key" pass "the closed pane reopened by its dispatch and a turn answered the follow-up"
  else record_result "$key" fail "$h reopened as $new, but no turn answering the follow-up was seen there"; fi
  rm -f "$rec"; [ -z "$new" ] || pp_pane_close "$new" native-trial-closed-end || true
  [ "$(read_result "$key")" = pass ]
}

# ont_seen <handle> <tag> -- the tag seen twice in the pane's text (the prompt, then the reply) within the tries.
ont_seen() {
  for _ in $(seq "${ONT_TRIES:-60}"); do
    [ "$(orca-ide terminal read --terminal "$1" --cursor 0 --limit 300000 --json 2>/dev/null | jq -r '.. | strings' 2>/dev/null | grep -o "$2" | wc -l)" -ge 2 ] && return 0
    sleep "${ONT_SLEEP:-5}"
  done; return 1
}

trial_submit() {
  local s h i out bad=0; ont_load
  s=$(ont_worker claude 'Run `sleep 60` in the foreground, then end your turn.') || { record_result submit fail "worker-start failed"; return 1; }
  h=$(ont_id '.result.handle // .result.terminal.handle' <<<"$s")
  for i in 1 2 3; do
    out=$(orca-ide terminal send --terminal "$h" --text "trial wake $i" --enter --wait-submit 10 --json 2>&1) || bad=1
    grep -q '"accepted": *false' <<<"$out" && bad=1
  done
  if [ "$bad" = 1 ]; then record_result submit fail "a send failed or a receipt said accepted:false"
  else echo "typed 3 wakes; after the worker's turn ends, check its session log for the 3 texts in order, once each, then run: record_result submit pass|fail <why>" >&2; fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -uo pipefail
  case ${1:-} in
    wake) trial_wake "${2:-}" ;;
    send) trial_send "${2:-}" "${3:-}" ;;
    submit) trial_submit ;;
    -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -6 ;;
    *) echo "usage: orca-native-trial.sh wake|send|submit <phase>" >&2; exit 2 ;;
  esac
fi
