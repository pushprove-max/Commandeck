#!/usr/bin/env bash
# timeout: 240
# main-watch.sh is the one thing that wakes main: every tick it posts each
# "finished, not handled" item to the run, and re-posts it every 5 minutes
# until main closes the item's task. Each case below is a way a wake was lost
# or faked before, or a service the plugin must be able to install.
#
# The fake orca-ide plays a timeline from files the test rewrites between ticks
# (agents: `<handle> <state>`, tasks: `<task> <status>`) and records every send.
# Each tick is one `--once` run, with COMMANDECK_NOW as the clock, so a service
# restart is simply the next run and no case sleeps.
set -euo pipefail

SOURCE=$(git rev-parse --show-toplevel)
# Physical path: macOS /tmp is a symlink, and main-watch finds main's pane by
# comparing Orca's worktreePath with the checkout's physical path.
T=$(cd "$(mktemp -d /tmp/main-watch-test.XXXXXX)" && pwd -P)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; [ ! -s "$T/sends" ] || { echo "sends were:" >&2; cat "$T/sends" >&2; }; exit 1; }

REPO=$T/repo S=$T/scratch F=$T/fake
mkdir -p "$REPO/scripts" "$T/bin" "$S" "$F" "$T/home/.config/orca" "$T/ws"
git -C "$REPO" init -q
cp "$SOURCE/scripts/main-watch.sh" "$SOURCE/scripts/paths.sh" "$SOURCE/scripts/project-main.sh" "$SOURCE/scripts/requirements.sh" \
   "$SOURCE/scripts/host-services.sh" "$SOURCE/scripts/orca-task-create.sh" "$SOURCE/scripts/dashboard_builders.jq" "$REPO/scripts/"
mkdir -p "$REPO/config"; cp "$SOURCE/config/routing.json" "$REPO/config/"
# read-verdict.sh stands in for a seat's own output: `verdict-<handle>` files.
# Every pane read is logged to `rv-reads`. No verdict is the real script's exit 3;
# an `rvfail-<handle>` file is a read that failed (a timeout, no buffer).
cat > "$REPO/scripts/read-verdict.sh" <<RV
#!/usr/bin/env bash
[ "\$1" = --state ] && { echo "\$*" >> "$F/state-reads"; cat "$F/state-\${3##*/}" 2>/dev/null; exit 0; }
echo "\$1" >> "$F/rv-reads"
echo "\$1 \${8:-}" >> "$F/rv-cutoffs"
[ ! -e "$F/rvfail-\$1" ] || exit 1
cat "$F/verdict-\$1" 2>/dev/null || exit 3
RV
# The pane sweep stands in as a recorder: its args, the JSON it was handed, and
# a failure whenever `sweep-fail` exists.
cat > "$REPO/scripts/close-done-panes.sh" <<SW
#!/usr/bin/env bash
printf '%s|%s|%s\n' "\$*" "\$(jq -c . <<<"\$COMMANDECK_PS_JSON")" "\$(jq -c . <<<"\$COMMANDECK_TERMINALS_JSON")" >> "$F/sweeps"
[ ! -e "$F/sweep-fail" ] || { echo "sweep boom" >&2; exit 1; }
SW
# The machine-wide file names another project's run: each project reads its own.
echo run_foreign > "$T/home/.config/orca/current-run"
mkdir -p "$S" && echo run_test > "$S/current-run"
export COMMANDECK_HOST_OS=Linux  # the systemctl stub is the service manager
: > "$F/agents"; : > "$F/tasks"; : > "$T/sends"; : > "$F/unread"; : > "$T/nudges"; : > "$T/binds"

# Both service managers record their calls. `launchctl list` answers from `jobs`.
cat > "$T/bin/systemctl" <<SC
#!/usr/bin/env bash
echo "\$*" >> "$F/systemctl"
case " \$* " in *" is-active "*) echo inactive; exit 3 ;; esac
exit 0
SC
cat > "$T/bin/launchctl" <<LC
#!/usr/bin/env bash
echo "\$*" >> "$F/launchctl"
[ "\$1" != list ] || cat "$F/jobs" 2>/dev/null
[ "\$1" != print ] || exit 1   # no such job: it is gone
exit 0
LC
# No processes: the broker reaper must never see or signal this machine's own.
# One pid's start time is the real answer: a wait file is checked against it.
printf '#!/usr/bin/env bash\ncase "$*" in *lstart=*) exec /bin/ps "$@" ;; esac\nexit 0\n' > "$T/bin/ps"
cat > "$T/bin/orca-ide" <<ORCA
#!/usr/bin/env bash
FENCED='{"ok":false,"error":{"message":"This coordinator terminal is no longer bound to Run run_test. Orchestration mutation request ID: r1."}}'
case "\$1 \$2" in
  "orchestration task-list")
    jq -Rn '{result:{tasks:[inputs | split(" ") | {id:.[0], status:.[1]}]}}' < "$F/tasks" ;;
  "orchestration task-create")
    # Real Orca refuses an unattributed create from a service with no terminal,
    # and one from a pane the run is no longer bound to (\`coord\` names the run's).
    case "\$*" in *"--from \$(cat "$F/coord" 2>/dev/null || echo term_main) "*) ;;
      *"--from "*) echo "\$FENCED"; exit 1 ;; *) echo '{"ok":false,"error":{"code":"no_active_sender_terminal"}}'; exit 1 ;; esac
    n=\$(( \$(wc -l < "$F/tasks") + 1 )); echo "task_new\$n pending" >> "$F/tasks"
    echo "{\"ok\":true,\"result\":{\"task\":{\"id\":\"task_new\$n\"}}}" ;;
  "orchestration run-use")
    # Every bind is recorded. rebind-refuse: ok:false, exit 0; the run does not move.
    printf '%s\n' "\$*" >> "$T/binds"
    [ ! -e "$F/rebind-refuse" ] || { echo '{"ok":false,"error":{"message":"run-use refused"}}'; exit 0; }
    sed -n 's/.*--from \([^ ]*\).*/\1/p' <<<"\$*" > "$F/coord"; echo '{"ok":true}' ;;
  "orchestration send")
    # A send from a pane the run is no longer bound to is refused.
    case "\$*" in *"--from \$(cat "$F/coord" 2>/dev/null || echo term_main) "*) ;;
      *) echo "\$FENCED"; exit 0 ;; esac
    printf '%s' "\$*" | tr '\n' ' ' >> "$T/sends"; echo >> "$T/sends"
    # Every accepted send is unread in main's inbox.
    echo x >> "$F/unread"
    a=("\$@"); for i in "\${!a[@]}"; do case \${a[i]} in
      --subject) printf '%s' "\${a[i+1]}" > "$T/last-subject" ;; --body) printf '%s' "\${a[i+1]}" > "$T/last-body" ;; esac; done
    echo '{"ok":true}' ;;
  "terminal send") # a typed wake; nosubmit: Orca's receipt shows no turn started
    printf '%s\n' "\$*" >> "$T/nudges"
    if [ -e "$F/nosubmit" ]; then echo '{"ok":true,"result":{"stages":["typed"]}}'
    else echo '{"ok":true,"result":{"stages":["typed","submitted","turn_started"]}}'; fi ;;
  "terminal read") # --screen: the visible screen; else the output lines and Orca's cursor
    printf '%s\n' "\$*" >> "$T/reads"
    case "\$*" in
      *--screen*) jq -n --arg t "\$(cat "$F/screen-\$4" 2>/dev/null)" '{result:{terminal:{tail:[\$t]}}}' ;;
      *) jq -Rn '[inputs] | {result:{terminal:{tail:., latestCursor:(length | tostring)}}}' < "$F/out-\$4" 2>/dev/null \
           || echo '{"result":{"terminal":{"tail":[],"latestCursor":"0"}}}' ;;
    esac ;;
  "terminal list")
    [ ! -e "$F/down" ] || exit 1
    jq -Rn --arg main "$REPO" '{result:{terminals:[inputs | split(" ") | {handle:.[0], tabId:.[0], leafId:"l",
      worktreePath:(if (.[0] | startswith("term_main")) then \$main else "/elsewhere" end), agentIdentity:"claude"}]}}' < "$F/agents" ;;
  "orchestration inbox") # one unread run message per line of \`unread\`; inbox-full: a full page of another run's mail
    if [ -e "$F/inbox-full" ]; then jq -n '{ok:true, result:{messages:[range(500) | {run_id:"run_x", to_handle:"run:run_x", read:0}]}}'
    else jq -Rn '{ok:true, result:{messages:[inputs | {run_id:"run_test", to_handle:"run:run_test", read:0}]}}' < "$F/unread"; fi ;;
  "orchestration run-list")
    jq -n --arg c "\$(cat "$F/coord" 2>/dev/null)" '{result:{runs:[{id:"run_test", coordinator_handle:(if \$c == "" then null else \$c end)}]}}' ;;
  "worktree ps")
    [ ! -e "$F/rpc-error" ] || { echo '{"ok":false,"error":{"code":"runtime_unavailable"}}'; exit 0; }
    jq -Rn '{result:{worktrees:[{agents:[inputs | split(" ") | {paneKey:(.[0] + ":l"), state:.[1]}]}]}}' < "$F/agents" ;;
  *) echo '{}' ;;
