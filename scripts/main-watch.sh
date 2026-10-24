#!/usr/bin/env bash
# main-watch.sh [--install|--uninstall|--job-file|--status|--once|--restart]
#   -- the ONE thing that wakes main. A persistent user service that,
#      every tick, computes the set "finished, not handled" and posts each item
#      to run:<current run>, then proves an idle main woke (wake(): Orca's
#      inbox pointer alone did not). Nothing in main's session is armed, so
#      nothing can be left unarmed.
#
# Finished:
#   - a seat (seat-*.txt) whose pane Orca reads `done` after this service saw
#     it `working`, or `done` with a verdict or marker present (fast work can
#     finish between two ticks). A boot `done` with neither is not finished.
# Stopped without reporting: a seat that finished with no marker or verdict
#   after this service saw it `working`, or whose pane is gone (closed or
#   crashed) after it was seen alive. Never read as success. A seat that sent
#   worker_done has a completed task, so it is handled and never posted. A seat's
#   own completion message to the run or main, or a plan author's plan commit, in
#   the current episode is a finish, never "stopped" (pp_seat_done, issue 320).
# Stalled: a working seat whose session log and pane screen have not changed
#   for STALL_S, or an Orca state neither working nor done held for WAITING_S.
#   Each stall episode is its own item with its own task.
# Machine safety, every tick: leaked Codex plugin brokers are killed (see
#   reap_brokers), a user process count past 2,000 is an item, and finished or
#   orphaned panes are closed (close-done-panes.sh --close).
# Heads-up: every Claude session's "you should know" offer, full text, posted
#   to main's inbox and never typed into a pane (heads_up_capture).
# A live claim in $PP_SCRATCH/heads-up-owner names a project's own watcher
#   (hu_claimed): this one then posts nothing, finished, stopped, stalled or
#   heads-up; the typed nudge and the typed wake still go.
# Handled = main closed the item's Orca task (completed or failed). An item with
# no task gets one on its first post. An open item re-posts every 5 minutes,
# except a heads-up note, which is settled once delivered. A seat a
# `seat.sh wait` watches is that wait's to report, and the typed wake goes only
# while main has unread mail.
# Delivery never counts as handled: a post is a wake, not a disposition.
# Every post is a full context replay for main, so the items due in one tick go
# out as one message, and repeats wait while main's pane is working.
#
# State lives in $PP_SCRATCH/main-watch, beside the seat records it reads, so a
# restart neither loses an item nor re-posts one inside the 5 minutes.
# Test seams: COMMANDECK_NOW (epoch), COMMANDECK_MAIN_WATCH_TICK_S, --once.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/paths.sh" || exit 1
. "$HERE/host-services.sh"
NAME=main-watch
# One job per project, under the plugin's own name on both hosts: the Mac label
# is $HS_PREFIX$JOB, the Linux unit commandeck-$JOB.service.
JOB=$NAME-$(basename "$PP_MAIN" | tr -c 'A-Za-z0-9_.\n-' '-')
[ "$(hs_os)" = Darwin ] && UNIT=$JOB || UNIT=commandeck-$JOB.service
STALL_S=1200    # 20 min with no session-log or pane growth
WAITING_S=120   # 2 min in a state that is neither working nor done
HOLD_S=3600     # 1 h at most that a Builder waiting on its helpers is held unposted (#41)
TICK=${COMMANDECK_MAIN_WATCH_TICK_S:-60}
REPOST=${COMMANDECK_MAIN_WATCH_REPOST_S:-300}
# Where main's pane runs: this checkout, unless main is an orchestrator in another project's checkout that drives
# this repo's units. Without it that main is never found, and every finished seat is posted to no one.
MAIN_AT=${COMMANDECK_MAIN_PANE_DIR:-$PP_MAIN}
SCRATCH=$PP_SCRATCH
ST=$SCRATCH/main-watch
WS=$PP_WORKSPACES
# Claude Code's folder (heads-up offers, transcripts) is the one main last started under, as agent-startup-context.sh
# records it (issue 291, as dashboard.sh reads it): the job runs with no pane's CLAUDE_CONFIG_DIR. With no record yet,
# the one the install ran under (KEEP_ENV). Read again each tick: main may start under another profile while this job runs.
claude_dir() {
  local d
  if d=$(cat "$SCRATCH/claude-config-dir" 2>/dev/null); then
    if [ -n "$d" ]; then export CLAUDE_CONFIG_DIR=$d; else unset CLAUDE_CONFIG_DIR; fi
  fi
  HU_STORE=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/store
}
claude_dir

# The job has no shell of its own: where the install was told the records are
# (paths.sh reads these) goes into the job, or it watches the default folders.
KEEP_ENV=(COMMANDECK_SCRATCH COMMANDECK_WORKSPACES COMMANDECK_ROUTING CODEX_HOME CLAUDE_CONFIG_DIR COMMANDECK_MAIN_PANE_DIR)
# others_job -- the job is named after the checkout's folder alone. Prints the
# other checkout, still on disk, that the job file of this name watches; its
# job is neither replaced nor removed from here.
# shortcut: a path with a character the job file escapes is not recognised, upgrade when the job name carries the path.
others_job() {
  local o
  o=$(sed -n -e 's/^Environment="COMMANDECK_MAIN=\(.*\)"$/\1/p' -e 's/.*<key>COMMANDECK_MAIN<\/key><string>\([^<]*\)<.*/\1/p' "$(job_file)" 2>/dev/null | head -1)
  [ -n "$o" ] && [ "$(pp_norm "$o")" != "$(pp_norm "$PP_MAIN")" ] && [ -d "$o" ] && printf '%s\n' "$o"
}
job_file() { [ "$(hs_os)" = Darwin ] && echo "$HOME/Library/LaunchAgents/$HS_PREFIX$JOB.plist" || echo "$HOME/.config/systemd/user/$UNIT"; }
# merge_live -- 0 while a merge job merge_start started has written no exit and its pid lives.
merge_live() {
  local p
  for p in "$ST"/mergejob-*.pid; do [ -f "$p" ] && [ ! -e "${p%.pid}.rc" ] && kill -0 "$(cat "$p")" 2>/dev/null && return 0; done
  return 1
}
# restart_job -- (re)load the job from its file, then keep that file's cksum in job-sum: a job file whose cksum is
# not there was written by an --install whose restart has not happened yet (restart_due).
restart_job() {
  if [ "$(hs_os)" = Darwin ]; then
    launchctl bootout "gui/$(id -u)/$HS_PREFIX$JOB" 2>/dev/null || true
    # bootout returns before the job is gone; bootstrapping in that window fails (error 5).
    for _ in $(seq 50); do launchctl print "gui/$(id -u)/$HS_PREFIX$JOB" >/dev/null 2>&1 || break; sleep 0.1; done
    launchctl bootstrap "gui/$(id -u)" "$(job_file)" || return 1
  else
    # restart, not enable --now: over a running job (an update) that would leave the old process.
    systemctl --user daemon-reload && systemctl --user enable "$UNIT" && systemctl --user restart "$UNIT" || return 1
  fi
  mkdir -p "$ST" && cksum < "$(job_file)" > "$ST/job-sum"
}
# restart_later -- the restart as a job of its own (`--restart`, via hs_start: a launchd job, a systemd-run unit), never
# a child of the watcher's job, so stopping the watcher cannot stop it. It waits until no merge job lives.
restart_later() {
  ! hs_active "$JOB-restart.service" || return 0
  local k envs=("PATH=$PATH" "HOME=$HOME" "COMMANDECK_MAIN=$PP_MAIN")
  for k in "${KEEP_ENV[@]}"; do [ -z "${!k:-}" ] || envs+=("$k=${!k}"); done
  hs_start "$JOB-restart" 64M "${envs[@]}" -- "$BASH" "$HERE/$NAME.sh" --restart
}
# restart_due -- the one retry, read every tick: the job file differs from the one last loaded (an --install's restart
# was lost, or job-sum is gone) and no merge job lives; restart_later skips when its job already runs. A watcher
# installed before this code is reinstalled by hand once: that --install rewrites its job file and restarts it
# (main-watch-auto-merge.test.sh).
restart_due() {
  local f; f=$(job_file)
  [ -f "$f" ] && [ "$(cksum < "$f")" != "$(cat "$ST/job-sum" 2>/dev/null)" ] && ! others_job >/dev/null && ! merge_live
}
# A restart never runs inside the watcher's job while a merge it started lives: a merge's own Post-merge
# `main-watch.sh --install` hands it to restart_later. The job settings (AbandonProcessGroup, KillMode=process) keep a
# restart of the watcher from stopping any other child of it.
install() {
  local o
  if o=$(others_job); then
    echo "main-watch: the job $JOB already watches $o, a checkout with the same folder name; one of the two folders needs another name. Nothing installed" >&2
    return 1
  fi
  if [ "$(hs_os)" = Darwin ]; then
    local plist=$HOME/Library/LaunchAgents/$HS_PREFIX$JOB.plist k
    mkdir -p "${plist%/*}"
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$HS_PREFIX$JOB</string>
<key>ProgramArguments</key><array><string>$(hs__xml "$BASH")</string><string>$(hs__xml "$HERE/$NAME.sh")</string></array>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>$(hs__xml "$PATH")</string><key>HOME</key><string>$(hs__xml "$HOME")</string><key>COMMANDECK_MAIN</key><string>$(hs__xml "$PP_MAIN")</string>$(for k in "${KEEP_ENV[@]}"; do [ -z "${!k:-}" ] || printf '<key>%s</key><string>%s</string>' "$k" "$(hs__xml "${!k}")"; done)</dict>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>AbandonProcessGroup</key><true/>
<key>StandardOutPath</key><string>$(hs__xml "$SCRATCH/scratchpad/$NAME.log")</string>
<key>StandardErrorPath</key><string>$(hs__xml "$SCRATCH/scratchpad/$NAME.log")</string>
</dict></plist>
EOF
    # launchd does not make the log's folder, and will not start a job whose log it cannot open.
    mkdir -p "$SCRATCH/scratchpad" || return 1
  else
    local unit=$HOME/.config/systemd/user/$UNIT
    mkdir -p "${unit%/*}"
    cat > "$unit" <<EOF
[Unit]
Description=Commandeck main-watch: wakes main while anything finished is unhandled

[Service]
ExecStart="$(hs__sd "$BASH")" "$(hs__sd "$HERE/$NAME.sh")"
Environment="PATH=$(hs__sd "$PATH")"
Environment="HOME=$(hs__sd "$HOME")"
Environment="COMMANDECK_MAIN=$(hs__sd "$PP_MAIN")"
$(for k in "${KEEP_ENV[@]}"; do [ -z "${!k:-}" ] || printf 'Environment="%s=%s"\n' "$k" "$(hs__sd "${!k}")"; done)
Restart=always
RestartSec=10
KillMode=process
MemoryMax=512M

[Install]
WantedBy=default.target
EOF
  fi
  if merge_live; then LATER=1; restart_later; else restart_job; fi
}

uninstall() {
  ! others_job >/dev/null || return 0
  if [ "$(hs_os)" = Darwin ]; then
    launchctl bootout "gui/$(id -u)/$HS_PREFIX$JOB" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$HS_PREFIX$JOB.plist"
  else
    systemctl --user disable --now "$UNIT" 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/$UNIT"
    systemctl --user daemon-reload
  fi
}

case "${1:-}" in
  --uninstall) uninstall; echo "main-watch uninstalled"; exit 0 ;;
  --job-file) job_file; exit 0 ;;
  --install) install || { echo "main-watch: install FAILED; nothing wakes main" >&2; exit 1; }
             [ -z "${LATER:-}" ] && echo "main-watch installed and started" \
               || echo "main-watch installed; it restarts once the running merge job ends (job $JOB-restart)"; exit 0 ;;
  # restart_later's job: an uninstall while it waits leaves nothing to load.
  --restart) while merge_live; do sleep 1; done; [ ! -f "$(job_file)" ] || restart_job; exit ;;
  --status) if hs_active "$UNIT"; then echo "main-watch: running"; exit 0; fi
            echo "MAIN-WATCH NOT RUNNING -- nothing wakes main; bash $(printf '%q' "$HERE")/main-watch.sh --install"; exit 1 ;;
  --once|"") ;;
  *) echo "usage: main-watch.sh [--install|--uninstall|--job-file|--status|--once|--restart]" >&2; exit 2 ;;
esac
mkdir -p "$ST" || exit 1
[ -e "$ST/since" ] || : > "$ST/since"

