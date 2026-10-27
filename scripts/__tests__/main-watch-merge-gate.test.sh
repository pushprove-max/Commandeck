#!/usr/bin/env bash
# Issues 254 and 258: every refusal of the merge gate other than the replay's (main-watch-auto-merge.test.sh), a held
# unit that runs no gate and lands once its hold is gone, a refusal posted once per tip, and (issue 307) two units
# that pass in one tick going as one merge train.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-merge-setup.sh"
N=5000; tick $N; N=20000; D=$S/main-watch/digest
# The other refusals: a narrowed GO and an open owner question. Held units
# (`Merge: hold`, the open question) never run the gate and are never nudged; a refusal is posted once per tip.
N=$((N + 1000)); : > "$T/sends"; : > "$T/typed"; : > "$F/verify-calls"
unit narrow; echo "a narrowed pass with no closing pass before it: its GO merges nothing" > "$F/refuse-narrow"
unit hold; echo 'Merge: hold' >> "$T/ws/hold/.claude/briefs/hold.md"
unit owner; echo '{"id":"owner-q1","askedAt":"1999-01-01T00:00:00Z","question":"which?","proposedDefault":"a","source":"owner asks","answeredAt":null,"answer":null}' \
  > "$REPO/.claude/metrics/decisions.jsonl"
tick $N; for u in narrow hold owner; do said_done $u; done; tick $((N + 60))
[ "$(posts 'seat builder on narrow finished.*its GO merges nothing')" = 1 ] || fail "a narrowed GO was not refused with its reason"
[ "$(posts 'seat builder on hold finished.*Merge: hold')" = 1 ] || fail "a held unit's finish was not posted to main with the hold"
[ "$(posts 'seat builder on owner finished.*open owner decision')" = 1 ] || fail "a unit with an open owner question was not posted with it"
grep -qx 'hold\|owner' "$F/verify-calls" && fail "a held unit ran the gate"
for t in 120 180 240 400 700; do tick $((N + t)); done
[ "$(posts 'seat builder on narrow')" = 1 ] || fail "a refusal was posted again for the same tip ($(posts 'seat builder on narrow') posts)"
[ "$(grep -cx narrow "$F/verify-calls")" = 1 ] || fail "--verify ran again on a tip it already answered ($(grep -cx narrow "$F/verify-calls") runs)"
grep -q 'terminal term_hold\|terminal term_owner' "$T/typed" && fail "a held unit was nudged: $(cat "$T/typed")"
[ -s "$F/mq-calls" ] && grep -q 'narrow@\|hold@\|owner@' "$F/mq-calls" && fail "a refused or held unit was merged"

# Issue 258: the held unit left waiting is gated at the next tick once its hold is gone, and lands.
T0=$(tip hold); sed -i '/Merge: hold/d' "$T/ws/hold/.claude/briefs/hold.md"; tick $((N + 760)); jobwait hold; tick $((N + 820))
grep -qx "hold@$T0" "$F/mq-calls" || fail "a unit left waiting to merge was not gated and merged once its hold was gone"
grep -q 'hold merged' "$D" || fail "the waiting unit's merge has no digest line"
for u in narrow hold owner; do gone $u; done

