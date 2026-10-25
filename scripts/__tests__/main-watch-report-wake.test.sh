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

echo "PASS main-watch-report-wake.test.sh"
