#!/usr/bin/env bash
# Issue 353: a finished Builder used to reach main as "stopped without reporting" while its pass reports sat unread.
# main-watch.sh now stamps every finished round file (due-<key>), posts each report from its stamp alone, and fences the
# unit: nothing finishes or merges a Builder while one of its reports has not reached main (issue 352: a DONE after a
# narrowed GO is named as one). Pinned: every completed report wakes main once whichever order they land in; a send
# that fails, with the worktree then gone, is posted from the stamp at the next tick, in round order; a finished
# Builder with an undelivered report is neither posted finished nor merged; a DONE after a narrowed GO says it needs
# a final pass; a tick with nothing new posts nothing.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-merge-setup.sh"
N=5000; tick $N; I=$S/main-watch
rnd() { # <unit> <round> <kind> <verdict> -- one finished round file
  printf '## Sol\nReviewed: x\nPass: %s\nTiming: a b\n\nVERDICT: %s\n' "$3" "$4" > "$T/ws/$1/.claude/briefs/$1-r$2-reports.md"; }
sent() { wc -l < "$T/sends" | tr -d ' '; }
more() { N=$((N + 100)); tick $N; }

# Every completed report wakes main once, whichever order they land in: r2 first, then r1, then a run of quiet ticks.
unit ro; rnd ro 2 review NO-GO
more; rnd ro 1 adversarial GO
for t in 1 2 3 4; do more; done
[ "$(posts 'main-watch: ro pass 1: GO (adversarial)')" = 1 ] || fail "r1 was not posted exactly once ($(posts 'main-watch: ro pass 1: GO (adversarial)') posts)"
[ "$(posts 'main-watch: ro pass 2: NO-GO (review)')" = 1 ] || fail "r2 was not posted exactly once ($(posts 'main-watch: ro pass 2: NO-GO (review)') posts)"
[ "$(posts 'fix round 2 runs from ro-fix-r2.md')" = 1 ] || fail "a NO-GO report did not name its fix round"
# A second tick posts nothing: no record of what was seen is needed, the delivered items are the record.
BEFORE=$(sent); more
[ "$(sent)" = "$BEFORE" ] || fail "a tick with every report delivered posted again ($BEFORE -> $(sent))"
ls "$I"/due-report-ro-* >/dev/null 2>&1 && fail "a delivered report kept its stamp"
# older_report_stamped_superseded: r1 finished after r2, so its next step is r2's to give.
[ "$(posts 'superseded by pass 2; act on that report')" = 1 ] || fail "older_report_stamped_superseded: r1 was not stamped superseded by pass 2 ($(posts 'superseded by pass 2') posts)"
gone ro

# r1's send fails, the worktree is removed, the next tick posts r1 from its stamp. While r1 is undelivered the unit's
# DONE is neither posted as a finish nor merged.
unit rb; rnd rb 1 final GO; said_done rb; touch "$F/refuse-sends"
more; more
[ "$(posts 'seat builder on rb finished')" = 0 ] || fail "a finished Builder with an undelivered report was posted finished"
grep -q 'rb@' "$F/mq-calls" && fail "a Builder with an undelivered report was merged"
ls "$I"/due-report-rb-r1-* >/dev/null 2>&1 || fail "the failed send left no stamp to retry from"
gone rb; rm -f "$F/refuse-sends"
: > "$T/sends"
for t in 1 2 3; do more; done
[ "$(posts 'main-watch: rb pass 1: GO (final)')" = 1 ] || fail "r1 was not posted once from its stamp after the worktree was gone ($(posts 'main-watch: rb pass 1: GO (final)') posts)"
ls "$I"/due-report-rb-* >/dev/null 2>&1 && fail "a delivered report kept its stamp"
BEFORE=$(sent); more
[ "$(sent)" = "$BEFORE" ] || fail "a further tick posted again after r1 was delivered"

# A DONE after a narrowed GO is posted as finished on a narrowed pass, needing a final pass: the report went first.
: > "$T/sends"
unit rn; rnd rn 1 review GO; echo "narrowed: its GO merges nothing" > "$F/refuse-rn"; said_done rn
for t in 1 2 3; do more; done
[ "$(posts 'Finished on a narrowed pass; needs a final pass: builder-codex-pass.sh rn 2 final')" = 1 ] \
  || fail "a DONE after a narrowed GO was not posted as needing a final pass ($(posts 'Finished on a narrowed pass') posts)"
[ "$(posts 'main-watch: rn pass 1: GO (review)')" = 1 ] || fail "the narrowed report itself was not posted once"
[ "$(posts 'Newest report: rn-r1-reports.md: GO (review)')" = 1 ] || fail "the refusal did not lead with the newest report"
grep -q 'rn@' "$F/mq-calls" && fail "a narrowed GO was merged"
gone rn