# A kept refusal stands for its tip and round files: a new pass on the same commit (a new round file, nothing
# committed) runs --verify again, and the unit merges. The new round file is a report main has not read yet (issue 353):
# a tick stamps it, the next posts it, the third gates.
N=$((N + 1000)); unit stale; echo "no closing pass" > "$F/refuse-stale"; tick $N; said_done stale; tick $((N + 60))
rm "$F/refuse-stale"; echo "VERDICT: GO" > "$T/ws/stale/.claude/briefs/stale-r2-reports.md"; T0=$(tip stale); tick $((N + 120)); tick $((N + 180)); tick $((N + 240)); jobwait stale
grep -qx "stale@$T0" "$F/mq-calls" || fail "a new closing pass on an unchanged tip did not clear the kept refusal: $(cat "$F/mq-calls")"
# How a merge ended reaches main with the worktree gone: the stub removes it as the real merge does.
N=$((N + 1000)); unit late; echo late > "$F/mq-late"; tick $N; said_done late; tick $((N + 60)); jobwait late; tick $((N + 120))
[ ! -d "$T/ws/late" ] || fail "the stub merge did not remove the worktree"
[ "$(posts 'merge of late did not land cleanly')" = 1 ] || fail "a merge that landed with a failed post-merge step did not reach main once its worktree was gone"
: > "$F/mq-late"; gone late
# A unit named like a job file (u.rc) is a unit: how its merge ended reaches main too.
N=$((N + 1000)); unit lt.rc; echo lt.rc > "$F/mq-late"; tick $N; said_done lt.rc; tick $((N + 60)); jobwait lt.rc; tick $((N + 120))
[ "$(posts 'merge of lt.rc did not land cleanly')" = 1 ] || fail "a unit named lt.rc had its merge result skipped"
: > "$F/mq-late"; gone lt.rc; rm -f "$S/main-watch/merge-lt.rc"
# A merge job that died before it wrote its exit is told to main, never waited on for good; a running one is not.
N=$((N + 1000)); unit orph; tick $N; bash -c 'echo $$' > "$S/main-watch/mergejob-dead.pid"
printf '%s\n%s\n' "$(tip orph)" "$S/main-watch/mergejob-dead.log" > "$S/main-watch/merge-orph"; said_done orph; tick $((N + 60))
[ "$(posts 'merge job for orph ended with no exit')" = 1 ] || fail "a merge job that died with no exit file was not posted to main"
grep -q 'orph@' "$F/mq-calls" && fail "a unit whose merge job died was merged again"
sleep 300 & echo $! > "$S/main-watch/mergejob-live.pid"; LIVE=$!
unit slow; printf '%s\n%s\n' "$(tip slow)" "$S/main-watch/mergejob-live.log" > "$S/main-watch/merge-slow"; said_done slow; tick $((N + 120)); kill "$LIVE"
[ "$(posts 'merge job for slow')" = 0 ] || fail "a merge job still running was posted as dead"
# A merge job whose wrapper died while its merge runs is not told as ended: .pid names a group, and the merge lives in it.
N=$((N + 1000)); unit wrap; set -m; bash -c 'sleep 300 & wait' & G=$!; set +m; sleep 0.3; kill -KILL "$G"; wait "$G" 2>/dev/null || true
echo "$G" > "$S/main-watch/mergejob-wrap.pid"; printf '%s\n%s\n' "$(tip wrap)" "$S/main-watch/mergejob-wrap.log" > "$S/main-watch/merge-wrap"
said_done wrap; tick $((N + 60)); tick $((N + 120)); kill -- -"$G" 2>/dev/null || true
[ "$(posts 'merge job for wrap')" = 0 ] || fail "a merge job whose wrapper died while its merge ran was posted as ended"
for u in orph slow stale wrap; do gone $u; rm -f "$S/main-watch/merge-$u"; done
# An earlier build's job files (merge-<epoch>.log, .rc, .pid) are no unit's record: nothing is posted for them.
N=$((N + 1000)); echo 0 > "$S/main-watch/merge-123.rc"; echo 1 > "$S/main-watch/merge-123.pid"; echo "merge-queue: x merged; ok" > "$S/main-watch/merge-123.log"; tick $N
[ "$(posts '123\.')" = 0 ] || fail "an earlier build's merge job file was read as a unit's merge record"

# Issue 307: two units that pass the gate in one tick go as one merge train.
N=$((N + 2000)); unit ta; unit tb; A=$(tip ta) B=$(tip tb); tick $N; said_done ta; said_done tb; tick $((N + 60)); jobwait ta
grep -qx -- "--train ta@$A tb@$B\|--train tb@$B ta@$A" "$F/mq-calls" || fail "two units passing in one tick were not one train: $(cat "$F/mq-calls")"
# A unit name is matched as written, not as a pattern: axb landing does not read as a.b landing.
N=$((N + 1000)); unit axb; unit a.b; echo a.b > "$F/mq-late"; tick $N; said_done axb; said_done a.b; tick $((N + 60)); jobwait a.b; tick $((N + 120))
[ "$(posts 'merge of a\.b did not land cleanly')" = 1 ] || fail "a.b's failed post-merge step was hidden by axb's success line"
: > "$F/mq-late"
# Issue 317: a merge of the unit at this tip that someone started by hand, running, is that merge: the gate queues none
# beside it. Its pid dead, the lock is stale and the unit merges as any other.
N=$((N + 1000)); unit hnd; H=$(tip hnd); sleep 300 & HP=$!
printf 'unit=hnd\nsha=%s\ntip=%s\npid=%s\nstarted=1\nstage=check\nmain=%s\nlog=x\n' "$H" "$H" "$HP" "$REPO" > "$REPO/.git/merge-unit-local.state"
tick $N; said_done hnd; tick $((N + 60))
grep -q "hnd@" "$F/mq-calls" && fail "a unit another merge is running was queued a second time: $(cat "$F/mq-calls")"
kill "$HP"; wait "$HP" 2>/dev/null || true; tick $((N + 120)); jobwait hnd
grep -qx "hnd@$H" "$F/mq-calls" || fail "a stale lock (its pid dead) kept the unit from merging: $(cat "$F/mq-calls")"
rm -f "$REPO/.git/merge-unit-local.state"; gone hnd
echo "PASS main-watch-merge-gate.test.sh"