esac
ORCA
chmod +x "$T/bin/orca-ide" "$T/bin/systemctl" "$T/bin/launchctl" "$T/bin/ps"

mw() { (cd "$REPO" && PATH=$T/bin:$PATH HOME=$T/home COMMANDECK_SCRATCH=$S COMMANDECK_WORKSPACES=$T/ws bash scripts/main-watch.sh "$@"); }
tick() { COMMANDECK_NOW=$1 mw --once 2>>"$T/stderr" || fail "main-watch exited non-zero at $1"; }
seat() { # unit handle task [launched] -- a seat record as seat.sh writes it
  mkdir -p "$T/ws/$1"
  printf 'handle=%s\ntask=%s\nrole=implementer\nunit=%s\nlaunched=%s\n' "$2" "$3" "$1" "${4:-1000}" > "$S/seat-$1-implementer.txt"
  echo "$3 running" >> "$F/tasks"
}
state() { sed -i "/^$1 /d" "$F/agents"; echo "$1 $2" >> "$F/agents"; }
posts() { grep -c -- "${1:-orchestration send}" "$T/sends" || true; }
fin() { # unit epoch -- a seat seen working, then done with its verdict, one tick later
  seat "$1" "term_$1" "task_$1" "$2"; echo 'VERDICT: GO' > "$F/verdict-term_$1"
  state "term_$1" working; tick "$2"; state "term_$1" "done"; tick $(($2 + 60))
}
settle() { # every item so far is handled and its seat record gone
  rm -f "$S"/seat-*.txt "$S/main-watch/wake"; sed -i 's/ running$/ completed/; s/ pending$/ completed/' "$F/tasks"
  : > "$T/sends"; : > "$T/nudges"; : > "$T/stderr"; : > "$T/binds"
}
# Main's pane is the sender of every create and send; idle, so repeats are not held.
state term_main idle

# Helpers of the heads-up and Builder cases, up here so a refute file gets them
# from the set-up half.
HUSTORE=$T/home/.claude/plugins/store/cc-plugin-you-should-know_builtin-t1.json
HULOG=$S/main-watch/heads-up-log.jsonl
mkdir -p "${HUSTORE%/*}"
transcript() { # session cwd -- a Claude transcript whose first records name no cwd
  local d; d=$T/home/.claude/projects/$(printf '%s' "$2" | sed 's#[/.]#-#g'); mkdir -p "$d"
  printf '{"type":"mode","cwd":null}\nnot json\n{"type":"user","cwd":"%s","sessionId":"%s"}\n' "$2" "$1" > "$d/$1.jsonl"
}
offers() { # (<session> <shownAt ms> <line> <explanation>)... -- the store as the mod writes it
  local s='[]'
  while [ "$#" -ge 4 ]; do
    s=$(jq -c --arg id "$1" --argjson at "$2" --arg l "$3" --arg e "$4" \
      '. + [{id:$id, askedTurn:3, view:{kind:"offer", line:$l, explanation:$e, shownAt:$at}}]' <<<"$s")
    shift 4
  done
  jq -n --argjson s "$s" '{sessions:($s + [{id:"cccc0000-0000-0000-0000-00000000000c", askedTurn:1, view:{kind:"dismissed"}}])}' > "$HUSTORE"
}
hu() { grep -c '^orchestration send .*--subject heads-up: ' "$T/sends" || true; }
has() { # <what> <text>... -- each text is in the last send's body
  local b k w=$1; b=$(cat "$T/last-body"); shift
  for k in "$@"; do case $b in *"$k"*) ;; *) fail "$w: the relay body lacks '$k'" ;; esac; done
}
bseat() { mkdir -p "$T/ws/$1/.claude"; printf 'handle=%s\ntask=%s\nrole=builder\nunit=%s\nlaunched=%s\n' "$2" "$3" "$1" "$4" > "$S/seat-$1-builder.txt"; echo "$3 running" >> "$F/tasks"; }
bstart() { jq -nc --argjson t "$1" --arg u "$2" '{ts: ($t | todate), event: "tool-start", use: $u, tool: "Bash", kind: "shell", call: $u}'; }
nudges() { grep -c -- "terminal send --terminal $1 --text Signal" "$T/nudges" || true; }

# A refute file loads the set-up and the helpers, and none of the cases. One
# tick first: the watcher posts only what finished after its first tick.
if [ "${MAIN_WATCH_TEST_HALF:-}" = setup ]; then tick 22990; return 0; fi