# Host change (owner order 2026-10-25): a design GO is not a narrowed GO. "a design GO's report names writing the code and the next
# final pass, not a merge"; "a DONE after a design GO is posted as finished on a design-only pass, not as narrowed, and is
# not merged".
: > "$T/sends"
unit rd; rnd rd 1 design GO; echo "rd-r1-reports.md is a design-only pass (its commit changed only the plan): its GO merges nothing" > "$F/refuse-rd"; said_done rd
for t in 1 2 3; do more; done
[ "$(posts 'design only, merges nothing -- the Builder writes the code, then builder-codex-pass.sh rd 2 final')" = 1 ] \
  || fail "a design GO's report did not name writing the code and the next final pass ($(posts 'design only, merges nothing') posts)"
[ "$(posts 'main-watch: rd pass 1: GO (design)')" = 1 ] || fail "the design report itself was not posted once"
[ "$(posts 'Finished on a design-only pass; the code is not reviewed yet: builder-codex-pass.sh rd 2 final')" = 1 ] \
  || fail "a DONE after a design GO was not posted as finished on a design-only pass ($(posts 'Finished on a design-only pass') posts)"
[ "$(posts 'Finished on a narrowed pass')" = 0 ] || fail "a DONE after a design GO was posted as narrowed"
grep -q 'rd@' "$F/mq-calls" && fail "a design GO was merged"
gone rd

# stop_check_unreadable_holds_report: a stop check whose answer names no round stamps nothing and is noted once; the tick
# after a readable answer stamps the report.
: > "$T/sends"
unit su; rnd su 1 review NO-GO; echo "no round named here" > "$F/refuse-su"
more; more
[ "$(posts 'main-watch: su pass 1')" = 0 ] || fail "stop_check_unreadable_holds_report: a report was posted from a check that named no round"
ls "$I"/due-report-su-* >/dev/null 2>&1 && fail "stop_check_unreadable_holds_report: an unreadable check left a stamp"
[ "$(grep -c '^report-su-r1-' "$I/diag")" = 1 ] || fail "stop_check_unreadable_holds_report: the held report was not noted exactly once (its key in the diag record)"
rm -f "$F/refuse-su"; more
[ "$(posts 'fix round 1 runs from su-fix-r1.md')" = 1 ] || fail "stop_check_unreadable_holds_report: the next tick did not stamp the report from a readable check"
gone su

# newer_round_during_verify_not_stamped: r3 lands while the check of r2 runs. No stamp this tick; the next tick stamps r2
# superseded by pass 3 and r3 from its own check.
: > "$T/sends"
unit nr; rnd nr 2 review NO-GO
printf '## Sol\nReviewed: x\nPass: review\nTiming: a b\n\nVERDICT: NO-GO\n' > "$F/mkround-nr"
more
[ "$(posts 'main-watch: nr pass 2')" = 0 ] || fail "newer_round_during_verify_not_stamped: r2 was stamped on a check that r3 overtook"
more
[ "$(posts 'superseded by pass 3; act on that report')" = 1 ] || fail "newer_round_during_verify_not_stamped: r2 was not stamped superseded by pass 3 on the next tick"
more
[ "$(posts 'fix round 3 runs from nr-fix-r3.md')" = 1 ] || fail "newer_round_during_verify_not_stamped: r3 was not stamped from its own check"
gone nr

# adversarial_go_review_stop_wins: a first-pass GO whose check says REVIEW STOP is stamped with the stop.
: > "$T/sends"
unit ag; rnd ag 1 adversarial GO
echo "REFUSED: REVIEW STOP: ag-r1-reports.md holds a P0 or P1 two passes past the cap (pass 7 on record); decision review-stop-ag-r1; it waits for the owner's answer, no fix round runs" > "$F/refuse-ag"
more; more
[ "$(posts 'REVIEW STOP, decision review-stop-ag-r1')" = 1 ] || fail "adversarial_go_review_stop_wins: the first-pass GO was not stamped with the REVIEW STOP"
[ "$(posts 'Next: a first-pass GO')" = 0 ] || fail "adversarial_go_review_stop_wins: the first-pass GO was stamped as a plain GO"
gone ag

# stamped_round_overtaken_before_send: r2 is stamped "fix round 2" and its send fails; r3 finishes before the next
# send. The stale next step is never sent: r2 goes out superseded by pass 3, then r3 with its own fix round.
: > "$T/sends"
unit so; rnd so 2 review NO-GO; touch "$F/refuse-sends"
more
grep -q 'fix round 2 runs from so-fix-r2.md' "$I"/due-report-so-r2-* || fail "stamped_round_overtaken_before_send: r2 was not stamped with its fix round before r3 landed"
rnd so 3 review NO-GO; rm -f "$F/refuse-sends"; : > "$T/sends"
for t in 1 2 3; do more; done
[ "$(posts 'fix round 2 runs from so-fix-r2.md')" = 0 ] || fail "stamped_round_overtaken_before_send: r2's stale fix-round step was sent after r3 finished"
[ "$(posts 'main-watch: so pass 2')" = 1 ] && [ "$(posts 'superseded by pass 3; act on that report')" = 1 ] \
  || fail "stamped_round_overtaken_before_send: r2 was not sent once, superseded by pass 3"
[ "$(posts 'fix round 3 runs from so-fix-r3.md')" = 1 ] || fail "stamped_round_overtaken_before_send: r3 was not sent with its own fix round"
gone so

echo "PASS main-watch-report-wake.test.sh"
