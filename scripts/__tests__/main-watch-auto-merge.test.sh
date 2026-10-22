#!/usr/bin/env bash
# Issue 254: a unit whose Builder said DONE and that passes the merge gate (a closing or first-pass GO on that exact
# tip, a clean tree, no `Merge: hold`, no open owner decision) merges itself into local main through merge-queue.sh,
# and main hears of it only in the digest. Issue 253: routine items (a landed merge, a repeated heads-up) go to the
# digest, and judgement (a refusal with its reason, a failed merge, a question) still wakes main. The other refusals,
# issue 258's waiting unit and the merge train are main-watch-merge-gate.test.sh.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-merge-setup.sh"
N=5000; tick $N

# Issue 253's replay: 12 items, 7 routine (5 merges that land, 2 repeats of a heads-up), one item a tick so no
# batching hides a wake. The 5 judgement items (a heads-up, a NO-GO, a red gate, a failed merge, a question) wake.
N=10000
# Staggered: each tick reads the last unit's merge and gates the next one's DONE.
# Each tip is read before its merge: the stub removes the worktree, as the real merge does.
declare -A TIPS; for u in cu1 cu2 cu3 cu4 cu5; do unit $u; TIPS[$u]=$(tip $u); done; tick $N
for u in cu1 cu2 cu3 cu4 cu5; do N=$((N + 60)); said_done $u; tick $N; jobwait $u; done; N=$((N + 60)); tick $N
for u in cu1 cu2 cu3 cu4 cu5; do
  grep -qx "$u@${TIPS[$u]}" "$F/mq-calls" || fail "a converged unit $u was not merged by sha through merge-queue.sh: $(cat "$F/mq-calls")"
  grep -q "$u" "$T/sends" && fail "a merge that landed sent main a message: $(grep "$u" "$T/sends")"
  grep -q "$u merged" "$D" || fail "a merge that landed has no digest line for $u"
  gone $u
done; N=$((N + 1000))
[ "$(grep -c . "$D")" = 5 ] || fail "five landed merges are not five digest lines: $(cat "$D")"
offer h1 $N "LINE-repeat"; tick $N; N=$((N + 600)); offer h2 $N "LINE-repeat"; tick $N; N=$((N + 600)); offer h3 $N "LINE-repeat"; tick $N
[ "$(posts LINE-repeat)" = 1 ] || fail "a heads-up repeating one already posted was sent again ($(posts LINE-repeat) sends)"
[ "$(grep -c "LINE-repeat" "$D")" = 2 ] || fail "the two repeated heads-ups are not in the digest"
N=$((N + 1000)); unit nogo; echo "the last pass ended NO-GO" > "$F/refuse-nogo"; tick $N; said_done nogo; tick $((N + 60))
N=$((N + 1000)); unit dirty; touch "$T/ws/dirty/stray.txt"; tick $N; said_done dirty; tick $((N + 60))
N=$((N + 1000)); unit failed; echo failed > "$F/mq-fail"; tick $N; said_done failed; tick $((N + 60)); jobwait failed; tick $((N + 120))
N=$((N + 1000)); rm -f "$S/main-watch/wake"; M0=$(mails)
jq -nc '{ok: true, result: {messages: [{to_handle: "run:run_test", from_handle: "term_q", read: 0, type: "question", subject: "a Builder asks"}]}}' > "$F/inbox"
tick $N; tick $((N + 180)); rm -f "$F/inbox"
[ "$(posts 'seat builder on nogo finished.*the last pass ended NO-GO')" = 1 ] || fail "a NO-GO unit was not posted with its reason"
[ "$(posts 'seat builder on dirty finished.*uncommitted')" = 1 ] || fail "a dirty tree was not posted with its reason"
[ "$(posts 'merge of failed did not land')" = 1 ] || fail "a failed merge was not posted to main with its log"
grep -qF "$S/main-watch/mergejob-" "$T/sends" || fail "the failed merge's post does not name its log"
[ "$(mails)" -gt "$M0" ] || fail "a Builder's question left unread did not wake main"
grep -q 'nogo@\|dirty@' "$F/mq-calls" && fail "a refused unit was merged: $(cat "$F/mq-calls")"
# Each post to an idle main and the unread question each type one wake; a heads-up note is inbox only.
[ "$(mails)" -le 6 ] || fail "12 items, 7 of them routine, made $(mails) wakes"
for u in nogo dirty failed; do gone $u; done

# A merge job runs inside the watcher's job, and a unit's `## Post-merge` line `main-watch.sh --install` restarts
# that job: the restart waits, as a job of its own, until no merge job lives, and the job settings stop the watcher's
# own process only. A restart that was lost is retried every tick from the job file alone, whatever state is gone.
# Old-install migration is out of scope by ruling (r-20261021-170113-1-f7afec): no old-format job file here.
printf '#!/bin/sh\necho "$*" >> "%s/lc"; case $1 in print) exit 1 ;; esac\n' "$F" > "$T/bin/launchctl"
printf '#!/bin/sh\necho "$*" >> "%s/sd"; [ "$2" != is-active ] || { echo inactive; exit 3; }\n' "$F" > "$T/bin/systemctl"
printf '#!/bin/sh\necho "$*" >> "%s/runs"\n' "$F" > "$T/bin/systemd-run"
chmod +x "$T/bin/launchctl" "$T/bin/systemctl" "$T/bin/systemd-run"
J=$S/main-watch/mergejob-1
restarted() { grep -qE -- '^--user restart |^bootstrap gui/[0-9]+ .*/LaunchAgents/' "$F/sd" "$F/lc"; }
helpers() { cat "$F/runs" "$F/lc" | grep -cE -- '--restart$|-restart\.plist$' || true; }
for os in Linux Darwin; do
  export COMMANDECK_HOST_OS=$os; : > "$F/sd"; : > "$F/runs"; : > "$F/lc"; rm -f "$S/main-watch/job-sum"
  sleep 60 & M=$!; echo "$M" > "$J.pid"
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
  kill "$M" 2>/dev/null || true; N=$((N + 60)); tick $N
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
  rm -f "$J".* "$j"
done
export COMMANDECK_HOST_OS=Linux

echo "PASS main-watch-auto-merge.test.sh"