# 0. THE SERVICE INSTALLS ON BOTH HOSTS, under the plugin's own label and the
#    project's name: one job per project, so a second project's install does
#    not replace the first's, and another tool's main-watch.service is not
#    ours. The job has no folder of its own, so it carries the project it
#    watches. --status names the install command by a path that works from
#    any project.
mw --install >/dev/null || fail "--install failed on Linux"
U=$T/home/.config/systemd/user/commandeck-main-watch-repo.service
M=$(cd "$REPO" && pwd -P)
grep -qx "Environment=\"COMMANDECK_MAIN=$M\"" "$U" || fail "the systemd unit does not name the project it watches: $(cat "$U")"
# The job reads its run and seat records where the install was told they are:
# without these it would watch the default folders and miss every finish.
grep -qx "Environment=\"COMMANDECK_SCRATCH=$S\"" "$U" && grep -qx "Environment=\"COMMANDECK_WORKSPACES=$T/ws\"" "$U" \
  || fail "the systemd unit drops the scratch or workspace folder the install ran with: $(cat "$U")"
grep -q "^ExecStart=\"[^\"]*\" \"$REPO/scripts/main-watch.sh\"$" "$U" || fail "the systemd unit does not run the plugin's script: $(cat "$U")"
grep -q '^Restart=always$' "$U" || fail "the systemd unit does not restart the service"
grep -q -- '--user enable commandeck-main-watch-repo.service' "$F/systemctl" || fail "the systemd unit was not enabled"
# enable alone leaves a running watcher on the old script after an update.
grep -q -- '--user restart commandeck-main-watch-repo.service' "$F/systemctl" || fail "the systemd unit was not restarted, so a running watcher keeps the old script"
# The job is named after the checkout's folder. Another checkout with the same
# folder name must not take this one's job over, nor take it away.
mkdir -p "$T/other"; cp -R "$REPO" "$T/other/repo"
mw2() { (cd "$T/other/repo" && PATH=$T/bin:$PATH HOME=$T/home COMMANDECK_SCRATCH=$S COMMANDECK_WORKSPACES=$T/ws bash scripts/main-watch.sh "$@"); }
! mw2 --install >/dev/null 2>"$T/other/err" || fail "a second checkout of the same folder name installed over the first's job"
grep -qx "Environment=\"COMMANDECK_MAIN=$M\"" "$U" || fail "the first checkout's systemd unit was replaced: $(cat "$U")"
grep -q "$M" "$T/other/err" || fail "the refusal does not name the checkout that owns the job: $(cat "$T/other/err")"
mw2 --uninstall >/dev/null 2>&1; [ -e "$U" ] || fail "a second checkout's uninstall removed the first's systemd unit"
COMMANDECK_HOST_OS=Darwin mw --install >/dev/null || fail "--install failed on the Mac"
P=$T/home/Library/LaunchAgents/com.commandeck.main-watch-repo.plist
! COMMANDECK_HOST_OS=Darwin mw2 --install >/dev/null 2>&1 || fail "a second checkout of the same folder name installed over the first's launchd job"
COMMANDECK_HOST_OS=Darwin mw2 --uninstall >/dev/null 2>&1; [ -e "$P" ] || fail "a second checkout's uninstall removed the first's launchd job"
rm -rf "$T/other"
grep -q '<key>Label</key><string>com.commandeck.main-watch-repo</string>' "$P" || fail "the launchd job is not under the plugin's label and the project's name"
grep -q "<key>COMMANDECK_MAIN</key><string>$M</string>" "$P" || fail "the launchd job does not name the project it watches"
grep -q "<key>COMMANDECK_SCRATCH</key><string>$S</string>" "$P" && grep -q "<key>COMMANDECK_WORKSPACES</key><string>$T/ws</string>" "$P" \
  || fail "the launchd job drops the scratch or workspace folder the install ran with"
grep -q "<string>$REPO/scripts/main-watch.sh</string>" "$P" && grep -q '<key>KeepAlive</key><true/>' "$P" \
  || fail "the launchd job does not keep the plugin's script alive"
grep -q "^bootstrap gui/[0-9]* $P$" "$F/launchctl" || fail "the launchd job was not started"
# bootout returns before the job is gone, and a bootstrap in that window fails (error 5).
grep -q '^print gui/[0-9]*/com.commandeck.main-watch-repo$' "$F/launchctl" || fail "the old launchd job was not waited out before the new one was started"
# launchd does not make a log's folder, and a job whose log cannot be opened never starts.
LOGDIR=$(sed -n 's|.*<key>StandardOutPath</key><string>\(.*\)/main-watch.log</string>.*|\1|p' "$P")
[ -n "$LOGDIR" ] && [ -d "$LOGDIR" ] || fail "the launchd job's log folder does not exist after install: $LOGDIR"
out=$(COMMANDECK_HOST_OS=Darwin mw --status) && fail "--status reported a service that is not running"
grep -q "MAIN-WATCH NOT RUNNING.*bash $REPO/scripts/main-watch.sh --install" <<<"$out" || fail "--status does not name the install command by its full path: $out"
printf '123\t0\tcom.commandeck.main-watch-repo\n' > "$F/jobs"
COMMANDECK_HOST_OS=Darwin mw --status | grep -qx 'main-watch: running' || fail "--status missed a running launchd job"
# Uninstall takes the job away on both hosts and leaves the state it kept.
mkdir -p "$S/main-watch"; touch "$S/main-watch/kept"
mw --uninstall >/dev/null || fail "--uninstall failed on Linux"
[ ! -e "$U" ] || fail "--uninstall left the systemd unit"
grep -q -- '--user disable --now commandeck-main-watch-repo.service' "$F/systemctl" || fail "the systemd unit was not stopped"
COMMANDECK_HOST_OS=Darwin mw --uninstall >/dev/null || fail "--uninstall failed on the Mac"
[ ! -e "$P" ] || fail "--uninstall left the launchd plist"
grep -q '^bootout gui/[0-9]*/com.commandeck.main-watch-repo$' "$F/launchctl" || fail "the launchd job was not stopped"
[ -e "$S/main-watch/kept" ] || fail "--uninstall removed the watcher's state"
rm -rf "$S/main-watch" "$F/jobs"

# 1. A BOOT `done` IS NOT A FINISH. Orca reads a fresh pane `done` before its
#    spec starts it; the real finish comes after `working`.
seat wt-blip term_blip task_blip
state term_blip "done";  tick 2000; tick 2060; tick 2090
[ "$(posts)" = 0 ] || fail "a boot done blip was posted as a finish"
# A boot `done` is read once, then remembered, not on every tick until closed.
[ "$(grep -cx term_blip "$F/rv-reads")" = 1 ] || fail "a boot done pane was re-read every tick: $(grep -cx term_blip "$F/rv-reads") reads"
state term_blip working; tick 2120
state term_blip "done";  tick 2180
[ "$(posts)" = 1 ] || fail "the real finish after working was not posted exactly once"
grep -q -- '--to run:run_test' "$T/sends" || fail "the post did not go to the current run"
# The close hint must run from main's project, where the plugin's scripts are not.
grep -q "\. $REPO/scripts/paths.sh && pp_task_close task_blip completed" "$T/sends" || fail "the close hint is not the dispatch-ending pp_task_close by full path"
tick 2240
[ "$(posts)" = 1 ] || fail "a finish was re-posted inside the 5-minute window"

