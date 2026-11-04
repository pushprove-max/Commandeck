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
# Issue 620: a brief that named a step to run before the merge was merged by the gate before the step ran. Any line of
# the brief that names pre-merge holds the merge until the evidence file has `Pre-merge: done <n>`, n the cksum of the
# whole brief (a stamp: no section is read, so no heading shape can drop a step). Its own FAIL lines: break-run reads
# `FAIL <label> (`.
no() { echo "FAIL $1 ($2)" >&2; exit 1; }
L1="a brief with a Pre-merge section holds the merge until the evidence says Pre-merge: done"
L2="a brief that names no pre-merge step does not hold"
N=$((N + 1000)); unit pm; unit pe
printf '## Pre-merge\n- run the data migration on the staging copy\n\n## Scope\n- x\n' >> "$T/ws/pm/.claude/briefs/pm.md"
printf '## Scope\n- merge after the tests pass\n' >> "$T/ws/pe/.claude/briefs/pe.md"
P=$(tip pm) E=$(tip pe); tick $N; said_done pm; said_done pe; tick $((N + 60)); jobwait pe; tick $((N + 120))
grep -q "pm@" "$F/mq-calls" && no "$L1" "merged before its step: $(cat "$F/mq-calls")"
[ "$(posts 'seat builder on pm finished.*Pre-merge')" = 1 ] || no "$L1" "the hold was not posted with its reason"
grep -q "pe@$E" "$F/mq-calls" || no "$L2" "not merged: $(cat "$F/mq-calls")"
# Every brief starts from the template: a template line naming pre-merge would hold every unit's merge.
! grep -qiE 'pre[-_ ]?merge' "$(dirname "$0")/../../templates/_builder-brief-template.md" || no "$L2" "the brief template names pre-merge, so every unit would be held"
# The done line carries the cksum of the brief, which the hold names: a bare one releases nothing.
held() { (. "$(dirname "$0")/../paths.sh"; PP_MAIN=$T/none pp_merge_held "$1" "$2"); }
dl() { held "$1" "$2" | sed -n 's/.*`\(Pre-merge: done [0-9][0-9]*\)`.*/\1/p'; }
DL=$(dl pm "$T/ws/pm")
[ -n "$DL" ] || no "$L1" "the hold names no done line to write: $(held pm "$T/ws/pm")"
echo "Pre-merge: done" >> "$T/ws/pm/.claude/briefs/pm-evidence.md"
held pm "$T/ws/pm" > /dev/null || no "$L1" "a bare Pre-merge: done line released the steps"
echo "$DL" >> "$T/ws/pm/.claude/briefs/pm-evidence.md"; tick $((N + 180)); jobwait pm; tick $((N + 240))
grep -q "pm@$P" "$F/mq-calls" || no "$L1" "not merged once the evidence said $DL: $(cat "$F/mq-calls")"
# Every ordering the passes found, in order: a step under `###` (r1), a done line older than a step (r1), a heading not
# `## Pre-merge` (r1), an indented heading (r2), a step in bold only (r3), then the other shapes and a brief edited after
# the done line. Each holds with no done line; the line the hold names releases it.
B=$T/pn/.claude/briefs; mkdir -p "$B"
shape() { printf "$1" > "$B/pn.md"; : > "$B/pn-evidence.md"
  held pn "$T/pn" | grep -q 'Pre-merge: done [0-9]' || no "$L1" "$2 did not hold naming its done line: $(held pn "$T/pn")"
  dl pn "$T/pn" > "$B/pn-evidence.md"; held pn "$T/pn" > /dev/null && no "$L1" "$2: the done line the hold names did not release it"; true; }
shape '## Pre-merge\n\n### Staging\n- run migration\n\n## Scope\n- x\n' "a step under a ### subheading"
printf '## Pre-merge\n\n### Staging\n- run migration\n- rebuild the index\n\n## Scope\n- x\n' > "$B/pn.md"
held pn "$T/pn" > /dev/null || no "$L1" "a done line written before a step was added released the new step"
shape '# pn\n\n## Pre-merge steps\n- run migration\n' "a heading other than ## Pre-merge"
shape '  ## Pre-merge\n- run migration\n' "an indented heading"
shape '## Pre-merge\n**Run the staging migration before merging.**\n' "a step in bold only"
for s in '## Pre-merge ##\n- x\n' 'Pre-merge\n---\n- x\n' '**Pre-merge**\n- x\n' '```\n## Pre-merge\n```\n- x\n' \
  '<h2>Pre-merge</h2>\n- x\n' '> ## Pre merge\n- x\n' 'Run the PREMERGE check first.\n' '## Pre_merge\n- x\n'; do
  shape "$s" "the shape $(printf '%q' "$s")"; done
printf '## Pre-merge\n**Run the staging migration, then reindex.**\n' > "$B/pn.md"
held pn "$T/pn" > /dev/null || no "$L1" "a brief edited after its done line released the edit"
# The one retry path is the tick: each piece of kept gate state removed between two ticks leaves the unit held, and the
# first tick after the done line merges it.
N=$((N + 1000)); unit pk; printf '**Pre-merge:** run migration\n' >> "$T/ws/pk/.claude/briefs/pk.md"; K=$(tip pk)
tick $N; said_done pk; tick $((N + 60))
for k in "gate-pk" "merge-pk" "item-*pk*"; do
  rm -f "$S/main-watch/"$k; N=$((N + 60)); tick $N
  grep -q "pk@" "$F/mq-calls" && no "$L1" "removing $k between two ticks released the hold"; done
dl pk "$T/ws/pk" >> "$T/ws/pk/.claude/briefs/pk-evidence.md"; tick $((N + 60)); jobwait pk; tick $((N + 120))
grep -q "pk@$K" "$F/mq-calls" || no "$L1" "not merged at the tick after the done line: $(cat "$F/mq-calls")"
echo "ok   $L1"; echo "ok   $L2"; gone pm; gone pe; gone pk
echo "PASS main-watch-merge-gate.test.sh"