# post <key> <task or empty> <subject> <body> [once] -- the whole handled/re-post
# rule. `once`: an item already delivered is settled, never re-posted.
post() {
  local f=$ST/item-$1 task=$2 last status y
  [ -e "$f" ] && grep -qx handled "$f" && return 0
  # Under a live claim the project's watcher posts every item. One it has run a whole cycle past (at= after this
  # watcher's first sighting) it posted; any other waits here, and is posted once the claim ends. A post is not
  # main handling it: it is recorded as posted at the owner's last cycle, its task kept, so once the claim ends
  # the item is reminded on the usual cadence until main closes its task.
  if [ "${CLAIMED:-0}" = 1 ]; then
    y=$(cat "$ST/yield-$1" 2>/dev/null) || { echo "$NOW" > "$ST/yield-$1"; return 0; }
    [ -e "$f" ] && task=$(sed -n 's/^task=//p' "$f")
    [ "$HU_AT" -le "$y" ] || printf 'posted=%s\ntask=%s\n' "$HU_AT" "$task" > "$f"
    return 0
  fi
  rm -f "$ST/yield-$1"
  [ -e "$f" ] && task=$(sed -n 's/^task=//p' "$f")
  last=$(sed -n 's/^posted=//p' "$f" 2>/dev/null)
  if [ -z "$task" ] || [ "$task" = none ]; then
    orca_op '' "$HERE/orca-task-create.sh" --run "$RUN" ${FROM:+--from "$FROM"} \
      --spec "main-watch item: $3. Complete this task once main has handled it; until then it is re-posted every 5 minutes." \
      || { echo "main-watch: no task for $1: $OP_ERR" >&2; note "${3#main-watch: }: $OP_ERR" "$1"; return 0; }
    task=$OP_OUT
    # Recorded before the send, so a failed send never mints a second task.
    printf 'posted=%s\ntask=%s\n' "${last:-}" "$task" > "$f"
  else
    status=$(jq -r --arg t "$task" 'first(.result.tasks[]? | select(.id == $t) | .status) // "absent"' <<<"$TASKS")
    case $status in
      completed|failed) echo handled > "$f"; return 0 ;;
      # Not in this run's task list: another run's seat, never this main's.
      absent) return 0 ;;
    esac
  fi
  [ -n "$last" ] && [ "${5:-}" = once ] && { echo handled > "$f"; return 0; }
  [ -n "$last" ] && [ $((NOW - last)) -lt "$REPOST" ] && return 0
  # A repeat waits while main is mid-turn: main is awake, and the post would only
  # queue another full replay behind that turn. A first post is never held.
  [ -n "$last" ] && [ "$MAIN_BUSY" = 1 ] && return 0
  DUE_KEY+=("$1"); DUE_TASK+=("$task"); DUE_SUBJ+=("$3")
  # pp_task_close, not a bare task-update: a seat's task keeps its supervised
  # dispatch active, and Orca refuses the update until that dispatch is ended.
  DUE_BODY+=("$4"$'\n'"handled = close task $task: (. $(printf '%q' "$HERE")/paths.sh && pp_task_close $task completed)")
}

# builder_card <unit> <launched> -- the Builder's card from the rows of its event log since that launch.
builder_card() {
  # One read of the session record from where the last tick stopped (issue 299); its state is in $PP_SCRATCH.
  pp_session_summary "$WS/$1"
  jq -cR --argjson la "$2" 'fromjson? | objects | select((try (.ts | sub("\\.[0-9]+"; "") | fromdateiso8601) catch null) as $t | $t == null or $t >= $la)' "$WS/$1/.claude/builder-events.jsonl" 2>/dev/null \
    | jq -cs --argjson now "$NOW" --argjson sessionAt "$PP_SESSION_AT" --argjson bgOpen "$PP_SESSION_BG" \
      --argjson cache "$PP_SESSION_CACHE" --argjson tick "$TICK" -f "$HERE/dashboard_builders.jq" 2>/dev/null
}
# helper_out <unit> <launched> -- a helper or a review pass the Builder started has not finished: a helper
# that logged a row within STALL_S, or a pass started within HOLD_S. A Builder that ended its turn to wait on
# it is waiting, not stopped (#41). A pass logs only its start and end rows, so its start is the clock; a helper
# silent past STALL_S, or a pass killed with no end row, died, so the Builder's stop is real and is posted.
helper_out() {
  [ -f "$WS/$1/.claude/builder-events.jsonl" ] || return 1
  builder_card "$1" "$2" | jq -e --argjson now "$NOW" --argjson s "$STALL_S" --argjson hold "$HOLD_S" \
    'any(.waiting[]; (.kind == "subagent" and ($now - (.seenAt | sub("\\.[0-9]+"; "") | fromdateiso8601) | . >= 0 and . < $s))
      or (.kind == "codex" and ($now - (.since | sub("\\.[0-9]+"; "") | fromdateiso8601) | . >= 0 and . < $hold)))' >/dev/null 2>&1
}

# stopped_nudge <unit> <handle> <item> -- issue 258: a Builder that ended its turn with no DONE line or verdict is
# typed one line before main is asked, at most twice per pane (builder_watch's history file), and never while an
# open decision names its unit (a ledger that cannot be read holds too). 0: nudged, or nudged within REPOST, so hold
# the post; 1: post, with NUDGED set when this stop was nudged.
stopped_nudge() {
  local hist=$ST/builder-$1-$2 at holds
  NUDGED=""
  at=$(awk -v i="$3" '$1 == "STOPPED" && $2 == i { print $3 }' "$hist" 2>/dev/null | tail -1)
  if [ -n "$at" ]; then
    [ $((NOW - at)) -ge "$REPOST" ] || return 0
    NUDGED=" Nudged $(( (NOW - at) / 60 )) min ago, and still stopped."; return 1
  fi
  [ "$(cat "$hist" 2>/dev/null | grep -c '^STOPPED ')" -lt 2 ] || return 1
  holds=$(COMMANDECK_MAIN=$PP_MAIN bash "$HERE/decision.sh" holds "$1" 2>/dev/null) || return 1
  ! grep -q '^Open question to the owner ' <<<"$holds" || return 1
  # Recorded before the send, as builder_watch's nudges are: a send that fails is not retried.
  echo "STOPPED $3 $NOW" >> "$hist"
  orca-ide terminal send --terminal "$2" --text "Signal STOPPED: you ended your turn with no DONE line or verdict. If you are waiting on an answer, say what in one line and end your turn; this is not an answer. Otherwise continue the batch." --enter >/dev/null 2>&1 \
    && pp_wake_log main-watch "$2" "nudge STOPPED $1" sent \
    || { echo "main-watch: nudge to $2 for $1 failed" >&2; pp_wake_log main-watch "$2" "nudge STOPPED $1" refused; }
  return 0
}

# builder_watch -- each working Builder seat's event log through
# dashboard_builders.jq. The first sighting of a signal episode ({kind, since})
# types one line into that pane and records the episode under $ST, so it never
# repeats across ticks or a restart. Main is woken only when the nudge did not
# help: the pane's third episode, or one lasting past 3x its limit. The
# dashboard card shows every signal; this function only types one line and
# posts, and no path in it ends, closes or relaunches a pane.
builder_watch() {
  local r u h out sig kind since lim text n state hist la anchor
  for r in "$SCRATCH"/seat-*-builder.txt; do
    # A record the origin run placed is that run's to watch, as in the seat loop.
    [ -f "$r" ] && ! grep -q '^origin=' "$r" || continue
    u=$(sed -n 's/^unit=//p' "$r" | head -1); h=$(sed -n 's/^handle=//p' "$r" | head -1)
    [ -n "$u" ] && [ -n "$h" ] && [ -f "$WS/$u/.claude/builder-events.jsonl" ] || continue
    # Episodes are per pane: a replacement pane's first signal is its first, not the old pane's third.
    hist=$ST/builder-$u-$h
    # A pane that is not mid-turn is main-watch's own item, not a signal. WARM alone also acts on done and idle: Orca
    # reads a Builder waiting on a background job or helper as working or done, so WARM trusts the session log's
    # end_turn marker (cache.ended) for "at the prompt". waiting, blocked and none never get one.
    state=$(awk -F'\t' -v h="$h" '$1 == h { print $2; exit }' <<<"$STATES")
    case $state in working|done|idle) ;; *) continue ;; esac
    # The log outlives a crashed Builder: only rows since this pane's launch are
    # its own, or it is nudged for a call the dead pane never ended.
    la=$(sed -n 's/^launched=//p' "$r" | head -1); [[ "$la" =~ ^[0-9]+$ ]] || la=0
    out=$(builder_card "$u" "$la") || continue
    while IFS= read -r sig; do
      [ -n "$sig" ] || continue
      kind=$(jq -r '.kind | ascii_upcase' <<<"$sig"); since=$(jq -r .since <<<"$sig"); lim=$(jq -r '.limitSec // 0' <<<"$sig")
      [ "$kind" = WARM ] || [ "$state" = working ] || continue
      if [ "$kind" = WARM ]; then
        # Its own history, never a row in $hist: the episode count below reads only $hist, so a ping cannot push a
        # later QUIET, STUCK or LOOP over the third-episode line, and WARM never posts to main. One line per window
        # (each . reply moves since); at most maxPings lines per anchor, which only the parent's own call moves.
        anchor=$(jq -r .anchor <<<"$sig")
        grep -qxF -- "$since $anchor" "$hist.warm" 2>/dev/null && continue
        n=$(grep -cxE -- "[0-9]+ $anchor" "$hist.warm" 2>/dev/null)
        [ "${n:-0}" -lt "$(jq -r .maxPings <<<"$sig")" ] || continue
        echo "$since $anchor" >> "$hist.warm"
        orca-ide terminal send --terminal "$h" --text "Signal WARM: keep-alive while you wait. Reply with one . and end your turn." --enter >/dev/null 2>&1 \
          && pp_wake_log main-watch "$h" "nudge WARM $u" sent \
          || { echo "main-watch: nudge to $h for $u failed" >&2; pp_wake_log main-watch "$h" "nudge WARM $u" refused; }
        continue
      fi
      case $kind in
        STUCK) text="Signal STUCK: one tool call has run for over $((lim / 60)) min. If you are waiting on it, say what; otherwise interrupt it and continue the batch." ;;
        QUIET) text="Signal QUIET: no tool call for $lim s. If you are waiting on something, say what; otherwise continue the batch." ;;
        *) text="Signal LOOP: the same call 3 times, or 4 failed calls in a row. Try a different approach, or say what blocks you." ;;
      esac
      # Recorded before the send: a nudge that fails is not retried, so one episode never sends twice.
      if ! grep -qxF -- "${kind} $since" "$hist" 2>/dev/null; then
        echo "${kind} $since" >> "$hist"
        orca-ide terminal send --terminal "$h" --text "$text" --enter >/dev/null 2>&1 && pp_wake_log main-watch "$h" "nudge $kind $u" sent \
          || { echo "main-watch: nudge to $h for $u failed" >&2; pp_wake_log main-watch "$h" "nudge $kind $u" refused; }
      fi
      n=$(grep -nxF -- "${kind} $since" "$hist" | head -1 | cut -d: -f1)
      if [ "${n:-0}" -ge 3 ] || { [ "$lim" -gt 0 ] && [ $((NOW - since)) -gt $((lim * 3)) ]; }; then
        post "builder-$u-$kind-$since" "" "main-watch: Builder $u is $kind and the nudge did not help" \
          "Builder $u (pane $h) has signal $kind since epoch $since; it was nudged once. Episodes on this pane so far: $(wc -l < "$hist" | tr -d ' '). The dashboard card for $u shows its steps."
      fi
    done < <(jq -c '.signals[]?' <<<"$out")
  done
}