# 2. MAIN DOES NOTHING. No task is closed: re-post after 5 minutes, then
#    silence once main completes the task.
tick 2481
[ "$(posts wt-blip)" = 2 ] || fail "an unhandled item was not re-posted after 5 minutes"
sed -i 's/^task_blip running$/task_blip completed/' "$F/tasks"
tick 2800; tick 3200
[ "$(posts wt-blip)" = 2 ] || fail "an item was posted again after main completed its task"

# 3. A FAST FINISH BETWEEN TICKS. The seat went working -> done inside one tick,
#    so the service never saw `working`; its verdict is in its own output.
settle
seat wt-fast term_fast task_fast 5000
echo 'VERDICT: GO' > "$F/verdict-term_fast"
state term_fast "done"; tick 5060
[ "$(posts wt-fast)" = 1 ] || fail "a fast finish with a verdict present was not posted"
# Only a read that ANSWERED is remembered: a failed first read is retried.
seat wt-flaky term_flaky task_flaky 5000
: > "$F/rvfail-term_flaky"; state term_flaky "done"; tick 5120
rm "$F/rvfail-term_flaky"; echo 'VERDICT: GO' > "$F/verdict-term_flaky"; tick 5180
[ "$(posts wt-flaky)" = 1 ] || fail "a finished pane whose first read failed was never posted"
# The same for a seat that was seen working: a read that failed says nothing
# about how it ended, and settling it as silent would hide the finish for good.
seat wt-flaky2 term_flaky2 task_flaky2 5200
state term_flaky2 working; tick 5200
: > "$F/rvfail-term_flaky2"; state term_flaky2 "done"; tick 5260
[ "$(posts wt-flaky2)" = 0 ] || fail "a seat whose result could not be read was settled anyway: $(grep wt-flaky2 "$T/sends" | tail -1)"
rm "$F/rvfail-term_flaky2"; echo 'VERDICT: GO' > "$F/verdict-term_flaky2"; tick 5320
grep 'wt-flaky2' "$T/sends" | tail -1 | grep -q 'finished' || fail "a worked seat whose first read failed was not posted as finished: $(grep wt-flaky2 "$T/sends" | tail -1)"

# 4. STOPPED WITHOUT REPORTING. A seat that went working -> done with no marker
#    or verdict did not finish; a pane that vanished is the same item.
settle
seat wt-silent term_silent task_silent 7000
state term_silent working; tick 7000
state term_silent "done";  tick 7060
grep -q 'wt-silent implementer stopped without reporting; inspect' "$T/sends" \
  || fail "a seat that stopped with no marker was not posted as stopped without reporting"
! grep -q 'on wt-silent finished' "$T/sends" || fail "a seat that stopped with no marker was posted as finished"
seat wt-gone term_gone task_gone 7000
state term_gone working; tick 7100
sed -i '/^term_gone /d' "$F/agents"; tick 7160
grep -q 'wt-gone implementer stopped without reporting; inspect' "$T/sends" || fail "a gone pane was not posted as stopped without reporting"
# Orca failing to list panes is not every pane gone.
seat wt-down term_down task_down 7000
state term_down working; tick 7200
: > "$F/down"; tick 7260; rm "$F/down"
[ "$(posts wt-down)" = 0 ] || fail "a failed pane listing was posted as a gone pane"
# Nor is an error reply that exits zero from the agent-state call: every pane would read as having no agent.
: > "$F/rpc-error"; tick 7320; rm "$F/rpc-error"
[ "$(posts wt-down)" = 0 ] || fail "an error reply from the pane listing was posted as a gone pane"

# 5. STALLED. A seat Orca still calls working, whose session log and pane have
#    not changed for 20 minutes, is hung. A log that grows is alive. The stall
#    has no task: one is made on its first post, and a restarted service
#    neither loses the item nor mints a second task.
settle
stall_seat() { # unit -- a seat with a Claude session log on disk
  local d; d=$T/home/.claude/projects/$(printf '%s' "$T/ws/$1" | sed 's#/#-#g')
  seat "$1" "term_$1" "task_$1" 8000; echo "session=sid-$1" >> "$S/seat-$1-implementer.txt"
  mkdir -p "$d"; echo '{}' > "$d/sid-$1.jsonl"; state "term_$1" working
}
stall_seat wt-stall; stall_seat wt-grow
GROW=$T/home/.claude/projects/$(printf '%s' "$T/ws/wt-grow" | sed 's#/#-#g')/sid-wt-grow.jsonl
for t in 8000 8300 8600 8900 9199; do echo '{"more":1}' >> "$GROW"; tick $t; done
[ "$(posts wt-stall)" = 0 ] || fail "a seat was posted as stalled before 20 minutes"
tick 9200
grep -q 'wt-stall implementer stalled; inspect' "$T/sends" || fail "a seat with no log or pane growth for 20 minutes was not posted as stalled"
echo '{"more":1}' >> "$GROW"; tick 9260
[ "$(posts wt-stall)" = 1 ] || fail "a restart re-posted inside 5 minutes"
echo '{"more":1}' >> "$GROW"; tick 9501
[ "$(posts wt-stall)" = 2 ] || fail "a restart lost the unhandled item"
[ "$(grep -c '^task_new' "$F/tasks")" = 1 ] || fail "the item got a second task: $(cat "$F/tasks")"
[ "$(posts wt-grow)" = 0 ] || fail "a seat whose log grows every few minutes was posted as stalled"
# A state that is neither working nor done (waiting for input) is posted after 2 min.
seat wt-wait term_wait task_wait 14000
state term_wait waiting; tick 14000; tick 14060
[ "$(posts wt-wait)" = 0 ] || fail "a waiting state held 1 minute was posted"
tick 14120
grep -q "wt-wait implementer stalled in Orca state waiting" "$T/sends" || fail "a waiting state held 2 minutes was not posted as stalled"

# 6. NO EXCESS TURNS. Every post that reaches main is a full context replay.
#    Items due in one tick go out as ONE message, each with its own task. A
#    repeat waits while main is working; a first post never waits.
settle
for u in wt-a wt-b wt-c wt-d; do
  seat $u term_$u task_$u 20000; echo 'VERDICT: GO' > "$F/verdict-term_$u"; state term_$u working
done
tick 20000
for u in wt-a wt-b wt-c; do state term_$u "done"; done
tick 20060
[ "$(posts)" = 1 ] || fail "three items due in one tick were not sent as one message"
[ "$(grep -o 'close task task_wt-[abc]' "$T/sends" | sort -u | wc -l | tr -d ' ')" = 3 ] || fail "the three items do not each carry their own task"
: > "$T/sends"
state term_main working; state term_wt-d "done"
tick 20361
[ "$(posts)" = 1 ] && grep -q 'on wt-d finished' "$T/sends" || fail "a first post was held while main was working"
! grep -q 'on wt-a finished' "$T/sends" || fail "a repeat was posted while main was working"
state term_main "done"; tick 20421
[ "$(posts wt-a)" = 1 ] || fail "a held repeat was not posted once main went idle"
state term_main idle
# A seat another host's run placed here is that run's to hear of.
: > "$T/sends"
seat wt-peer term_wt-peer task_wt-peer 20500; echo origin=run_origin >> "$S/seat-wt-peer-implementer.txt"
echo 'VERDICT: GO' > "$F/verdict-term_wt-peer"
state term_wt-peer working; tick 20500
state term_wt-peer "done";  tick 20560
[ "$(posts wt-peer)" = 0 ] || fail "a seat another run placed here was posted to this run"

