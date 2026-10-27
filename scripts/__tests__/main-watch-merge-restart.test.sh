#!/usr/bin/env bash
# A merge job runs inside the watcher's job, and a unit's `## Post-merge` line `main-watch.sh --install` restarts
# that job: the restart waits, as a job of its own, until no merge job lives, and the job settings stop the watcher's
# own process only. A restart that was lost is retried every tick from the job file alone, whatever state is gone.
# An old-format job file is not retried: a watcher installed before this code is reinstalled by hand once (last below).
# Split from main-watch-auto-merge.test.sh, which ran past the runner's cap under load.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-merge-setup.sh"
# The watcher posts only what finished after its first tick.
N=5000; tick $N
printf '#!/bin/sh\necho "$*" >> "%s/lc"; case $1 in print) exit 1 ;; esac\n' "$F" > "$T/bin/launchctl"
printf '#!/bin/sh\necho "$*" >> "%s/sd"; [ "$2" != is-active ] || { echo inactive; exit 3; }\n' "$F" > "$T/bin/systemctl"
printf '#!/bin/sh\necho "$*" >> "%s/runs"\n' "$F" > "$T/bin/systemd-run"
chmod +x "$T/bin/launchctl" "$T/bin/systemctl" "$T/bin/systemd-run"
J=$S/main-watch/mergejob-1
restarted() { grep -qE -- '^--user restart |^bootstrap gui/[0-9]+ .*/LaunchAgents/' "$F/sd" "$F/lc"; }
helpers() { cat "$F/runs" "$F/lc" | grep -cE -- '--restart$|-restart\.plist$' || true; }
for os in Linux Darwin; do
  export COMMANDECK_HOST_OS=$os; : > "$F/sd"; : > "$F/runs"; : > "$F/lc"; rm -f "$S/main-watch/job-sum"
  # The merge job's wrapper is dead and its merge lives in the group the pid names: the job lives.
  set -m; bash -c 'sleep 60 & wait' & M=$!; set +m; sleep 0.3; kill -KILL "$M"; wait "$M" 2>/dev/null || true; echo "$M" > "$J.pid"
  out=$(mw --install 2>&1) || fail "the $os install failed: $out"
  j=$(mw --job-file)
  grep -qE '^KillMode=process$|<key>AbandonProcessGroup</key><true/>' "$j" || fail "a restart of the $os job kills the merge it started: $(cat "$j")"
  restarted && fail "the $os install restarted the watcher while the merge job that ran it lives: $(cat "$F/sd" "$F/lc")"
  [ "$(helpers)" = 1 ] || fail "the $os install did not hand the restart to a job of its own: $(cat "$F/runs" "$F/lc")"
  N=$((N + 60)); tick $N; [ "$(helpers)" = 1 ] || fail "a $os tick started a restart while a merge job lives"
  mw --restart & H=$!; sleep 1.5
  restarted && fail "the $os restart job did not wait for the merge job"
  echo 0 > "$J.rc"; wait "$H" || fail "the $os restart job failed"
  restarted || fail "the $os restart job did not restart the watcher once the merge job ended: $(cat "$F/sd" "$F/lc")"
  kill -- -"$M" 2>/dev/null || true; N=$((N + 60)); tick $N
  [ "$(helpers)" = 1 ] || fail "a $os tick restarted a watcher already loaded from its job file"
  # A lost restart (the job file is not the one last loaded), then each piece of state removed between two ticks.
  for piece in job-sum merge-job restart-job; do
    echo lost > "$S/main-watch/job-sum"; h=$(helpers); N=$((N + 60)); tick $N
    [ "$(helpers)" = $((h + 1)) ] || fail "a $os lost restart was not retried at the next tick"
    case $piece in
      job-sum) rm -f "$S/main-watch/job-sum" ;;
      merge-job) rm -f "$J".* ;;
      restart-job) rm -f "$S"/scratchpad/*-restart.plist "$S"/scratchpad/*-restart.launchd.log ;;
    esac
    N=$((N + 60)); tick $N
    [ "$(helpers)" = $((h + 2)) ] || fail "a $os lost restart was not retried after its $piece was removed"
  done
  # The old-install migration the retry leaves out: a job file from before this code (a restart kills the merge job)
  # is rewritten by one --install by hand, which restarts the watcher at once when no merge job lives.
  if [ $os = Linux ]; then printf '[Service]\nKillMode=control-group\n' > "$j"; else printf '<plist><dict></dict></plist>\n' > "$j"; fi
  : > "$F/sd"; : > "$F/lc"
  out=$(mw --install 2>&1) || fail "the $os reinstall over an old-format job file failed: $out"
  { grep -qE '^KillMode=process$|<key>AbandonProcessGroup</key><true/>' "$j" && ! grep -q control-group "$j"; } \
    || fail "the $os reinstall left the old-format job file: $(cat "$j")"
  restarted || fail "the $os reinstall did not restart the watcher from the rewritten job file: $(cat "$F/sd" "$F/lc")"
  rm -f "$J".* "$j"
done

echo "PASS main-watch-merge-restart.test.sh"