# flush -- every item due this tick goes out as ONE message, since each post is a
# full context replay for main. Each item keeps its own task and posted time.
flush() {
  local n=${#DUE_KEY[@]} i subj body="" type=question
  [ "$n" -gt 0 ] || return 0
  # Issue 318: a heads-up is a note to verify, not a wake: as a status it is held for main's next wake.
  [ "$RELAY" = 0 ] || type=status
  if [ "$n" = 1 ]; then subj=${DUE_SUBJ[0]} body=${DUE_BODY[0]}
  else
    # orca-wait.sh prints a `heads-up:` subject's body whole; keep the prefix.
    subj="main-watch: $n items need you"; [ "$RELAY" = 0 ] || subj="heads-up: $n notes"
    for i in "${!DUE_KEY[@]}"; do body+="$((i + 1)). ${DUE_SUBJ[i]}"$'\n'"${DUE_BODY[i]}"$'\n\n'; done
  fi
  if orca_op '.ok == true' orca-ide orchestration send --run "$RUN" --to "run:$RUN" ${FROM:+--from "$FROM"} --type "$type" \
       --subject "$subj" --body "$body" --json; then
    pp_wake_log main-watch "run:$RUN" "flush $n item(s)" sent
    for i in "${!DUE_KEY[@]}"; do printf 'posted=%s\ntask=%s\n' "$NOW" "${DUE_TASK[i]}" > "$ST/item-${DUE_KEY[i]}"; done
    # A heads-up relay is inbox only: nothing is ever typed for it.
    [ "$RELAY" = 0 ] || return 0
    # IN THE INBOX IS NOT AWAKE: an idle main missed ~16 accepted
    # sends, two merge-ready STOPs among them. The wake is its own record, proven
    # by wake() and retried without a second message. An idle main the inbox
    # pointer already started reads working now, and needs nothing typed.
    printf '0\n%s\n%s\n' "${DUE_TASK[*]}" "$RUN" > "$ST/wake"
    if [ "$MAIN_BUSY" = 0 ]; then main_now; [ "$MAIN_STATE" != working ] || rm -f "$ST/wake"; fi
  else
    local s; s=$(printf '%s, ' "${DUE_SUBJ[@]#main-watch: }")
    echo "main-watch: send refused for $n item(s): $OP_ERR" >&2
    pp_wake_log main-watch "run:$RUN" "flush $n item(s)" refused "$OP_ERR"
    # A refused relay retries next tick from its saved text, still untyped.
    [ "$RELAY" = 0 ] || return 0
    note "${s%, }: send refused: $OP_ERR" "${DUE_KEY[@]}"
  fi
}

# note <text> [item key...] -- one undelivered item, or the reason a repair
# failed, for this tick's diagnostic (arm_diag).
note() { DIAG+="${DIAG:+; }$1"; shift; [ "$#" = 0 ] || DIAG_KEYS+=$(printf '%s\n' "$@")$'\n'; }

# orca_op <jq test of a good reply, or '' for the exit alone> <command...> -- one
# Orca call. A fenced refusal ("no longer bound to Run") is repaired by rebind
# and the call retried once. Leaves the reply in OP_OUT and, on failure, Orca's
# real reason in OP_ERR: a nonzero exit and an ok:false reply both fail.
orca_op() {
  local good=$1 rc try i; shift
  local args=("$@")
  for try in 1 2; do
    OP_OUT=$("${args[@]}" 2>"$ST/op-err"); rc=$?
    [ "$rc" = 0 ] && { [ -z "$good" ] || jq -e "$good" >/dev/null 2>&1 <<<"$OP_OUT"; } && return 0
    OP_ERR=$({ cat "$ST/op-err"; jq -r '.error.message // .error.code // empty' <<<"$OP_OUT" 2>/dev/null || printf '%s' "$OP_OUT"; } | tr '\n' ' ' | cut -c1-300)
    OP_ERR=${OP_ERR:-exit $rc with no answer}
    [ "$try" = 1 ] && grep -qiE 'no longer bound|not bound to' <<<"$OP_ERR" && rebind || return 1
    # rebind re-resolved main: a pane that restarted mid-tick is the sender now.
    for ((i = 0; i < ${#args[@]}; i++)); do [ "${args[i]}" != --from ] || args[i+1]=$FROM; done
  done
}

# rebind -- once a tick, bind the run to main's own pane after a fenced refusal
# (a job under the old main's handle took the run, then that pane closed). Only when no live pane holds the run: a live coordinator, whoever
# it is, keeps it, and main is told instead. 0 = the run is main's again.
rebind() {
  [ -z "$REBOUND" ] || return 1
  REBOUND=1
  main_now
  local r why
  if [ -z "$MAIN_H" ]; then why="no main pane to rebind run $RUN to"
  elif [ "$COORD" = '?' ]; then why="the run list did not answer, so who holds run $RUN is unknown; not rebound"
  elif [ "$COORD_LIVE" != 0 ] && [ "$COORD" != "$MAIN_H" ]; then why="run $RUN is held by live pane $COORD; not taken from it"
  else
    r=$(orca-ide orchestration run-use --id "$RUN" --from "$MAIN_H" --json 2>&1) && jq -e '.ok == true' >/dev/null 2>&1 <<<"$r" \
      && { echo "main-watch: rebound run $RUN to main $MAIN_H" >&2; return 0; }
    why="rebinding run $RUN to $MAIN_H failed: $(tr '\n' ' ' <<<"$r" | cut -c1-200)"
  fi
  echo "main-watch: $why" >&2; note "$why"; return 1
}

# arm_diag -- what Orca would not take this tick reaches main as one typed line
# (wake), since no inbox holds it; a task-create failure leaves no task to name.
# Items main already heard about for this run are not repeated inside REPOST; a
# new one is told at once. The items stay pending, so a later send delivers them.
arm_diag() {
  [ -n "$DIAG" ] || return 0
  local keys at tasks=
  keys=$(sort -u <<<"$DIAG_KEYS" | sed '/^$/d')
  at=$(sed -n 1p "$ST/diag" 2>/dev/null)
  [ -n "$at" ] && [ $((NOW - at)) -lt "$REPOST" ] && [ "$(sed -n 2p "$ST/diag")" = "$RUN" ] \
    && [ -z "$(comm -23 <(printf '%s\n' "$keys") <(sed 1,2d "$ST/diag" | sort -u))" ] && return 0
  printf '%s\n%s\n%s\n' "$NOW" "$RUN" "$keys" > "$ST/diag"
  [ "$(sed -n 3p "$ST/wake" 2>/dev/null)" = "$RUN" ] && tasks=$(sed -n 2p "$ST/wake")
  printf '0\n%s\n%s\n%s\n' "$tasks" "$RUN" "$(cut -c1-800 <<<"$DIAG")" > "$ST/wake"
}

# resolve_main <worktree ps JSON> <terminal list JSON> -- sets MAIN_H and
# MAIN_STATE (Orca's state for that pane, `none` when unknown), COORD (the run's
# coordinator, `?` when the run list did not answer) and COORD_LIVE (that pane
# is listed), and FROM, the --from of every send: a service has no terminal of its own, and Orca refuses a send it
# cannot attribute. FROM is main's pane, else the run's live coordinator, else what pp_sender finds (issue 321: Orca
# can list main's pane with no agentIdentity); only MAIN_H is ever typed into. Found every tick, so /clear and a
# restarted pane need nothing re-pinned. Only a claude pane in the main checkout
# is main, so a worker or shell holding the run is never typed into. The run's
# coordinator comes first: an old main pane left open after a restart is also a
# claude pane in the main checkout, and Orca refuses its sends ("no longer
# bound to Run").
resolve_main() {
  COORD=$(pp_run_coord "$RUN") || COORD='?'
  COORD_LIVE=$(jq -r --arg c "$COORD" '[(.result | if type == "array" then . else (.terminals // []) end)[]? | select(.handle == $c)] | length' <<<"$2" 2>/dev/null)
  MAIN_H=$(jq -r --arg m "$MAIN_AT" --arg c "$COORD" "$PP_PNORM"'($m | pnorm) as $m | [(.result | if type == "array" then . else (.terminals // []) end)[]?
    | select((.worktreePath | pnorm) == $m and .agentIdentity == "claude")] | first((.[] | select(.handle == $c)), .[] | .handle) // empty' <<<"$2" 2>/dev/null)
  MAIN_STATE=$(jq -rn --argjson ps "$1" --argjson ts "$2" --arg h "$MAIN_H" '
    ([$ps.result.worktrees[]?.agents[]?] | map({(.paneKey // ""): .state}) | add // {}) as $a
    | first(($ts.result | if type == "array" then . else (.terminals // []) end)[]? | select(.handle == $h)
      | $a["\(.tabId):\(.leafId)"]) // "none"' 2>/dev/null)
  [ -n "$MAIN_STATE" ] || MAIN_STATE=none
  FROM=$(pp_sender "$MAIN_H" "$([ "$COORD" = '?' ] || [ "${COORD_LIVE:-0}" = 0 ] || echo "$COORD")") || FROM=
}
main_now() { # main as Orca sees it at this moment, not at the start of the tick
  resolve_main "$(listing worktree ps || echo '{}')" "$(listing terminal list || echo '{}')"
}
state_now() { # <handle> -- the pane's Orca agent state at this moment, joined as STATES is; empty when unlisted
  jq -rn --argjson ps "$(listing worktree ps || echo '{}')" --argjson ts "$(listing terminal list || echo '{}')" --arg h "$1" '
    ([$ps.result.worktrees[]?.agents[]?] | map({(.paneKey // ""): .state}) | add // {}) as $a
    | first(($ts.result | if type == "array" then . else (.terminals // []) end)[]? | select(.handle == $h) | $a["\(.tabId):\(.leafId)"]) // empty' 2>/dev/null
}

# listing <orca-ide subcommand...> -- a pane listing, printed only when Orca
# answered one: Orca can exit 0 with an RPC error body, which holds no panes and
# would read as "every pane is gone". 1 = no listing.
listing() {
  local o
  o=$(orca-ide "$@" --json 2>/dev/null) && jq -e '.result' >/dev/null 2>&1 <<<"$o" && printf '%s\n' "$o"
}

# wake -- the pending wake of an accepted send: one line typed into main's pane,
# counted only when Orca's receipt shows the turn it started (turn_started, the
# seat.sh receipt contract). Never typed into a pane that is working, in any
# state but idle/done, or waiting on a person (PROMPT_BLOCKED); those keep it
# for a later tick. An unproven wake is retried WAKE_TRIES times, one a tick,
# then dropped: the item re-posts after 5 minutes anyway. Main's mail is never
# acknowledged here.
# A fourth line is arm_diag's diagnostic: what Orca refused, typed whatever
# became of the tasks, and never called inbox mail.
WAKE_TRIES=3
# mail_wake -- actionable mail unread while main is idle arms the same proven wake: two orders once sat 13 minutes with
# main idle, because only this watcher's own posts ever got a wake. Issue 318: only a wakeKinds type counts, sent to
# the run or to main's handle, by anyone (main-watch itself sends from main's handle); wake() holds it until its
# window closes, and takes the window's one wake claim (pp_wake_claim, unread-since) as it types, so an unanswered main
# is typed at most once per window, by this or Orca's nudge. A full page or no answer is not read.
mail_wake() {
  local a
  a=$(pp_inbox_actionable "$RUN" "${MAIN_H:-}") || return 0
  [ "$a" != '[]' ] || return 0
  [ ! -e "$ST/wake" ] || return 0
  # Issue 331: a listing with no pane for main arms the wake too, so wake() logs no_pane and the 10-minute alert can fire;
  # otherwise mail waiting for a main that is gone left no trace.
  case $MAIN_STATE in idle|done) ;; none) { [ -z "$MAIN_H" ] && [ "$LISTED" = 1 ]; } || return 0 ;; *) return 0 ;; esac
  # A task id nothing knows reads as open in wake(), which then re-checks the inbox itself.
  printf '0\nmail\n%s\n' "$RUN" > "$ST/wake"
}
# tell_relay <why> <fix> -- wake() gave up on main (a prompt open in its pane, or no wake proven): the relay hears,
# once per wake episode (the wake's task list, kept in wake-told), through main's run under main's handle, as
# flush() sends. Only a send Orca took marks the episode told, so a refused one is tried again next tick.
tell_relay() {
  [ -d "$PP_WORKSPACES/Chief-of-Staff" ] && [ "$(cat "$ST/wake-told" 2>/dev/null)" != "$tasks" ] || return 0
  orca_op '.ok == true' orca-ide orchestration send --run "$RUN" --to "run:$RUN" ${FROM:+--from "$FROM"} --type status \
    --subject "cos: main-watch: main has not read finished work" \
    --body "$(wc -w <<<"$tasks" | tr -d ' ') item(s) wait unread in main's inbox for run $RUN: $1. Fix: $2." --json \
    && { printf '%s\n' "$tasks" > "$ST/wake-told"; pp_wake_log main-watch "run:$RUN" "tell relay: $1" sent; return 0; }
  pp_wake_log main-watch "run:$RUN" "tell relay: $1" refused "${OP_ERR:-}"
  return 1
}
# relay_picker <terminal list json> -- an open picker blocks the relay pane itself, and its mail waits behind it
# (issue 232). While the relay's screen shows a prompt and messages to it wait unread, $ST/relay-picker.json holds
# {since, waiting}; the dashboard raises "picker open N min" from it at 30 minutes. Nothing is sent to the pane.
relay_picker() {
  local h screen n f=$ST/relay-picker.json
  h=$(jq -r --arg p "$PP_WORKSPACES/Chief-of-Staff" "$PP_PNORM"'($p | pnorm) as $p | first((.result | if type == "array" then . else (.terminals // []) end)[]?
    | select((wtp | pnorm) == $p) | .handle) // empty' <<<"$1" 2>/dev/null)
  if [ -n "$h" ] && screen=$(orca-ide terminal read --terminal "$h" --screen --json 2>/dev/null | jq -r '.result.terminal.tail | if type == "array" then .[] else error end' 2>/dev/null) \
     && grep -qiE "$PROMPT_BLOCKED" <<<"$screen" \
     && n=$(orca-ide orchestration inbox --terminal "$h" --limit 500 --json 2>/dev/null | jq -er --arg h "$h" \
       '.result.messages | if type == "array" then [.[] | select(.read == 0 and (.to_handle // $h) == $h)] | length else error end' 2>/dev/null) \
     && [ "$n" -gt 0 ]; then
    local since; since=$(jq -r '.since // empty' "$f" 2>/dev/null); [[ $since =~ ^[0-9]+$ ]] || since=$NOW
    printf '{"since":%s,"waiting":%s}\n' "$since" "$n" > "$f"
  else
    rm -f "$f"
  fi
}
# wake_result <result> [error] -- the pane wake's one outcome: written to the wake log, and the failing streak kept. A
# failure writes $ST/wake-streak as "<start> <result>" (the start stays while the same failure repeats; another one
# restarts it); only turn_started deletes it. Inbox mail (flush, its reposts) and held are not a woken pane: they neither
# start nor clear a streak. A streak of 10 minutes tells the relay once ($ST/wake-alert).
wake_result() {
  local r=$1 start= res=
  pp_wake_log main-watch "${MAIN_H:-main}" wake "$@"
  case $r in
    turn_started) rm -f "$ST/wake-streak" "$ST/wake-alert"; return 0 ;;
    held) return 0 ;;
  esac
  read -r start res < "$ST/wake-streak" 2>/dev/null || true
  if [ "$res" != "$r" ] || [ -z "$start" ]; then start=$NOW; echo "$start $r" > "$ST/wake-streak"; rm -f "$ST/wake-alert"; fi
  if [ $((NOW - start)) -ge 600 ] && [ ! -e "$ST/wake-alert" ]; then
    tell_relay "main has not been woken for $(((NOW - start) / 60)) minutes ($r)" "restart main" && : > "$ST/wake-alert"
  fi
  return 0
}
wake() {
  [ -e "$ST/wake" ] || return 0
  local tries tasks t open=0 screen r diag text
  tries=$(sed -n 1p "$ST/wake"); tasks=$(sed -n 2p "$ST/wake"); diag=$(sed -n 4p "$ST/wake")
  # Mail another run's inbox took is that run's; main switched away from it.
  [ "$(sed -n 3p "$ST/wake")" = "$RUN" ] || { rm -f "$ST/wake"; return 0; }
  for t in $tasks; do
    case $(jq -r --arg t "$t" 'first(.result.tasks[]? | select(.id == $t) | .status) // "open"' <<<"$TASKS") in
      completed|failed) ;; *) open=1 ;;
    esac
  done
  [ "$open" = 1 ] || [ -n "$diag" ] || { rm -f "$ST/wake"; return 0; }
  # Nothing actionable unread, nothing typed: main drained its inbox and only the item's
  # task is open, so a typed wake read "nothing was queued". An inbox Orca does
  # not answer keeps the wake, and so does a full page: the inbox is the whole
  # machine's, newest first, and this run's unread mail may be behind it.
  # Issue 318: while the oldest is younger than the window the wake waits, untried, so what arrives meanwhile wakes
  # main once, at the close, as Orca's nudges do (cos-own-echo.sh). A diagnostic is typed at once.
  local unread
  if [ "$open" = 1 ] && unread=$(pp_inbox_actionable "$RUN" "${MAIN_H:-}"); then
    if [ "$unread" = '[]' ]; then open=0; [ -n "$diag" ] || { rm -f "$ST/wake"; return 0; }
    elif [ -z "$diag" ] && pp_wake_window_open "$unread" "$NOW"; then return 0; fi
  fi
  if [ "${tries:-0}" -ge "$WAKE_TRIES" ] 2>/dev/null; then
    # Main's session log written since the first try is a main at work again (a new session, a restart): the
    # relay is not told to restart a pane that healed itself (issue 238).
    local at; at=$(pp_session_log_at "$MAIN_AT")
    if [ "$at" != null ] && [ "$at" -gt "$(cat "$ST/wake-first" 2>/dev/null || echo "$NOW")" ]; then
      echo "main-watch: wake not proven, but main's session log moved since the first try; nothing told" >&2
      rm -f "$ST/wake"; return 0
    fi
    echo "main-watch: wake not proven after $WAKE_TRIES tries; the items re-post in 5 minutes" >&2
    tell_relay "main did not wake after $WAKE_TRIES typed wakes" "restart main"
    wake_result gave_up "after $WAKE_TRIES typed wakes"
    rm -f "$ST/wake"; return 0
  fi
  main_now
  [ -n "$MAIN_H" ] || { echo "main-watch: no main pane to wake" >&2; wake_result no_pane "no live pane in $MAIN_AT"; return 0; }
  case $MAIN_STATE in idle|done) ;; *) return 0 ;; esac
  screen=$(orca-ide terminal read --terminal "$MAIN_H" --screen --json 2>/dev/null | jq -r '.result.terminal.tail | if type == "array" then .[] else error end' 2>/dev/null) \
    || { echo "main-watch: main's screen is unreadable; no wake typed" >&2; wake_result unreadable "terminal read failed"; return 0; }
  ! grep -qiE "$PROMPT_BLOCKED" <<<"$screen" || { tell_relay "main's pane shows an open question or permission prompt" "answer the prompt in main's pane"; wake_result blocked "open prompt in main's pane"; return 0; }
  text="main-watch: items are waiting in your Orca inbox for run $RUN; read them and handle each."
  # The recovery is built here, outside the stored reason arm_diag truncates, and
  # the command ends the line so it can be copied whole. It is offered only when
  # no live pane holds the run (rebind's own test, on main_now's fresh answer):
  # run-use from main would fence a live holder, so that one is named instead.
  local fix=" To take the run back, run this from your own pane: orca-ide orchestration run-use --id $RUN"
  if [ "$COORD" = '?' ]; then fix=" Who holds run $RUN is unknown; reconcile first: find out what that pane is before taking the run."
  elif [ "$COORD_LIVE" != 0 ] && [ "$COORD" != "$MAIN_H" ]; then fix=" Live pane $COORD holds run $RUN; reconcile first: find out what that pane is before taking the run."
  fi
  [ -z "$diag" ] || text="main-watch: Orca did not take these for run $RUN, so they are NOT in your inbox: $diag. Each retries every tick.$([ "$open" = 0 ] || echo ' Other items are waiting in your Orca inbox.')$fix"
  # Issue 318: Orca's nudge that started a turn inside the window holds this wake, untried; a diagnostic is typed anyway.
  local claimed=$NOW
  pp_wake_claim "$NOW" || { [ -n "$diag" ] || { wake_result held "Orca's own nudge holds the claim"; return 0; }; claimed=; }
  r=$(orca-ide terminal send --terminal "$MAIN_H" --text "$text" --enter --wait-submit 10 --json 2>/dev/null)
  if jq -e '[.. | objects | .stages? // empty | .[]?] | index("turn_started") != null' <<<"$r" >/dev/null 2>&1; then
    rm -f "$ST/wake" "$ST/wake-told"
    wake_result turn_started
  else
    wake_result no_turn "$(jq -r '.error.message // "no turn_started in the receipt"' <<<"$r" 2>/dev/null || echo "no receipt")"
    # No turn: the claim is given back for the next try or nudge, unless a nudge took a newer one meanwhile.
    [ -z "$claimed" ] || pp_wake_release "$claimed"
    [ "${tries:-0}" != 0 ] || echo "$NOW" > "$ST/wake-first"
    printf '%s\n%s\n%s\n%s\n' "$((tries + 1))" "$tasks" "$RUN" "$diag" > "$ST/wake"
    echo "main-watch: wake not proven for $MAIN_H (try $((tries + 1)) of $WAKE_TRIES): $(jq -r '.error.message // "no turn_started in the receipt"' <<<"$r" 2>/dev/null || echo "no receipt")" >&2
  fi
}

# The cutoff is always the seat's launch: read-verdict.sh drops session logs
# older than it, and takes the answer after the last prompt, so a follow-up in
# the same session is read from that session and an old verdict is not.
# has_result <handle> <launched> -- a verdict or marker is in this seat's OWN
# output (its pane, or its session log since launch). A file in the worktree is
# never read: another seat of the same unit writes there too. RV_OK=1 when the
# read answered (0, or 3/5: no verdict yet, turn over without one); a timeout or
# failed read leaves 0, so the caller retries instead of remembering it.
has_result() {
  local out rc
  out=$(timeout 20 bash "$HERE/read-verdict.sh" "$1" 5 "" "" "" "" "" "$2" 2>/dev/null); rc=$?
  RV_OUT=$out
  case $rc in 0|3|5) RV_OK=1 ;; *) RV_OK=0 ;; esac
  grep -qE '^VERDICT: |-DONE$' <<<"$out"
}

# grew_at <key> <handle> <worktree> <task> <launched> <session id> -- the epoch the
# seat's session log or pane output last grew. Pane growth is Orca's output
# cursor, never the screen: a spinner redraw changes the screen of a hung pane.
# No locatable log leaves the pane alone to decide.
grew_at() {
  local g=$ST/grow-$1 lf=$ST/log-$1 log old cur at sig
  old=$(sed -n 3p "$g" 2>/dev/null); at=$(head -1 "$g" 2>/dev/null)
  # Only the lines since the last read: the whole buffer is read once per seat.
  # An unanswered read keeps the old cursor, so it never reads as growth.
  cur=$(pane_cursor "$2" "${old:-0}")
  cur=${cur:-$old}
  log=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(printf '%s' "$3" | sed 's#/#-#g')/$6.jsonl
  if [ -z "$6" ] || [ ! -f "$log" ]; then
    # The read-verdict lookup is the costly read: once per seat, then again only
    # for a stall candidate, in case the seat moved to a new session.
    log=$(cat "$lf" 2>/dev/null)
    if [ ! -e "$lf" ] || [ $((NOW - ${at:-$NOW})) -ge "$STALL_S" ]; then
      log=$(timeout 20 bash "$HERE/read-verdict.sh" --state --worktree "$3" --task "$4" \
        --launched "${5:-0}" 2>/dev/null | sed -n 's/^session=//p')
      printf '%s\n' "$log" > "$lf"
    fi
  fi
  sig="$(stat -c %s "$log" 2>/dev/null) $log $cur"
  # Line 4 is the located session log, empty when none was found.
  [ "$(sed -n 2p "$g" 2>/dev/null)" = "$sig" ] \
    || printf '%s\n%s\n%s\n%s\n' "$NOW" "$sig" "$cur" "$([ -f "$log" ] && printf '%s' "$log")" > "$g"
  head -1 "$g"
}

# pane_cursor <handle> [from] -- Orca's output cursor for the pane, reading only
# the lines past <from>; empty when Orca did not answer.
pane_cursor() {
  orca-ide terminal read --terminal "$1" --cursor "${2:-0}" --limit 300000 --json 2>/dev/null \
    | jq -r '.result.terminal.latestCursor // empty' 2>/dev/null
}

# log_size <key> -- bytes in the seat's session log grew_at located (grow file
# line 4); empty when none was found.
log_size() {
  local log; log=$(sed -n 4p "$ST/grow-$1" 2>/dev/null)
  [ -z "$log" ] || stat -c %s "$log" 2>/dev/null || true
}

# pane_grew <handle> <key> -- the pane printed past the cursor, or its session
# log grew past the size, recorded when this seat's finish settled. Orca 1.4.220
# never moves an agent pane's cursor, so the log is what shows a new turn there.
# No record or an unanswered read is no growth. A third argument `b` compares
# with the marks of the seat's boot read instead (mark_pane). A seat marked
# when it had no log yet is looked up again here, with grew_at's arguments
# after the mark's letter: a log that has appeared since is its new turn.
pane_grew() {
  local fp cur fl sz m=${3:-f}
  fl=$(cat "$ST/${m}l-$2" 2>/dev/null)
  if [ -z "$fl" ] && [ -e "$ST/${m}l-$2" ] && [ $# -gt 3 ]; then
    rm -f "$ST/log-$2"; grew_at "$2" "$1" "$4" "$5" "$6" "${7:-}" >/dev/null
    [ -z "$(log_size "$2")" ] || return 0
  fi
  sz=$(log_size "$2")
  [[ $fl =~ ^[0-9]+$ && $sz =~ ^[0-9]+$ ]] && [ "$sz" -gt "$fl" ] && return 0
  fp=$(cat "$ST/${m}p-$2" 2>/dev/null); [[ $fp =~ ^[0-9]+$ ]] || return 1
  cur=$(pane_cursor "$1" "$fp")
  [[ $cur =~ ^[0-9]+$ ]] && [ "$cur" -gt "$fp" ]
}

# mark_pane <f|b> <key> <handle> <worktree> <task> <launched> <session id> --
# what pane_grew compares with: the pane's cursor and its session log's size,
# each recorded once. An unanswered cursor read is retried next tick. On Orca
# 1.4.220 the log is the only sign of a new turn; one not located yet (first
# seen `done`, or it appeared after a `working` tick cached "none") is looked
# up once more here, and the size is empty when there is still none.
mark_pane() {
  local at
  [ -e "$ST/$1p-$2" ] || { at=$(pane_cursor "$3"); [[ ! $at =~ ^[0-9]+$ ]] || echo "$at" > "$ST/$1p-$2"; }
  [ -e "$ST/$1l-$2" ] || {
    [ -n "$(sed -n 4p "$ST/grow-$2" 2>/dev/null)" ] \
      || { rm -f "$ST/log-$2"; grew_at "$2" "$3" "$4" "$5" "$6" "${7:-}" >/dev/null; }
    log_size "$2" > "$ST/$1l-$2"; }
}

# rv_unanswered <key> -- the seat's own output could not be read (RV_OK=0), so
# nothing is known and nothing may be remembered. 0 = try again next
# tick; 1 after RV_TRIES unanswered reads in a row, when the caller settles on
# what it has rather than never reporting the seat.
RV_TRIES=5
rv_unanswered() {
  local n; n=$(( $(cat "$ST/rvf-$1" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$ST/rvf-$1"
  [ "$n" -lt "$RV_TRIES" ]
}

# reap_brokers -- the openai-codex plugin starts one detached
# `app-server-broker.mjs serve --cwd <dir>` per Claude session and stops it only
# in that session's SessionEnd hook, which a pane closed by `orca-ide terminal
# close` never runs. Each leak keeps 5-120 children; on 2026-09-28 about 2,000
# of them hit kern.maxprocperuid and crashed the Mac. A broker is leaked when it
# is over an hour old, no live claude or codex-companion works in its --cwd, and
# no codex-companion is in its tree (a review in flight). Its tree is killed
# children first; a --cbm-daemon-internal process and its subtree never are.
# Leaves PROCS and PROC_TOP (this user's process count and top command
# families) for proc_warn.
reap_brokers() {
  local snap pids live="" p cwd age n order
  PROCS=
  snap=$(ps -A -o uid=,pid=,ppid=,etime=,command= 2>/dev/null | awk -v me="$(id -u)" '$1 == me')
  [ -n "$snap" ] || return 0
  pids=$(awk '{ n = split($5, a, "/") } a[n] == "claude" || /codex-companion/ { printf "%s%s", s, $2; s = "," }' <<<"$snap")
  local raw rc=0
  [ -z "$pids" ] || { raw=$(lsof -a -d cwd -p "$pids" -Fn 2>/dev/null); rc=$?; live=$(sed -n 's/^n//p' <<<"$raw"); }
  if [ -n "$pids" ] && { [ "$rc" != 0 ] || [ -z "$live" ]; }; then
    # An lsof that failed or named nothing would make a live session's broker look abandoned.
    echo "main-watch: lsof failed (exit $rc) or named no working directory for the live sessions; no broker reaped" >&2
  else
    while IFS=$'\t' read -r p cwd age n order; do
      # env: the external kill, so a test's PATH stub stands in for it.
      # shellcheck disable=SC2086 # the tree is a pid list
      env kill -TERM $order "$p" 2>/dev/null
      echo "main-watch: killed leaked codex broker pid=$p cwd=$cwd age=${age}s children=$n"
    done < <(awk -v OFS='\t' '
      NR == FNR { live[$0] = 1; next }
      {
        pid = $2; kids[$3] = kids[$3] " " pid
        t = $4; d = 0
        if (t ~ /-/) { split(t, dt, "-"); d = dt[1]; t = dt[2] }
        k = split(t, hms, ":")
        age[pid] = hms[k] + 60 * hms[k - 1] + (k == 3 ? 3600 * hms[1] : 0) + 86400 * d
        c = $0; for (i = 1; i <= 4; i++) sub(/^[[:space:]]*[^[:space:]]+/, "", c)
        sub(/^[[:space:]]+/, "", c); cmd[pid] = c
      }
      function walk(p,   m, ks, j, ch) {
        m = split(kids[p], ks, " ")
        for (j = 1; j <= m; j++) {
          ch = ks[j]
          if (cmd[ch] ~ /--cbm-daemon-internal/) continue
          if (cmd[ch] ~ /codex-companion/) busy = 1
          walk(ch); order = order " " ch; n++
        }
      }
      END {
        for (p in cmd) {
          if (cmd[p] !~ /app-server-broker\.mjs serve/ || cmd[p] ~ /--cbm-daemon-internal/ || age[p] <= 3600) continue
          if (!match(cmd[p], /--cwd[= ][^[:space:]]+/)) continue
          cwd = substr(cmd[p], RSTART + 6, RLENGTH - 6)
          # A path may hold a space, and ps does not quote: ask of each live
          # folder whether it is the whole --cwd of this broker.
          alive = 0
          for (l in live) {
            i = index(cmd[p], "--cwd " l); if (!i) i = index(cmd[p], "--cwd=" l)
            if (i && substr(cmd[p], i + 6 + length(l), 1) ~ /^ ?$/) alive = 1
          }
          if (alive) continue
          order = ""; n = 0; busy = 0; walk(p)
          if (!busy) print p, cwd, age[p], n, substr(order, 2)
        }
      }' <(printf '%s\n' "$live") - <<<"$snap")
  fi
  # The observed count, not less the kills: a tree slow to die is still there,
  # and the next tick samples again.
  PROCS=$(wc -l <<<"$snap" | tr -d ' ')
  PROC_TOP=$(awk '{ n = split($5, a, "/"); c[a[n]]++ } END { for (k in c) print c[k], k }' <<<"$snap" \
    | sort -rn | head -3 | awk '{ printf "%s%s %s", s, $2, $1; s = ", " }')
}

# proc_warn -- past 2,000 of this user's processes, one item per episode: at
# kern.maxprocperuid nothing new can start, which is how the Mac crashed.
proc_warn() {
  [ -n "${PROCS:-}" ] || return 0
  if [ "$PROCS" -le 2000 ]; then rm -f "$ST/procs-high"; return 0; fi
  [ -s "$ST/procs-high" ] || echo "$NOW" > "$ST/procs-high"
  local cap
  cap=$(sysctl -n kern.maxprocperuid 2>/dev/null) || cap=unknown
  post "procs-$(cat "$ST/procs-high")" "" "main-watch: $PROCS processes for this user (cap $cap)" \
    "Top command families: $PROC_TOP. At the per-user cap (kern.maxprocperuid) nothing new can start. Find the leak: ps -A -o command= | sort | uniq -c | sort -rn | head"
}

# digest <line> -- a routine item (issue 253): one line in the digest file orca-wait.sh counts; no message, no wake.
digest() { printf '%s %s\n' "$NOW" "$1" >> "$ST/digest"; }

# gate <unit> <worktree> -- the merge gate on a Builder's DONE (issues 254, 258). 0: the unit is queued, merging or
# merged; merge_collect reports how its merge ends. 1: WHY says why it is not merged. A held unit (`Merge: hold` in
# its brief, or an owner decision open on it) runs no gate, and its why starts "held:".
# --verify runs once per tip and set of round files (pp_gate_key): its key, exit, rule and line are kept in
# gate-<unit>, which orca-wait.sh reads (issue 306 R11). The rule has a line of its own, kept for the file's layout
# and no longer read: every rule --verify passes is a GO.
gate() {
  local u=$1 w=$2 tip key f=$ST/gate-$1 rc rule out
  WHY=$(pp_merge_held "$u" "$w") && { WHY="held: $WHY"; return 1; }
  tip=$(git -C "$w" rev-parse HEAD 2>/dev/null) || { WHY="its worktree has no commit"; return 1; }
  [ "$(sed -n 1p "$ST/merge-$u" 2>/dev/null)" != "$tip" ] || return 0
  # Issue 317: a hand-started merge of this unit at this tip, running or waiting on the lock, is that merge; none is queued beside it.
  pp_merge_active "$u" "$tip" >/dev/null && return 0
  [ -z "$(git -C "$w" status --porcelain 2>/dev/null)" ] || { WHY="its worktree has uncommitted files, which no pass read"; return 1; }
  key=$(pp_gate_key "$u" "$w")
  if [ "$(sed -n 1p "$f" 2>/dev/null)" != "$key" ]; then
    out=$(bash "$HERE/builder-codex-pass.sh" --verify "$w" "$u" "$tip" 2>&1 </dev/null); rc=$?
    rule=$(sed -n 's/^Builder proof: .*; rule: //p' <<<"$out" | head -1)
    [ "$rc" = 0 ] && out=$(grep -m1 '^Builder proof' <<<"$out") || out=$(grep . <<<"$out" | tail -1)
    printf '%s\n%s\n%s\n%s\n' "$key" "$rc" "$rule" "$(cut -c1-300 <<<"$out")" > "$f"
  fi
  rc=$(sed -n 2p "$f"); out=$(sed -n 4p "$f")
  [ "$rc" = 0 ] || { WHY=${out:-the merge check refused it and gave no reason}; return 1; }
  MERGE+=("$u@$tip")
}

# merge_collect -- how each merge job ended, read from its records every tick and not through the unit's seat: a
# landed merge removes the worktree, and the seat with it. A unit that landed is posted to main once (issue 318: a
# landed merge is actionable), and has one digest line. One that did not, that landed with a
# later step failed, or whose job died with no exit, is posted to main.
merge_collect() {
  local r u tip log rc pid landed
  for r in "$ST"/merge-*; do
    [ -f "$r" ] && ! grep -qx told "$r" || continue
    u=${r#"$ST"/merge-} tip=$(sed -n 1p "$r") log=$(sed -n 2p "$r")
    # A unit's record opens with its sha: an earlier build's job files (merge-<epoch>.log, .rc, .pid) do not.
    [[ $tip =~ ^[0-9a-f]{40}$ ]] || continue
    if ! rc=$(cat "${log%.log}.rc" 2>/dev/null); then
      # shortcut: a pid the system gave to another process since reads as the job still running; rare, and the next
      # merge of the unit writes a new record.
      pid=$(cat "${log%.log}.pid" 2>/dev/null) && kill -0 "$pid" 2>/dev/null && continue
      post "merge-$u-$tip" "" "main-watch: the merge job for $u ended with no exit; it may have merged part way" \
        "The merge of $u at ${tip:0:8} stopped before it wrote its exit (log $log). Look for $u in main's log first; merge it by hand only if it is not there: $HERE/merge-unit-local.sh $u" once
    # The unit name is matched as written: in a pattern, a.b would also match axb's line.
    elif ! landed=$(awk -v p="merge-queue: $u merged; " 'index($0, p) == 1 { print substr($0, length(p) + 1); n++ } END { exit !n }' "$log"); then
      post "merge-$u-$tip" "" "main-watch: the merge of $u did not land cleanly (exit $rc); log $log" \
        "$(grep '^merge-queue: ' "$log" | grep -wF -- "$u" | tail -n 3)"$'\n'"Read the log and finish it by hand: $log" once
    # Told once flush recorded the post: a refused send posts again next tick. The digest line is written once.
    elif grep -qE '^(posted=.|handled$)' "$ST/item-merge-$u-$tip" 2>/dev/null; then
      echo told >> "$r"
    else
      grep -qx digested "$r" || { digest "$u merged into local main at ${tip:0:8}; log $log"; echo digested >> "$r"; }
      post "merge-$u-$tip" "" "main-watch: $u merged into local main at ${tip:0:8}" "merge-queue: $u merged; $landed; log $log" once
    fi
  done
}

# merge_start -- one detached job for the units that passed the gate this tick: merge-queue.sh merges each by its sha,
# two or more as one train (issue 307). Not pp_detach: merge_collect tells main how it ended, through flush.
# The exit goes to a file merge_collect reads; the job's pid to another, so a job that died is told from a slow one.
# The job's files are mergejob-*, never merge-*: a unit may be named u.rc or u.log.
merge_start() {
  [ "${#MERGE[@]}" -gt 0 ] || return 0
  local log=$ST/mergejob-$NOW.log m args=("${MERGE[@]}")
  [ "${#MERGE[@]}" = 1 ] || args=(--train "${MERGE[@]}")
  for m in "${MERGE[@]}"; do printf '%s\n%s\n' "${m#*@}" "$log" > "$ST/merge-${m%@*}"; done
  (cd "$PP_MAIN" && COMMANDECK_FOREGROUND=1 nohup bash -c '"$@" > "$0" 2>&1; echo $? > "${0%.log}.rc"' "$log" \
    bash "$HERE/merge-queue.sh" "${args[@]}" </dev/null >/dev/null 2>&1 & echo $! > "${log%.log}.pid")
}

seat() { # handle task unit role launched [session id] [seat tag] [worktree name]
  # A planner of a unit planned before 0.18.0 runs in <unit>-plan: the record names where the seat runs.
  local h=$1 task=$2 u=$3 w=$WS/${8:-$3} key="seat-$1-$2" state kind since at ep item
  # The closing line compared below is this seat's own read, never the last seat's.
  RV_OUT=
  [ -n "$h" ] && [ -n "$u" ] && [ "$u" != u ] && [ -d "$w" ] || return 0
  state=$(awk -F'\t' -v h="$h" '$1 == h { print $2; exit }' <<<"$STATES")
  case $state in ""|none) ;; *) : > "$ST/seen-$key" ;; esac
  [ -e "$ST/state-$key" ] && [ "$(sed -n 2p "$ST/state-$key")" = "$state" ] || printf '%s\n%s\n' "$NOW" "$state" > "$ST/state-$key"
  since=$(head -1 "$ST/state-$key")
  # Once settled, the kind never changes within one episode; only the task
  # decides from here. A seat that works again after a settled finish (main sent
  # it a follow-up) starts a new episode: its next stop is a new item with a
  # new task, whatever became of the first one's task. Working again is seen
  # as `working`, or, when the follow-up started and finished between two
  # ticks, as pane output past the cursor recorded when the finish settled.
  # A Codex pane on the Mac reads `none` throughout, so the same growth is the
  # only sign there.
  # ponytail: output a pane prints after `done` with no new turn (late hook
  # output, a resize) reads as a new finish and costs main one extra post;
  # fingerprint the session log's last assistant message if that shows up.
  kind=$(cat "$ST/kind-$key" 2>/dev/null)
  # A Codex pane on the Mac reads `none` at work and at rest, so there its log
  # growing past the settled finish is the only sign of the follow-up.
  # A finish settled while Orca still read `working` (sw-, a stale snapshot) needs the pane to grow past it too.
  if [ -n "$kind" ] && case $state in
      working) [ ! -e "$ST/sw-$key" ] || pane_grew "$h" "$key" f "$w" "$task" "$5" "${6:-}" ;;
      done|none) pane_grew "$h" "$key" f "$w" "$task" "$5" "${6:-}" ;;
      *) false ;; esac; then
    rm -f "$ST/kind-$key" "$ST/rv-$key" "$ST/fp-$key" "$ST/fl-$key" "$ST/held-$key" "$ST/sw-$key"; kind=; echo "$NOW" > "$ST/episode-$key"
  fi
  # A settled finish is not read again; the wait check below still needs the
  # closing line it was settled on.
  [ "$kind" != finished ] || RV_OUT=$(cat "$ST/rv-$key" 2>/dev/null)
  ep=$(cat "$ST/episode-$key" 2>/dev/null)
  item=$key${ep:+-$ep}; [ -z "$ep" ] || task=
  # Issue 258: Orca reads a Builder at its prompt as idle as well as done; both are a stop.
  local cs=$state; [ "$4:$state" != builder:idle ] || cs=done
  case $cs in
    working)
      # A hold ends when the Builder works again, settled or not: its next helper wait starts a fresh clock.
      : > "$ST/working-$key"; rm -f "$ST/held-$key"
      if [ -z "$kind" ]; then
        at=$(grew_at "$key" "$h" "$w" "$task" "$5" "${6:-}")
        [ $((NOW - at)) -ge "$STALL_S" ] || return 0
        # A quiet seat that reported or committed its plan is finished, whatever Orca's snapshot says (issue 320).
        seat_reported "$h" "$4" || { post "stall-$key-$at" "" "main-watch: $u $4 stalled; inspect" \
          "Seat $4 ($h) on $u is working, but its session log and pane have not changed for $(( (NOW - at) / 60 )) min. Inspect it: $HERE/read-verdict.sh $h"
          return 0; }
        : > "$ST/sw-$key"; echo "$kind" > "$ST/kind-$key"; printf '%s\n' "$RV_OUT" > "$ST/rv-$key"
        mark_pane f "$key" "$h" "$w" "$task" "$5" "${6:-}"
      fi ;;
    done)
      if [ -z "$kind" ]; then
        # A boot `done` with no result is read once, not every tick until closed,
        # and again only when the pane or its log grew past that read: a seat
        # that works and finishes between two ticks never reads `working`.
        if [ ! -e "$ST/working-$key" ] && [ -e "$ST/booted-$key" ]; then
          pane_grew "$h" "$key" b "$w" "$task" "$5" "${6:-}" || return 0
          rm -f "$ST/booted-$key" "$ST/bp-$key" "$ST/bl-$key"
        fi
        # The cutoff is the seat's launch, also for a follow-up: read-verdict.sh
        # drops a session created before it, and the seat's own session was
        # created at launch. Its latest answer is the one after the last prompt.
        if has_result "$h" "${5:-0}"; then kind=finished
        elif [ "$RV_OK" = 0 ] && rv_unanswered "$key"; then return 0
        elif [ -e "$ST/working-$key" ] && seat_reported "$h" "$4"; then :
        elif [ -e "$ST/working-$key" ]; then kind=silent
        else [ "$RV_OK" = 0 ] || { : > "$ST/booted-$key"; mark_pane b "$key" "$h" "$w" "$task" "$5" "${6:-}"; }; return 0; fi
        # A Builder with no DONE line and a helper out is waiting on it: read again next tick. DONE is its own
        # unit's marker as the brief prints it, never another pane's it quotes (DESIGN-DONE). A VERDICT line
        # is no finish here: read-verdict.sh ends its output at one, and a Builder quotes its passes' verdicts,
        # so DONE is also read as the last line of the latest message in the Builder's own session (--state's
        # marker), bound as seat.sh binds it: the seat tag typed into every prompt, direct ones included.
        # The log is the Builder's own to write, so the hold is bounded by this service's clock: HOLD_S at most.
        if [ "$4" = builder ] && ! grep -qxF -- "${u^^}-DONE" <<<"$RV_OUT" && helper_out "$u" "${5:-0}" \
          && ! timeout 20 bash "$HERE/read-verdict.sh" --state --worktree "$w" --agent claude --launched "${5:-0}" --spec "${7:-}" \
            --marker "${u^^}-DONE" 2>/dev/null | grep -qx 'marker=1'; then
          [ -s "$ST/held-$key" ] || echo "$NOW" > "$ST/held-$key"
          # A helper or pass started after the hold began means the Builder worked, maybe between two ticks: a new clock.
          [ "$(builder_card "$u" "${5:-0}" | jq -r --argjson now "$NOW" '[.waiting[] | select(.kind == "subagent" or .kind == "codex")
            | .since | sub("\\.[0-9]+"; "") | fromdateiso8601 | select(. <= $now)] | max // 0' 2>/dev/null || echo 0)" \
            -le "$(cat "$ST/held-$key")" ] || echo "$NOW" > "$ST/held-$key"
          [ $((NOW - $(cat "$ST/held-$key"))) -ge "$HOLD_S" ] || return 0
          # Expired with no DONE: a quoted verdict is not the Builder's finish.
          kind=silent
        fi
        rm -f "$ST/rvf-$key" "$ST/held-$key"
        echo "$kind" > "$ST/kind-$key"; printf '%s\n' "$RV_OUT" > "$ST/rv-$key"
      fi
      # The finish's fingerprint, once per finish.
      mark_pane f "$key" "$h" "$w" "$task" "$5" "${6:-}" ;;
    ""|none)
      # Gone: only a pane this service saw alive, and only when Orca answered.
      [ "$LISTED" = 1 ] || return 0
      if [ ! -e "$ST/seen-$key" ]; then
        # Orca never binds a Codex pane on the Mac: it reads `none` from its
        # first tick to its last and was never tracked. A pane Orca
        # still lists whose session log is found is alive. The lookup is the
        # costly read: every tick for a seat's first STALL_S, then once per STALL_S.
        [ "$state" = none ] || return 0
        at=$(cat "$ST/look-$key" 2>/dev/null)
        [ -z "$at" ] || [ $((NOW - ${5:-0})) -lt "$STALL_S" ] || [ $((NOW - at)) -ge "$STALL_S" ] || return 0
        echo "$NOW" > "$ST/look-$key"; rm -f "$ST/log-$key"
        grew_at "$key" "$h" "$w" "$task" "$5" "${6:-}" >/dev/null
        [ -n "$(sed -n 4p "$ST/grow-$key" 2>/dev/null)" ] || return 0
        : > "$ST/seen-$key"
      fi
      # Orca never binds a Codex pane on the Mac, so a Codex seat can read blank
      # while it works: a located session log that grew within STALL_S is still
      # working. read-verdict.sh --state searches both Codex homes. A verdict
      # is read first, so a blank seat that finished is posted as finished.
      if [ -z "$kind" ]; then
        if has_result "$h" "${5:-0}"; then kind=finished
        else
          at=$(grew_at "$key" "$h" "$w" "$task" "$5" "${6:-}")
          [ -z "$(sed -n 4p "$ST/grow-$key" 2>/dev/null)" ] || [ $((NOW - at)) -ge "$STALL_S" ] || return 0
          # A read that failed says nothing about how the seat ended, and a
          # settled seat is not read again: it is tried each tick, and only a
          # read still failing STALL_S later settles as silent (a pane with no
          # buffer fails every read, and must still be posted).
          if [ "$RV_OK" = 0 ]; then
            [ -e "$ST/rvfail-$key" ] || echo "$NOW" > "$ST/rvfail-$key"
            [ $((NOW - $(cat "$ST/rvfail-$key"))) -ge "$STALL_S" ] || return 0
          fi
          seat_reported "$h" "$4" || kind=silent
        fi
        rm -f "$ST/rvf-$key" "$ST/rvfail-$key"
        echo "$kind" > "$ST/kind-$key"; printf '%s\n' "$RV_OUT" > "$ST/rv-$key"
      fi
      # A listed pane's finish is fingerprinted too, so its follow-up is seen.
      [ "$state" != none ] || mark_pane f "$key" "$h" "$w" "$task" "$5" "${6:-}" ;;
    *)
      [ $((NOW - since)) -ge "$WAITING_S" ] || return 0
      post "wait-$key-$since" "" "main-watch: $u $4 stalled in Orca state $state; inspect" \
        "Seat $4 ($h) on $u has been '$state' for $(( (NOW - since) / 60 )) min. It may be waiting for input: $HERE/read-verdict.sh $h"
      return 0 ;;
  esac
  # The seat's own message reached main: nothing to post.
  [ "$kind" != reported ] || { echo handled > "$ST/item-$item"; return 0; }
  if [ "$kind" = finished ]; then
    # A seat.sh wait on this pane reports the finish itself.
    pp_waited_on "$h" "$NOW" "${RV_OUT:-}" "watch:$item" && { echo handled > "$ST/item-$item"; return 0; }
    local why=
    # A Builder's DONE in a unit worktree (one that holds its own brief) goes through the merge gate every tick
    # until it lands (issues 254, 258): only a held or refused one reaches main as a finish.
    if [ "$4" = builder ] && [ -f "$w/.claude/briefs/$u.md" ] && grep -qxF -- "${u^^}-DONE" <<<"$RV_OUT"; then
      gate "$u" "$w" && return 0; why=$WHY
      [[ $why != held:* ]] && { post "$item-$(git -C "$w" rev-parse HEAD 2>/dev/null)" "" "main-watch: seat $4 on $u finished ($h); not merged: $why" \
        "Seat $4 on $u said DONE and its merge gate refused it: $why. Fix or merge it: $HERE/merge-unit-local.sh $u" once; return 0; }
    fi
    post "$item" "$task" "main-watch: seat $4 on $u finished ($h)${why:+; not merged, $why}" \
      "Seat $4 on $u stopped. Read it: $HERE/read-verdict.sh $h, then collect it."
  else
    # One more reading first: a seat Orca read idle for one tick while still at work, or whose session log was
    # written after this tick read it, is not stopped (issue 238). Its finish is forgotten, so the next is read afresh.
    at=$(pp_session_log_at "$w")
    if [ "$(state_now "$h")" = working ] || { [ "$at" != null ] && [ "$at" -gt "$NOW" ]; }; then
      rm -f "$ST/kind-$key" "$ST/rv-$key" "$ST/fp-$key" "$ST/fl-$key"; return 0
    fi
    # A live Builder pane is nudged first (issue 258); a gone one has no one to type to.
    NUDGED=""
    if [ "$4" = builder ] && [ -n "$state" ] && [ "$state" != none ]; then stopped_nudge "$u" "$h" "$item" && return 0; fi
    post "$item" "$task" "main-watch: $u $4 stopped without reporting; inspect" \
      "Seat $4 ($h) on $u stopped with no marker, verdict or worker_done${state:+ (Orca: $state)}.$NUDGED This is NOT a finish. Inspect it: $HERE/read-verdict.sh $h${RV_OUT:+ Last words: $(tr '\n' ' ' <<<"$RV_OUT" | tail -c 300)}"
  fi
}

# seat_reported <handle> <role> -- issue 320: the seat's own completion message that reached main (kind reported,
# nothing posted), or its fresh plan commit or a completion note main has not seen (kind finished, with the PLAN-DONE
# line a wait that released on it claims)
# since its episode began (pp_seat_done). Fails, setting nothing, when there is neither, and for any seat but a plan
# author: a Builder's finish is its DONE line and the merge gate (issue 258), a judge's is its VERDICT line.
seat_reported() {
  local r sd
  [[ $2 == plan-author* ]] && r=$(pp_seat_record "$1") && sd=$(pp_seat_done "$r" "${MAIN_H:-}" "$([ "$COORD" = '?' ] || echo "$COORD")") || return 1
  if [ "$sd" = message ]; then kind=reported; else kind=finished RV_OUT+=${RV_OUT:+$'\n'}PLAN-DONE; fi
}

# HEADS-UP RELAY. The built-in "you should know" mod keeps each Claude
# session's current Heads-up offer, full explanation included, in its store;
# pressing 1 would inject it into that session as a prompt, so the store is only
# read. Each tick captures every unseen (session id, shownAt) pair into the
# ledger and the archive, then posts each group as an item, inbox only. A later
# offer overwrites `view`, so capture comes first and is never conditional on a
# run, a sender or a send. Offers with the same line within HU_WINDOW_MS of the
# group's first one are one note naming every session.
# HU_STORE is the store under the config folder claude_dir() read this tick.
HU_LEDGER=$ST/heads-up.json
# The archive is this project's own: another project's watcher on the same
# machine keeps its own, so neither takes the other's archived offers as new.
HU_LOG=$ST/heads-up-log.jsonl
# Handled notes, one line per group key and per member (session@shownAt), beside
# the archive: the archive keeps every note for good, so a handled receipt that
# went with its item file would leave the note on record and looking new.
HU_DONE=$ST/heads-up-handled
HU_WINDOW_MS=300000

# hu_cwd <session id> -- the checkout the session ran in: the first cwd its own
# transcript records. The project directory name is a lossy slug and is never
# reversed. Empty when not exactly one transcript names one.
hu_cwd() {
  local t
  t=$(ls "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$1".jsonl 2>/dev/null)
  [ -n "$t" ] && [ "$(wc -l <<<"$t")" = 1 ] || return 0
  head -200 "$t" | jq -rR 'fromjson? | select(type == "object" and (.cwd | type) == "string" and .cwd != "") | .cwd' 2>/dev/null | head -1
}

hu_save() { # <ledger JSON> -- replaced whole, so a crash never leaves half a ledger
  printf '%s\n' "$1" > "$HU_LEDGER.tmp" && mv -f "$HU_LEDGER.tmp" "$HU_LEDGER" && return 0
  echo "main-watch: cannot write $HU_LEDGER; heads-up state not saved" >&2; return 1
}

heads_up_capture() {
  local f offers o led rec
  [ -e "$HU_LEDGER" ] && { led=$(jq -ce 'select(.pairs | type == "object") | select(.groups | type == "object")' "$HU_LEDGER" 2>/dev/null) \
    || { echo "main-watch: $HU_LEDGER is unreadable; no heads-up captured until it is repaired" >&2; return 0; }; }
  led=${led:-'{"pairs":{},"groups":{}}'}
  # An offer archived whose ledger write then failed is taken from the archive,
  # since the store may have replaced it by now.
  # ponytail: reads the whole archive every tick; keep an offset if it grows large.
  # A handled note never comes back from the archive, ledger or no ledger.
  # Files, not --arg/--argjson: the ledger and the done list grow without a bound, and past the 1 MB argument limit
  # (ARG_MAX) jq would fail every tick (issue 280).
  offers=$(jq -cR --slurpfile leda <(printf '%s' "$led") --rawfile done <(cat "$HU_DONE" 2>/dev/null) '
    $leda[0] as $led | ($done | split("\n") | map({(.): 1}) | add // {}) as $d
    | fromjson? | select(type == "object" and (.id | type) == "string")
    | select($led.pairs["\(.id)@\(.shownAt)"] == null and $d["\(.id)@\(.shownAt)"] == null) | {id, at: .shownAt, line, explanation, cwd, archived: true}' "$HU_LOG" 2>/dev/null)
  hu_take "$offers" || return 0
  for f in "$HU_STORE"/cc-plugin-you-should-know_builtin-*.json; do
    [ -f "$f" ] || continue
    # One read of the whole file: the mod rewrites it under us, and a partial
    # copy fails to parse, so it is skipped whole until the next tick.
    offers=$(jq -c '.sessions | if type == "array" then . else error end
      | map(select(type == "object" and .view.kind? == "offer")) | sort_by(.view.shownAt)[]
      | {id, at: .view.shownAt, line: .view.line, explanation: .view.explanation}' "$f" 2>/dev/null) \
      || { echo "main-watch: heads-up store $f did not parse; skipped this tick" >&2; continue; }
    hu_take "$offers" || return 0
  done
}

# hu_take <offers, one JSON per line> -- capture each unseen pair into the
# caller's ledger `led`. 1 = the ledger could not be saved; stop this tick.
hu_take() {
  local o rec cwd next sent p htext
  # Groups already delivered: a relay is sent once, so anything that joined one
  # would never reach main. Only the same session's identical text joins those.
  sent=$({ grep -lE '^(posted=[0-9]|handled$)' "$ST"/item-heads-up-* 2>/dev/null | sed 's#.*/item-##'; cat "$HU_DONE" 2>/dev/null; } \
    | jq -Rsc 'split("\n") | map(select(. != ""))')
  # What main already handled, by (session, line, explanation), from the archive:
  # the ledger that would have matched a repeat of it may be gone with the temp folder.
  htext=$(jq -cRn --rawfile done <(cat "$HU_DONE" 2>/dev/null) '
    ($done | split("\n") | map({(.): 1}) | add // {}) as $d
    | [inputs | fromjson? | select(type == "object" and $d["\(.id)@\(.shownAt)"] != null) | {([.id, .line, .explanation] | tojson): 1}] | add // {}' "$HU_LOG" 2>/dev/null); [ -n "$htext" ] || htext='{}'
  while IFS= read -r o; do
    [ -n "$o" ] || continue
    jq -e '(.id | type == "string" and test("^[A-Za-z0-9-]+$")) and (.at | type == "number" and . > 0 and . == floor)
      and (.line | type == "string" and length > 0) and (.explanation | type == "string" and length > 0)' >/dev/null 2>&1 <<<"$o" \
      || { echo "main-watch: heads-up offer skipped: no valid id, shownAt, line or explanation: $(cut -c1-160 <<<"$o")" >&2; continue; }
    p=$(jq -r '"\(.id)@\(.at)"' <<<"$o")
    jq -e --arg p "$p" '.pairs[$p]' >/dev/null <<<"$led" && continue
    # Still shown in the store after the temp folder lost the ledger.
    grep -qxF -- "$p" "$HU_DONE" 2>/dev/null && continue
    # The same session showing the same text again is handled with it.
    if jq -e --slurpfile ha <(printf '%s' "$htext") '$ha[0][[.id, .line, .explanation] | tojson] != null' >/dev/null 2>&1 <<<"$o"; then
      echo "$p" >> "$HU_DONE"; continue
    fi
    # An archived record keeps the checkout it was captured with; only a missing
    # one is looked up again.
    cwd=$(jq -r 'if (.cwd | type) == "string" then .cwd else empty end' <<<"$o")
    [ -n "$cwd" ] || cwd=$(hu_cwd "$(jq -r .id <<<"$o")")
    # A shownAt todate cannot render (1e100) fails here; nothing below may save then.
    rec=$(jq -c --arg cwd "$cwd" \
      '{id, shownAt: .at, utc: (.at / 1000 | floor | todate), cwd: (if $cwd == "" then null else $cwd end), line, explanation}' <<<"$o" 2>/dev/null) \
      && [ -n "$rec" ] || { echo "main-watch: heads-up offer skipped: shownAt is not a time: $(cut -c1-160 <<<"$o")" >&2; continue; }
    # Archived before it counts as captured: an unwritable archive leaves the
    # offer uncaptured, so the next tick tries again.
    jq -e '.archived' >/dev/null <<<"$o" || printf '%s\n' "$rec" 2>/dev/null >> "$HU_LOG" \
      || { echo "main-watch: cannot append $HU_LOG; heads-up $(jq -r '"\(.id)@\(.shownAt)"' <<<"$rec") not captured" >&2; continue; }
    # A session with no known checkout shares a note with nobody: a group waits
    # for every member's checkout, so one unplaced session held the others' note
    # back, for good when it never resolved.
    next=$(jq -c --argjson r "$rec" --argjson w "$HU_WINDOW_MS" --slurpfile senta <(printf '%s' "${sent:-[]}") '
      $senta[0] as $sent | (first(.groups | to_entries[] | select(.key as $k | .value.line == $r.line
          and (any(.value.members[]; .id == $r.id and .explanation == $r.explanation)
               or ((any($sent[]; . == $k) | not) and $r.cwd != null and all(.value.members[]; .cwd != null)
                 and (((.value.first - $r.shownAt) | if . < 0 then -. else . end) < $w)))) | .key)
        // "heads-up-\($r.shownAt)-\($r.id[0:8])") as $k
      | .pairs["\($r.id)@\($r.shownAt)"] = $k
      | .groups[$k] |= ((. // {line: $r.line, first: $r.shownAt, members: []}) | .members += [$r | del(.line)])' <<<"$led") \
      && [ -n "$next" ] || { echo "main-watch: heads-up $(jq -r '"\(.id)@\(.shownAt)"' <<<"$rec") could not be added to the ledger; skipped" >&2; continue; }
    led=$next
    hu_save "$led" || return 1
    # The same text joining a note main already handled is handled with it.
    ! grep -qxF -- "$(jq -r --arg p "$p" '.pairs[$p]' <<<"$led")" "$HU_DONE" 2>/dev/null || echo "$p" >> "$HU_DONE"
  done <<<"$1"
}

# hu_done <key> <ledger> -- when the group's receipt reads handled, put every
# member's (session, shownAt) and then the key on the lasting list, so a key on
# record means its members are too. 1 = not handled. A failed append is tried
# again next tick, while the receipt is still there.
hu_done() {
  [ -e "$ST/item-$1" ] && grep -qx handled "$ST/item-$1" || return 1
  { jq -r --arg k "$1" '.pairs | to_entries[] | select(.value == $k) | .key' <<<"$2"; echo "$1"; } >> "$HU_DONE"
}

HU_CLAIM_S=300   # a heads-up claim older than five ticks is no claim
# hu_claimed -- a project's own watcher posts every item for this checkout: $PP_SCRATCH/heads-up-owner
# (pid=, main=, at=, written whole each cycle it posts) names a live pid, this checkout as text, and an at= from
# 0 to HU_CLAIM_S old. Anything else is no claim, and this watcher posts. Sets HU_PID and HU_AT.
# shortcut: pid plus a 300 s at= window; add the process start time to the claim if a reuse is seen.
hu_claimed() {
  local c main
  c=$(cat "$PP_SCRATCH/heads-up-owner" 2>/dev/null) || return 1
  HU_PID=$(sed -n 's/^pid=//p' <<<"$c" | tail -1) main=$(sed -n 's/^main=//p' <<<"$c" | tail -1) HU_AT=$(sed -n 's/^at=//p' <<<"$c" | tail -1)
  [[ $HU_PID =~ ^[0-9]+$ && $HU_AT =~ ^[0-9]+$ ]] && kill -0 "$HU_PID" 2>/dev/null \
    && [ "$(pp_norm "$main")" = "$(pp_norm "$PP_MAIN")" ] && [ $((NOW - HU_AT)) -ge 0 ] && [ $((NOW - HU_AT)) -le "$HU_CLAIM_S" ]
}

# hu_seen <session id> <shownAt> -- 0 when a store file shows that offer now. A store that cannot be read, or a
# file that does not parse, shows nothing: an unsure note waits and may be posted twice, never lost.
hu_seen() {
  cat "$HU_STORE"/cc-plugin-you-should-know_builtin-*.json 2>/dev/null | jq -en --arg id "$1" --argjson at "$2" \
    'any(inputs | .sessions? | arrays | .[]; type == "object" and .id == $id and .view.kind? == "offer" and .view.shownAt == $at)' >/dev/null 2>&1
}

# hu_shown <session id> <shownAt> -- 0 while the store still shows that offer,
# or cannot be read; 1 once every store file answers and none shows it.
hu_shown() {
  local f rc
  # A folder that cannot be listed shows no file, which is not the offer being
  # gone. A folder that is not there at all, under a parent that can be
  # searched, holds no offer.
  [ -d "$HU_STORE" ] && [ -r "$HU_STORE" ] && [ -x "$HU_STORE" ] \
    || { [ ! -e "$HU_STORE" ] && [ -x "${HU_STORE%/*}" ] && return 1; return 0; }
  for f in "$HU_STORE"/cc-plugin-you-should-know_builtin-*.json; do
    [ -f "$f" ] || continue
    jq -e --arg id "$1" --argjson at "$2" '.sessions | if type == "array" then . else error end
      | any(.[]; type == "object" and .id == $id and .view.kind? == "offer" and .view.shownAt == $at)' "$f" >/dev/null 2>&1; rc=$?
    [ "$rc" = 1 ] || return 0
  done
  return 1
}

# heads_up_post -- each group not yet handled, through post: one task per group,
# retried from the saved text until Orca accepts it, then never sent again.
heads_up_post() {
  local led k id cwd subj body t p
  # The claim owner posts these notes. A note it must have seen (every member shown before its last cycle, at=,
  # and still shown) is put on the handled list unsent. Any other waits, unposted, and is posted once the claim
  # ends: backlog gone from the store, or an offer newer than the owner's last cycle, is never lost with the owner.
  if [ "$CLAIMED" = 1 ]; then
    led=$(cat "$HU_LEDGER" 2>/dev/null) || return 0
    for k in $(jq -r '.groups | keys[]' <<<"$led" 2>/dev/null); do
      grep -qxF -- "$k" "$HU_DONE" 2>/dev/null && continue
      for p in $(jq -r --arg k "$k" '.pairs | to_entries[] | select(.value == $k) | .key' <<<"$led"); do
        [ "${p##*@}" -le $((HU_AT * 1000)) ] && hu_seen "${p%@*}" "${p##*@}" || continue 2
      done
      { jq -r --arg k "$k" '.pairs | to_entries[] | select(.value == $k) | .key' <<<"$led"; echo "$k"; } >> "$HU_DONE"
    done
    return 0
  fi
  led=$(cat "$HU_LEDGER" 2>/dev/null) || return 0
  for k in $(jq -r '.groups | keys[]' <<<"$led" 2>/dev/null); do
    grep -qxF -- "$k" "$HU_DONE" 2>/dev/null && continue
    ! hu_done "$k" "$led" || continue
    # A note is main's whatever run it was first posted to: a task this run's
    # list does not hold (main switched runs) is made again here, not dropped.
    t=$(sed -n 's/^task=//p' "$ST/item-$k" 2>/dev/null)
    [ -z "$t" ] || jq -e --arg t "$t" 'any(.result.tasks[]?; .id == $t)' >/dev/null <<<"$TASKS" || rm -f "$ST/item-$k"
    for id in $(jq -r --arg k "$k" '.groups[$k].members[] | select(.cwd == null) | .id' <<<"$led"); do
      cwd=$(hu_cwd "$id"); [ -n "$cwd" ] || continue
      led=$(jq -c --arg k "$k" --arg id "$id" --arg c "$cwd" '.groups[$k].members |= map(if .id == $id and .cwd == null then .cwd = $c else . end)' <<<"$led")
      hu_save "$led" || return 0
    done
    # Never guessed as main: a source with no checkout yet waits, visibly. It
    # holds back no note already known to be this project's: that one goes now.
    if jq -e --arg k "$k" --arg m "$PP_MAIN" --arg w "$WS" "$PP_PNORM"'($m | pnorm) as $m | ($w | pnorm) as $w | .groups[$k].members | any(.[]; .cwd == null)
        and (any(.[]; .cwd != null and (.cwd | pnorm | . == $m or startswith($m + "/") or startswith($w + "/"))) | not)' >/dev/null <<<"$led"; then
      # It waits while the offer is still shown. Once the offer is gone and no
      # transcript ever named the session, it would wait for good: it is put on
      # the handled list unsent, and said so; its text stays in the archive.
      for p in $(jq -r --arg k "$k" '.groups[$k].members[] | select(.cwd == null) | "\(.id)@\(.shownAt)"' <<<"$led"); do
        ! hu_shown "${p%@*}" "${p##*@}" || { echo "main-watch: heads-up $k waits: no transcript names its session's checkout yet" >&2; continue 2; }
      done
      { jq -r --arg k "$k" '.pairs | to_entries[] | select(.value == $k) | .key' <<<"$led"; echo "$k"; } >> "$HU_DONE" \
        && echo "main-watch: heads-up $k dropped: its offer is gone and no transcript ever named its session's checkout; the text is kept in $HU_LOG" >&2
      continue
    fi
    # The offer store is the machine's and every project runs a watcher: only
    # notes from this project's checkouts go to this project's main, and only
    # those members are quoted.
    led=$(jq -c --arg k "$k" --arg m "$PP_MAIN" --arg w "$WS" "$PP_PNORM"'($m | pnorm) as $m | ($w | pnorm) as $w | .groups[$k].members |= map(select(.cwd != null and (.cwd | pnorm | . == $m or startswith($m + "/") or startswith($w + "/"))))' <<<"$led")
    jq -e --arg k "$k" '.groups[$k].members | length > 0' >/dev/null <<<"$led" || continue
    subj=$(jq -r --arg k "$k" --arg m "$PP_MAIN" "$PP_PNORM"'($m | pnorm) as $m | .groups[$k] | "heads-up: \([.members[] | if (.cwd | pnorm) == $m then "main" else (.cwd | split("/") | last) end] | unique | join(", ")) -- \(.line)"' <<<"$led")
    body=$(jq -r --arg k "$k" --arg m "$PP_MAIN" --arg log "$HU_LOG" "$PP_PNORM"'($m | pnorm) as $m | .groups[$k]
      | "This note is another model'"'"'s unverified claim. Main must verify it against code or live state before acting.\nLine: \(.line)\n\n"
        + ([.members[] | "From \(if (.cwd | pnorm) == $m then "main" else (.cwd | split("/") | last) end): session \(.id), shown \(.utc) (shownAt \(.shownAt) ms)\nCheckout: \(.cwd)\nExplanation:\n\(.explanation)"] | join("\n\n"))
        + "\n\nFull text archived in \($log)."' <<<"$led")
    # A note repeating the line of another note already posted is routine (issue 253): the digest, not a second
    # message. heads-up-lines keeps <key><TAB><line> per posted note.
    p=$(jq -r --arg k "$k" '.groups[$k].line | gsub("[\t\n]"; " ")' <<<"$led")
    if awk -F'\t' -v k="$k" -v l="$p" '$1 != k && $2 == l { f = 1 } END { exit !f }' "$ST/heads-up-lines" 2>/dev/null; then
      echo handled > "$ST/item-$k"; hu_done "$k" "$led" && digest "heads-up repeated: ${subj#heads-up: }"; continue
    fi
    post "$k" "" "$subj" "$body" once
    grep -qF -- "$k"$'\t' "$ST/heads-up-lines" 2>/dev/null || printf '%s\t%s\n' "$k" "$p" >> "$ST/heads-up-lines"
    # In the tick that marks it, not the next: the temp folder may be gone by then.
    hu_done "$k" "$led" || true
  done
}

# trim_log -- launchd holds the watcher's own log open, so it is cut in place (same inode) and not renamed: past 1 MiB
# it keeps its last 512 KiB.
trim_log() {
  local f=$SCRATCH/scratchpad/$NAME.log
  [ -e "$f" ] && [ "$(wc -c < "$f")" -gt 1048576 ] || return 0
  tail -c 524288 "$f" > "$f.cut" && cat "$f.cut" > "$f"
  rm -f "$f.cut"
}

tick() {
  trim_log
  claude_dir
  # Before the run lookup: a leak is reaped whether or not main can be told.
  reap_brokers
  heads_up_capture
  RUN=$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE")
  [ -n "$RUN" ] || { echo "main-watch: no current run; nothing to post to" >&2; return 0; }
  NOW=${COMMANDECK_NOW:-$(date +%s)}
  DIAG= DIAG_KEYS= REBOUND= RELAY=0
  # Read once a tick: every post and the heads-up relay stand down under it (hu_claimed).
  CLAIMED=0
  if hu_claimed; then
    CLAIMED=1
    [ "$(cat "$ST/hu-yield" 2>/dev/null)" = "$HU_PID" ] || { echo "$HU_PID" > "$ST/hu-yield"
      echo "main-watch: nothing is posted (finished, stopped, stalled, heads-up): pid $HU_PID claims this checkout's items for $PP_MAIN ($PP_SCRATCH/heads-up-owner)" >&2; }
  else rm -f "$ST/hu-yield"
  fi
  # A failed task list cannot tell handled from open; skip rather than guess.
  # A fenced one would silence every item, so main hears it (rebind was tried).
  if ! orca_op '.result.tasks' orca-ide orchestration task-list --run "$RUN" --json; then
    echo "main-watch: task-list failed; skipping this tick: $OP_ERR" >&2
    [ -z "$REBOUND" ] || { note "task list: $OP_ERR" task-list; arm_diag; wake; }
    return 0
  fi
  TASKS=$OP_OUT
  local ps terms r f u h t role launched sid
  # LISTED=0 when Orca could not list panes: then every pane would read as gone.
  LISTED=1
  ps=$(orca-ide worktree ps --json 2>/dev/null) || { ps='{}'; LISTED=0; }
  terms=$(orca-ide terminal list --json 2>/dev/null) || { terms='{}'; LISTED=0; }
  # An error reply that exits zero lists nothing either.
  jq -e '.result | type == "object"' <<<"$ps" >/dev/null 2>&1 || { ps='{}'; LISTED=0; }
  jq -e '.result | type == "object" or type == "array"' <<<"$terms" >/dev/null 2>&1 || { terms='{}'; LISTED=0; }
  # handle<TAB>Orca agent state, joined on the pane key as close-done-panes.sh does.
  STATES=$(jq -rn --argjson ps "$ps" --argjson ts "$terms" '
    ([$ps.result.worktrees[]?.agents[]?] | map({(.paneKey // ""): .state}) | add // {}) as $a
    | ($ts.result | if type == "array" then . else (.terminals // []) end)[]?
    | "\(.handle)\t\($a["\(.tabId):\(.leafId)"] // "none")"' 2>/dev/null)
  resolve_main "$ps" "$terms"
  MAIN_BUSY=0
  [ "$MAIN_STATE" = working ] && MAIN_BUSY=1
  DUE_KEY=() DUE_TASK=() DUE_SUBJ=() DUE_BODY=() MERGE=()
  proc_warn
  builder_watch

  # A seat another host's run placed here is marked so (origin= line): that run
  # hears of it, and posting it here too would wake a second main.
  # One awk over every record, as in close-done-panes.sh: thirteen processes a
  # record was most of a tick. Each key's first line counts, the last
  # for session=. The separator is not whitespace, so an empty field keeps its
  # place; not a pipe: a subshell would drop the items this tick batches.
  while IFS=$'\x1f' read -r h t u role launched sid tag wt; do
    seat "$h" "$t" "$u" "$role" "$launched" "$sid" "$tag" "$wt"
  done < <(awk -F= -v OFS=$'\x1f' '
    function out() { if (FILENAME != "" && !("origin" in v)) print v["handle"], v["task"], v["unit"], v["role"], v["launched"], v["session"], v["tag"], v["worktree"] }
    FNR == 1 { if (NR > 1) out(); split("", v) }
    /^(handle|task|unit|role|launched|origin|tag|worktree)=/ { if (!($1 in v)) v[$1] = substr($0, length($1) + 2); next }
    /^session=/ { v["session"] = substr($0, 9) }
    END { if (NR) out() }' "$SCRATCH"/seat-*.txt 2>/dev/null)
  merge_collect
  merge_start
  flush
  arm_diag
  mail_wake
  wake
  if [ -d "$PP_WORKSPACES/Chief-of-Staff" ]; then relay_picker "$terms"; else rm -f "$ST/relay-picker.json"; fi
  # Heads-up notes are their own batch, after the typed wake and its diagnostic:
  # inbox only, success or refusal.
  DUE_KEY=() DUE_TASK=() DUE_SUBJ=() DUE_BODY=() RELAY=1
  heads_up_post
  flush
  RELAY=0
  # Finished and orphaned panes are closed here, after this tick's items went
  # out with the panes still listed; an open pane holds RAM.
  local swept
  [ "$LISTED" = 1 ] || return 0
  if swept=$(COMMANDECK_PS_JSON="$ps" COMMANDECK_TERMINALS_JSON="$terms" bash "$HERE/close-done-panes.sh" --close 2>&1); then
    [ -z "$swept" ] || printf '%s\n' "$swept"
  else
    echo "main-watch: pane sweep failed: $(tail -1 <<<"$swept" | cut -c1-200)" >&2
  fi
}

# The long-lived loop's stderr drops a line identical to the one before and says how many it dropped when a new line
# comes, so a failure that repeats every tick does not fill the log. --once keeps plain stderr.
FILT=
if [ "${1:-}" != --once ]; then
  exec 2> >(awk '$0 == last && NR > 1 { n++; next } { if (n) printf "(repeated %d times)\n", n; n = 0; last = $0; print; fflush() }
    END { if (n) printf "(repeated %d times)\n", n }' >&2)
  FILT=$!
fi
TICKN=0
while :; do
  ! restart_due || restart_later
  tick
  [ "${1:-}" = --once ] && break
  # Test seam: end the loop after this many ticks.
  TICKN=$((TICKN + 1)); [ -z "${COMMANDECK_MAIN_WATCH_MAX_TICKS:-}" ] || [ "$TICKN" -lt "$COMMANDECK_MAIN_WATCH_MAX_TICKS" ] || break
  sleep "$TICK"
done
[ -z "$FILT" ] || { exec 2>&-; wait "$FILT" 2>/dev/null || true; }