# 7. A SECOND FINISH AFTER THE TASK CLOSED. Main sent the same pane a follow-up
#    and closed the first item's task meanwhile; the second finish is a new item.
settle
fin wt-again 21000
[ "$(posts wt-again)" = 1 ] || fail "the first finish was not posted"
state term_wt-again working; tick 21120
sed -i 's/^task_wt-again running$/task_wt-again completed/' "$F/tasks"
state term_wt-again "done";  tick 21180
[ "$(posts wt-again)" = 2 ] || fail "a finish after the task was closed was not posted again"
# The follow-up ran in the session the seat was launched with. read-verdict.sh
# drops every session log older than the time it is given, so it is given the
# launch time, never the follow-up's: that would leave only the pane's history.
[ "$(grep '^term_wt-again ' "$F/rv-cutoffs" | tail -1)" = "term_wt-again 21000" ] || fail "the follow-up's result was read with a cutoff other than the launch time: $(grep '^term_wt-again ' "$F/rv-cutoffs" | tail -1)"
grep -q 'close task task_new' <<<"$(tail -1 "$T/sends")" || fail "the second finish did not get a new task: $(tail -1 "$T/sends")"

# 7b. A WAIT FILE THAT OUTLIVED ITS WAIT. Scratch survives a reboot, so the pid
#     in `waiting-<handle>` can belong to another process by now; read as a live
#     wait, the finish was left to a wait that no longer exists. A wait that is
#     really running still owns its pane's report.
settle
printf '%s\nstart %s\n' "$$" "Thu Jan  1 00:00:00 1970" > "$S/waiting-term_wt-stale"
printf '%s\nstart %s\n' "$$" "$(LC_ALL=C /bin/ps -o lstart= -p $$ | xargs)" > "$S/waiting-term_wt-live"
echo "$$" > "$S/waiting-term_wt-nostart"
fin wt-stale 22000; fin wt-live 22100; fin wt-nostart 22200
[ "$(posts wt-stale)" = 1 ] || fail "a finish was left to a wait file whose pid is another process now"
[ ! -e "$S/waiting-term_wt-stale" ] || fail "the stale wait file was not removed"
[ "$(posts wt-nostart)" = 1 ] && [ ! -e "$S/waiting-term_wt-nostart" ] || fail "a wait file with no start time was trusted on its pid alone"
[ "$(posts wt-live)" = 0 ] && [ -e "$S/waiting-term_wt-live" ] || fail "a running wait lost its pane's report"

# 7b-2. THE CLOSE COMMAND IN A POST runs from a plugin folder with a space in
#     its name: unquoted, it sourced nothing, the task stayed open and the post
#     came back every five minutes.
settle; mkdir -p "$T/pl ug"; cp -R "$REPO/scripts" "$T/pl ug/"
seat wt-sp term_wt-sp task_wt-sp 22500; echo 'VERDICT: GO' > "$F/verdict-term_wt-sp"
state term_wt-sp working; tick 22500; state term_wt-sp "done"
(cd "$REPO" && COMMANDECK_NOW=22560 PATH=$T/bin:$PATH HOME=$T/home COMMANDECK_SCRATCH=$S COMMANDECK_WORKSPACES=$T/ws bash "$T/pl ug/scripts/main-watch.sh" --once 2>>"$T/stderr")
cmd=$(grep -o "handled = close task task_wt-sp: .*pp_task_close task_wt-sp completed[)']*" "$T/sends" | tail -1 | sed 's/^[^:]*: //')
[ -n "$cmd" ] || fail "no close command was posted from the spaced folder: $(cat "$T/sends")"
out=$(cd "$REPO" && PATH=$T/bin:$PATH HOME=$T/home COMMANDECK_SCRATCH=$S bash -c "$cmd" 2>&1) || true
! grep -q 'No such file' <<<"$out" || fail "the posted close command breaks at the space in the plugin path: $cmd -> $out"

# 7c. ONE WAIT REPORTS ONE FINISH. A wait that saw the pane's marker is that
#     turn's report. A follow-up sent with no wait ends on the same line within
#     five minutes: read as the same report, its finish never woke main.
settle
seat wt-warm term_wt-warm task_wt-warm 23000; echo 'VERDICT: GO' > "$F/verdict-term_wt-warm"
state term_wt-warm working; tick 23000
printf '%s\nseen %s %s\n' 1 23050 'VERDICT: GO' > "$S/waiting-term_wt-warm"
state term_wt-warm "done"; tick 23060; tick 23075
[ "$(posts wt-warm)" = 0 ] || fail "a finish its wait reported was posted again"
state term_wt-warm working; tick 23120; state term_wt-warm "done"; tick 23180
[ "$(posts wt-warm)" = 1 ] || fail "a follow-up that ended on the wait's marker within five minutes never woke main: $(cat "$T/sends")"
# A follow-up with its own wait is that wait's to report.
state term_wt-warm working; tick 23200
printf '%s\nseen %s %s\n' 1 23230 'VERDICT: GO' > "$S/waiting-term_wt-warm"
state term_wt-warm "done"; tick 23240
[ "$(posts wt-warm)" = 1 ] || fail "a follow-up its own wait reported was posted again"

# 8. A SEAT THAT READS BLANK WHILE IT WORKS (Orca does not bind every Codex
#    pane): a session log that grew within the stall window is still working.
settle
R=$T/home/.codex/sessions/2026/09/28/rollout-cx.jsonl
mkdir -p "${R%/*}"; echo '{}' > "$R"; echo "session=$R" > "$F/state-wt-cx"
seat wt-cx term_cx task_cx 24000
state term_cx working; tick 24000
state term_cx none; echo '{"more":1}' >> "$R"; tick 24060
[ "$(posts wt-cx)" = 0 ] || fail "a blank seat whose session log grew was posted as stopped"
tick 25300
grep -q 'wt-cx implementer stopped without reporting; inspect' "$T/sends" || fail "a blank seat with a quiet session log was not posted as stopped"

# 8b. A CODEX PANE ON THE MAC READS `none` FROM LAUNCH: it is never seen
#     working, so "only a pane this service saw alive" left it out for good.
#     Listed, with a session log found, it is alive. A pane with no log yet
#     (still booting) is not posted.
settle
R=$T/home/.codex/sessions/2026/09/28/rollout-cy.jsonl
echo '{}' > "$R"; echo "session=$R" > "$F/state-wt-cy"
seat wt-cy term_cy task_cy 25400; seat wt-boot term_boot task_boot 25400
state term_cy none; state term_boot none; tick 25400
echo '{"more":1}' >> "$R"; tick 25460
[ "$(posts wt-cy)" = 0 ] || fail "a pane blank from launch whose session log grew was posted as stopped"
tick 26760
grep -q 'wt-cy implementer stopped without reporting; inspect' "$T/sends" || fail "a pane blank from launch with a quiet session log was never posted"
[ "$(posts wt-boot)" = 0 ] || fail "a blank pane with no session log yet was posted"

