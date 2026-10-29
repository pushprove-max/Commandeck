#!/usr/bin/env bash
# Issue 254: a unit whose Builder said DONE and that passes the merge gate (a closing or first-pass GO on that exact
# tip, a clean tree, no `Merge: hold`, no open owner decision) merges itself into local main through merge-queue.sh.
# Issue 318 overrules issue 253 for a landed merge: main is told once (a landed merge is actionable), and the digest
# keeps its line. A repeated heads-up stays digest only, and a heads-up goes out as a status note, never a wake;
# judgement (a refusal with its reason, a failed merge, a question) still wakes main. The other refusals,
# issue 258's waiting unit and the merge train are main-watch-merge-gate.test.sh; the watcher's restart around a merge
# job is main-watch-merge-restart.test.sh.
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
  [ "$(posts "main-watch: $u merged into local main at ${TIPS[$u]:0:8}")" = 1 ] || fail "a merge that landed did not send main exactly one merged message: $(grep "$u" "$T/sends")"
  grep -q "$u merged" "$D" || fail "a merge that landed has no digest line for $u"
  gone $u
done; N=$((N + 1000))
[ "$(grep -c . "$D")" = 5 ] || fail "five landed merges are not five digest lines: $(cat "$D")"
offer h1 $N "LINE-repeat"; tick $N; N=$((N + 600)); offer h2 $N "LINE-repeat"; tick $N; N=$((N + 600)); offer h3 $N "LINE-repeat"; tick $N
[ "$(posts LINE-repeat)" = 1 ] || fail "a heads-up repeating one already posted was sent again ($(posts LINE-repeat) sends)"
[ "$(grep LINE-repeat "$T/sends" | grep -c -- '--type status')" = 1 ] || fail "a heads-up relay did not go out as a status note: $(grep LINE-repeat "$T/sends")"
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
# Each post to an idle main (the five landed merges among them) and the unread question each type one wake; a
# heads-up note is inbox only.
[ "$(mails)" -le 11 ] || fail "12 items, 2 of them routine, made $(mails) wakes"
for u in nogo dirty failed; do gone $u; done

# Issue 443: the unit driver's last step is the Builder launch, and from there the unit converges with no main turn. The
# launch mark (drive-<unit>.launched, written by builder-launch.sh under the driver) tells main-watch to settle the
# Builder's routine round reports unsent; the hand-launched unit below, with the same reports, still posts each one.
rounds() { # <unit> <pass> <verdict> <n> -- one finished round file
  printf 'Pass: %s\nVERDICT: %s\n' "$2" "$3" > "$T/ws/$1/.claude/briefs/$1-r$4-reports.md"
}
sent() { grep -c . "$T/sends" || true; }
N=$((N + 1000))
unit hand; rounds hand review NO-GO 1; rounds hand final GO 2; tick $N; tick $((N + 60))
[ "$(posts 'main-watch: hand pass 1: NO-GO (review)')" = 1 ] || fail "a hand-launched Builder lost its per-pass post: $(cat "$T/sends")"
N=$((N + 1000)); unit drv; date +%s > "$S/drive-drv.launched"; rounds drv review NO-GO 1; tick $N
rounds drv final GO 2; tick $((N + 60)); S1=$(sent); said_done drv; tick $((N + 120)); jobwait drv; tick $((N + 180))
L="a driven unit's Builder that ends on a closing GO is merged with no message to main (issue 443)"
[ "$(posts 'main-watch: drv pass')" = 0 ] || fail "$L: a routine round report was posted: $(grep 'drv pass' "$T/sends")"
[ "$(posts 'main-watch: drv merged into local main')" = 1 ] || fail "$L: the landing was not posted once: $(cat "$T/sends")"
[ "$(sent)" = "$((S1 + 1))" ] || fail "$L: main got more than the landing after the closing GO: $(tail -n +$((S1 + 1)) "$T/sends")"
gone drv; gone hand
echo "ok   $L"

N=$((N + 1000)); unit drv2; date +%s > "$S/drive-drv2.launched"; echo "first-pass GO" > "$F/rule-drv2"; rounds drv2 adversarial GO 1
tick $N; said_done drv2; tick $((N + 60)); jobwait drv2; tick $((N + 120))
L="a driven first-pass GO with no stop posts nothing and merges (issue 443)"
[ "$(posts 'main-watch: drv2 pass 1')" = 0 ] || fail "$L: the first-pass GO was posted: $(grep 'drv2 pass' "$T/sends")"
grep -q '^drv2@' "$F/mq-calls" || fail "$L: the unit was not merged: $(cat "$F/mq-calls")"
gone drv2
echo "ok   $L"

# A live driver owns its unit's seats: a finished seat posts nothing until the driver is gone, then posts as before.
printf '#!/usr/bin/env bash\ncase "$*" in *list-units*) cat "%s/units" 2>/dev/null ;; esac\nexit 0\n' "$F" > "$T/bin/systemctl"; chmod +x "$T/bin/systemctl"
N=$((N + 1000)); unit dlv; echo "the last pass ended NO-GO" > "$F/refuse-dlv"; said_done dlv
echo 'drive-dlv-1790000100.service loaded active running x' > "$F/units"; tick $N; tick $((N + 60))
L="main-watch posts no seat finish for a unit a live driver owns (issue 443)"
[ "$(posts 'seat builder on dlv finished')" = 0 ] || fail "$L: posted while the driver was listed: $(cat "$T/sends")"
rm -f "$F/units"; tick $((N + 120))
[ "$(posts 'seat builder on dlv finished')" = 1 ] || fail "$L: the finish was lost once the driver ended: $(cat "$T/sends")"
gone dlv
echo "ok   $L"

echo "PASS main-watch-auto-merge.test.sh"