# 8c. A SEAT THAT WORKS AND FINISHES BETWEEN TWO TICKS after its boot `done`
#     is never seen working. Its pane printed past the boot read, so it is
#     read again.
settle
seat wt-late term_late task_late 26800
state term_late "done"; tick 26800
echo 'VERDICT: GO' > "$F/verdict-term_late"; echo worked >> "$F/out-term_late"
tick 26860
[ "$(posts wt-late)" = 1 ] || fail "a seat that worked and finished between two ticks was never read again"

# 8d. THE SAME, WITH A PANE THAT PRINTED NOTHING NEW: the cursor did not move,
#     but the seat's session log grew.
settle
R=$T/home/.codex/sessions/2026/09/28/rollout-cz.jsonl
echo '{}' > "$R"; echo "session=$R" > "$F/state-wt-cz"
seat wt-cz term_cz task_cz 26870
state term_cz "done"; tick 26870
echo 'VERDICT: GO' > "$F/verdict-term_cz"; echo '{"more":1}' >> "$R"
tick 26930
[ "$(posts wt-cz)" = 1 ] || fail "a seat whose session log grew after its boot read, with a still pane, was never read again"

# 8e. A PANE THAT READS `none` FOR GOOD FINISHES TWICE. Main sent it a
#     follow-up; it is never seen working or done, so the session log growing
#     past the first finish is the only sign of the second.
settle
R=$T/home/.codex/sessions/2026/09/28/rollout-ca.jsonl
echo '{}' > "$R"; echo "session=$R" > "$F/state-wt-ca"
seat wt-ca term_ca task_ca 27000; echo 'VERDICT: GO' > "$F/verdict-term_ca"
state term_ca none; tick 27000; tick 27060
[ "$(posts wt-ca)" = 1 ] || fail "a blank pane's first finish was posted $(posts wt-ca) times, not once"
echo '{"more":1}' >> "$R"; tick 27120
[ "$(posts wt-ca)" = 2 ] || fail "a blank pane that finished a second time was not posted again"

# 9. FINISHED PANES ARE CLOSED EVERY TICK, from the JSON this tick already
#    fetched; the sweep's failure never costs main a wake.
settle; : > "$F/sweeps"
tick 27000
IFS='|' read -r sarg sps sts < "$F/sweeps"
[ "$sarg" = --close ] || fail "a tick did not run the pane sweep with --close"
[ "$sps" = "$(PATH=$T/bin:$PATH orca-ide worktree ps --json | jq -c .)" ] || fail "the sweep was not handed the tick's worktree ps JSON: $sps"
[ "$sts" = "$(PATH=$T/bin:$PATH orca-ide terminal list --json | jq -c .)" ] || fail "the sweep was not handed the tick's terminal list JSON: $sts"
: > "$F/sweep-fail"; : > "$T/stderr"
fin wt-swept 27000
[ "$(posts wt-swept)" = 1 ] || fail "a failed sweep stopped the tick's posts"
grep -q 'pane sweep failed' "$T/stderr" || fail "a failed sweep was not logged"
rm -f "$F/sweep-fail"; : > "$F/sweeps"
: > "$F/down"; tick 27120; rm -f "$F/down"
[ ! -s "$F/sweeps" ] || fail "the sweep ran on a tick whose pane list failed"

# 10. AN ACCEPTED INBOX SEND IS NOT A WAKE. Main gets one typed wake whose
#     receipt proves a turn started; an unproven wake is retried alone, a
#     bounded number of times; a busy or asking main is never typed into.
settle
fin wt-w1 28000
[ "$(grep -c -- '^terminal send --terminal term_main .*--enter --wait-submit' "$T/nudges")" = 1 ] || fail "an idle main the accepted send did not wake got no typed wake: $(cat "$T/nudges")"
settle; : > "$F/nosubmit"; ntasks=$(wc -l < "$F/tasks")
fin wt-w2 28100
tick 28220; tick 28280; tick 28340
[ "$(posts wt-w2)" = 1 ] || fail "an unproven wake re-sent the inbox message"
[ "$(wc -l < "$T/nudges" | tr -d ' ')" = 3 ] || fail "an unproven wake was not retried once per tick up to its bound: $(cat "$T/nudges")"
[ "$(wc -l < "$F/tasks")" = $((ntasks + 1)) ] || fail "an unproven wake minted another task"
grep -q 'wake not proven' "$T/stderr" || fail "an unproven wake logged no reason"
rm -f "$F/nosubmit"; settle
state term_main working
fin wt-w3 29000
[ "$(posts wt-w3)" = 1 ] || fail "a first post was held while main was working"
[ ! -s "$T/nudges" ] || fail "a working main was typed into"
state term_main idle; printf 'Which one?\n1. Yes\nEnter to select\n' > "$F/screen-term_main"
tick 29090
[ ! -s "$T/nudges" ] || fail "a main showing a question prompt was typed into"
rm -f "$F/screen-term_main"; tick 29120
[ "$(wc -l < "$T/nudges" | tr -d ' ')" = 1 ] || fail "the held wake was not typed once main was idle"

# 10b. THE INBOX IS THE WHOLE MACHINE'S, NEWEST FIRST. A full page of other
#      runs' mail says nothing about this run's: the wake is kept and typed.
settle; : > "$F/inbox-full"
fin wt-w4 29300
rm -f "$F/inbox-full"
[ "$(wc -l < "$T/nudges" | tr -d ' ')" = 1 ] || fail "a full page of other runs' mail was read as nothing unread, and the wake was dropped"

# 11. A FENCED MAIN. The run is bound to a pane that closed, so every send from
#     the live main is refused. The fence is repaired once a tick under main's
#     own handle; what is still undelivered reaches main as one typed line with
#     the command that takes the run back, and is never recorded as delivered.
settle
echo term_dead > "$F/coord"; : > "$F/rebind-refuse"
fin wt-f1 31740
[ "$(posts)" = 0 ] || fail "a fenced send counted as mail"
[ "$(grep -c -- '--id run_test --from term_main ' "$T/binds")" = 1 ] || fail "the refused tick did not try exactly one rebind under main's handle: $(cat "$T/binds")"
grep -q -- '^terminal send --terminal term_main .*NOT in your inbox.*wt-f1.*no longer bound to Run run_test.*orca-ide orchestration run-use --id run_test' "$T/nudges" \
  || fail "the diagnostic does not name the item, the refusal and the recovery command: $(cat "$T/nudges")"
! grep -qE '^handled$|^posted=.' "$S"/main-watch/item-seat-term_wt-f1-* 2>/dev/null || fail "a refused item was stamped as posted or handled"
rm -f "$F/rebind-refuse"; tick 31860
[ "$(cat "$F/coord")" = term_main ] || fail "the repair did not bind the run to main's own pane"
[ "$(posts wt-f1)" = 1 ] || fail "the repaired item was not sent in the tick that repaired the run"
rm -f "$F/coord"

# 12. HEADS-UP RELAY. Each Claude session's "you should know" offer reaches
#     main's inbox once, whole, named by the session's checkout, never typed.
#     The archive is this project's own, not a file every project shares.
settle
W1=aaaa1111-0000-0000-0000-000000000001 WCWD=$T/ws/wt-hu
EXPL='It said "quoted" and $(touch '"$T"'/pwned).'
transcript $W1 "$WCWD"
offers $W1 40000123 "The review skipped a seat." "$EXPL"
cp "$HUSTORE" "$T/store.before"
tick 40000
[ "$(hu)" = 1 ] || fail "a new offer did not reach main exactly once"
[ "$(cat "$T/last-subject")" = "heads-up: wt-hu -- The review skipped a seat." ] || fail "wrong relay subject: $(cat "$T/last-subject")"
case $(cat "$T/last-body") in *"$EXPL"*"archived in $HULOG"*) ;; *) fail "the relay body lacks the whole note or its archive: $(cat "$T/last-body")" ;; esac
[ "$(jq -r .explanation "$HULOG")" = "$EXPL" ] || fail "the offer was not archived whole in the project's own state"
[ ! -e "$T/home/.claude/heads-up-log.jsonl" ] || fail "the archive went to the file every project on the machine shares"
[ ! -s "$T/nudges" ] && [ ! -e "$S/main-watch/wake" ] || fail "a relay typed into a pane or armed a typed wake"
cmp -s "$HUSTORE" "$T/store.before" || fail "main-watch wrote the offer store"
[ ! -e "$T/pwned" ] || fail "the note's text was run as a command"
tick 40060; tick 40301
[ "$(hu)" = 1 ] && [ "$(wc -l < "$HULOG" | tr -d ' ')" = 1 ] || fail "a delivered heads-up was relayed or archived again"

# 13. WHAT THE PLUGIN LEFT OUT STAYS OUT. Loop done files and job wake logs
#     belong to drivers the plugin does not ship; neither is an item here.
settle; mkdir -p "$S/scratchpad"
echo 'STOP unit=wt-old route=cap' > "$S/unit-loop-wt-old.done"; mkdir -p "$T/ws/wt-old"
printf 'exit=1\n' > "$S/scratchpad/wake-job-1-1.send.log"
tick 41000
[ "$(posts)" = 0 ] || fail "a driver file the plugin does not ship was posted as an item"

# A BLANK CODEX PANE WHOSE RESULT COULD NOT BE READ at the stall is not
# settled as silent on that one read: the review may be finished, and a
# settled seat is never read again. The read is tried each tick; only one
# still failing a whole stall later is posted as stopped.
settle
R=$T/home/.codex/sessions/2026/09/28/rollout-rf.jsonl
echo '{}' > "$R"; echo "session=$R" > "$F/state-wt-rf"
seat wt-rf term_rf task_rf 42000
state term_rf none; tick 42000
: > "$F/rvfail-term_rf"; tick 43400
[ "$(posts wt-rf)" = 0 ] || fail "a blank seat whose result could not be read was settled anyway: $(grep wt-rf "$T/sends" | tail -1)"
rm "$F/rvfail-term_rf"; echo 'VERDICT: GO' > "$F/verdict-term_rf"; tick 43460
grep 'wt-rf' "$T/sends" | tail -1 | grep -q 'finished' || fail "a blank seat whose first read failed was not posted as finished: $(grep wt-rf "$T/sends" | tail -1)"
settle
R=$T/home/.codex/sessions/2026/09/28/rollout-rg.jsonl
echo '{}' > "$R"; echo "session=$R" > "$F/state-wt-rg"
seat wt-rg term_rg task_rg 45000
state term_rg none; : > "$F/rvfail-term_rg"; tick 45000; tick 46400
[ "$(posts wt-rg)" = 0 ] || fail "a blank seat was settled on its first failed read"
tick 47700
grep 'wt-rg' "$T/sends" | tail -1 | grep -q 'stopped without reporting' || fail "a blank seat whose result never could be read was never posted: $(grep wt-rg "$T/sends" | tail -1)"

# A HEADS-UP FROM ANOTHER PROJECT IS NOT THIS WATCHER'S. The offer store is one
# for the machine, and every project runs a watcher: a note from a session in
# another project's checkout goes to that project's main, not to this one,
# whose run would get a stranger's text and a second task for it.
settle
W2=bbbb2222-0000-0000-0000-000000000002
transcript $W2 "$T/elsewhere/other-repo"
HU_BEFORE=$(hu)
offers $W2 48000123 "Another project's note." "private to the other project"
tick 48000; tick 48060
[ "$(hu)" = "$HU_BEFORE" ] || fail "a heads-up from another project's session was relayed to this project's main"
! grep -q 'private to the other project' "$T/sends" "$T/last-body" 2>/dev/null || fail "another project's explanation reached this project's run"
W3=cccc3333-0000-0000-0000-000000000003
transcript $W3 "$REPO"
offers $W2 48000123 "Another project's note." "private to the other project" $W3 48200123 "Main saw it too." "from this project's main"
tick 48200
[ "$(hu)" = $((HU_BEFORE + 1)) ] || fail "a heads-up from this project's main checkout was not relayed"

# A session no transcript ever names must not hold back this project's own
# note of the same text: main's note goes now, quoting main alone.
settle
W4=dddd4444-0000-0000-0000-000000000004 W5=eeee5555-0000-0000-0000-000000000005
transcript $W4 "$REPO"
HU_BEFORE=$(hu)
offers $W4 49000123 "A shared note." "from this project's main" $W5 49000456 "A shared note." "from a session nobody can place"
tick 49000; tick 49060
[ "$(hu)" = $((HU_BEFORE + 1)) ] || fail "a known local note waited on an unplaced session with the same text"
has "the shared note" "from this project's main"
! grep -q 'from a session nobody can place' "$T/last-body" || fail "an unplaced session's explanation was relayed"

# Builder signals. A tool call open past its limit gets one typed line. The
# event log stays in the worktree when a Builder crashes: a replacement pane
# must not be nudged, or main woken, for a call the dead pane never ended.
settle
B=70000
bseat wt-b1 term_b1 task_b1 $((B - 300)); state term_b1 working
bstart $((B - 200)) s1 > "$T/ws/wt-b1/.claude/builder-events.jsonl"
tick $B
[ "$(nudges term_b1)" = 1 ] || fail "a shell call 200 s open (limit 180) got $(nudges term_b1) nudges, not one: $(cat "$T/nudges")"
bseat wt-b2 term_b2new task_b2 $((B - 100)); state term_b2new working
{ bstart $((B - 5000)) dead1; bstart $((B - 50)) live1; } > "$T/ws/wt-b2/.claude/builder-events.jsonl"
tick $((B + 10))
[ "$(nudges term_b2new)" = 0 ] || fail "a replacement pane was nudged for the crashed Builder's open call: $(cat "$T/nudges")"
[ "$(posts 'Builder wt-b2 is')" = 0 ] || fail "main was woken for the crashed Builder's open call"
tick $((B + 200))
[ "$(nudges term_b2new)" = 1 ] || fail "the replacement pane's own open call (250 s) got $(nudges term_b2new) nudges, not one"

# A Builder ends its turn to wait on a helper it started, so its pane reads done
# (#41). The helper's rows are the real shape: a stop, a call of its own, then
# its finishing stop. Waiting is not stopping; the finish with no DONE still is.
settle
H=80000
hrow() { jq -nc --argjson t "$1" --arg e "$2" '{ts: ($t | todate), event: $e} + if $e == "tool-start"
  then {use: "h\($t)", agent: "a1", tool: "Grep", kind: "tool", call: "h"} else {agent_id: "a1", type: "Explore"} end'; }
for u in wt-h1 wt-h2 wt-h3; do bseat $u term_$u task_$u $((H - 2000)); state term_$u working; done
{ hrow $((H - 120)) subagent-start; hrow $((H - 90)) subagent-stop; hrow $((H - 30)) tool-start; } > "$T/ws/wt-h1/.claude/builder-events.jsonl"
# read-verdict.sh ends its output at a verdict line: a Builder quoting its pass's verdict reads like this.
printf 'Pass 1 is back.\nVERDICT: GO\n' > "$F/verdict-term_wt-h1"
# A helper with no row for longer than the stall limit has not run on: the stop is real.
hrow $((H - 1500)) subagent-start > "$T/ws/wt-h2/.claude/builder-events.jsonl"
# A Builder that printed DONE is done, a helper out or not.
hrow $((H - 120)) subagent-start > "$T/ws/wt-h3/.claude/builder-events.jsonl"; echo 'WT-H3-DONE' > "$F/verdict-term_wt-h3"
tick $H; for u in wt-h1 wt-h2 wt-h3; do state term_$u "done"; done; tick $((H + 60))
[ "$(posts wt-h1)" = 0 ] || fail "a Builder waiting on its helper was posted: $(grep wt-h1 "$T/sends")"
grep -q 'wt-h2 builder stopped without reporting' "$T/sends" || fail "a Builder whose helper went silent past the stall limit was not posted"
grep -q 'seat builder on wt-h3 finished' "$T/sends" || fail "a Builder that printed DONE with a helper out was not posted as finished"
tick $((H + 120)); [ "$(posts wt-h1)" = 0 ] || fail "a Builder still waiting on its helper was posted on a later tick"
hrow $((H + 130)) subagent-stop >> "$T/ws/wt-h1/.claude/builder-events.jsonl"; tick $((H + 180))
grep -q 'seat builder on wt-h1 finished' "$T/sends" || fail "a Builder whose helper finished was not posted on the next tick: $(cat "$T/sends")"
rm -f "$F/verdict-term_wt-h1"; settle
bseat wt-h4 term_wt-h4 task_wt-h4 $((H - 2000)); state term_wt-h4 working
{ hrow $((H + 200)) subagent-start; hrow $((H + 210)) tool-start; hrow $((H + 230)) subagent-stop; } > "$T/ws/wt-h4/.claude/builder-events.jsonl"
tick $((H + 240)); state term_wt-h4 "done"; tick $((H + 300))
grep -q 'wt-h4 builder stopped without reporting' "$T/sends" || fail "a Builder whose only helper had finished, with no DONE, was not posted"
# The log is the Builder's own to write. A row dated in the future is no sign of a helper at work, and
# however fresh its rows, a hold ends after HOLD_S (1 h) of this service's own clock.
settle; H=90000
for u in wt-h5 wt-h6 wt-h7 wt-h8 wt-h9; do bseat $u term_$u task_$u $((H - 2000)); state term_$u working; done
hrow 4070908800 subagent-start > "$T/ws/wt-h5/.claude/builder-events.jsonl"
hrow $((H - 10)) subagent-start > "$T/ws/wt-h6/.claude/builder-events.jsonl"
# wt-h8 quotes a pass's verdict and waits on a helper that stays busy: the expired hold is no finish.
hrow $((H - 10)) subagent-start > "$T/ws/wt-h8/.claude/builder-events.jsonl"; printf 'Pass 2 is back.\nVERDICT: GO\n' > "$F/verdict-term_wt-h8"
# wt-h9 printed DONE after a quoted verdict: read-verdict.sh's output ends at the verdict, the session's last line is DONE.
hrow $((H - 10)) subagent-start > "$T/ws/wt-h9/.claude/builder-events.jsonl"; echo 'VERDICT: GO' > "$F/verdict-term_wt-h9"; echo 'marker=1' > "$F/state-wt-h9"; echo 'tag=seat-builder-88000-9' >> "$S/seat-wt-h9-builder.txt"
# The helper's own rows are old; the end of its call (an end row names no agent) is recent.
{ hrow $((H - 1500)) subagent-start; hrow $((H - 1400)) tool-start; jq -nc --argjson t $((H - 30)) --arg u "h$((H - 1400))" '{ts: ($t | todate), event: "tool-end", use: $u, ok: true}'; } \
  > "$T/ws/wt-h7/.claude/builder-events.jsonl"
tick $H; for u in wt-h5 wt-h6 wt-h7 wt-h8 wt-h9; do state term_$u "done"; done; tick $((H + 60))
grep -q 'seat builder on wt-h9 finished' "$T/sends" || fail "a Builder whose last line is DONE after a quoted verdict was held: $(grep wt-h9 "$T/sends")"
# read-verdict-latest.test.sh runs the real reader with these arguments on a session with no task id.
grep -q -- '--worktree [^ ]*/wt-h9 --agent claude --launched 88000 --spec seat-builder-88000-9 --marker WT-H9-DONE$' "$F/state-reads" || fail "the DONE read is not the call read-verdict-latest.test.sh checks: $(grep wt-h9 "$F/state-reads")"
grep -q 'wt-h5 builder stopped without reporting' "$T/sends" || fail "a helper row dated in the future held a stopped Builder"
[ "$(posts wt-h6)" = 0 ] || fail "a Builder with a fresh helper was posted at once"
[ "$(posts wt-h7)" = 0 ] || fail "a Builder whose helper's call ended 30 s ago was posted: the end row was not read as the helper's"
for u in wt-h6 wt-h8; do hrow $((H + 3600)) tool-start >> "$T/ws/$u/.claude/builder-events.jsonl"; done; tick $((H + 3600))
[ "$(posts wt-h6)" = 0 ] || fail "a Builder held under an hour was posted"
for u in wt-h6 wt-h8; do hrow $((H + 3660)) tool-start >> "$T/ws/$u/.claude/builder-events.jsonl"; done; tick $((H + 3670))
grep -q 'wt-h6 builder stopped without reporting' "$T/sends" || fail "a Builder held past an hour by fresh helper rows was never posted"
grep -q 'wt-h8 builder stopped without reporting' "$T/sends" || fail "an expired hold on a Builder quoting a verdict was not posted as stopped: $(grep wt-h8 "$T/sends")"

echo "PASS main-watch.test.sh"
