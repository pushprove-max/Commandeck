#!/usr/bin/env bash
# At 00:02 on 2026-10-12 main-watch posted 226 old notes again. macOS
# removes a temp file nobody has read for three days (tmp_cleaner, at midnight),
# the handled receipts lived only in the temp state folder, and the notes
# themselves are archived under ~/.claude for good. A note whose receipt was
# removed looked new. Handled must outlive the temp folder; a note main never
# got must still arrive.
set -euo pipefail
MAIN_WATCH_TEST_HALF=setup source "$(dirname "$0")/main-watch.test.sh"

A=face0000-0000-0000-0000-0000000000a1 B=face0000-0000-0000-0000-0000000000b2
transcript "$A" "$T/ws/wt-handled-note"
: > "$T/sends"

offers "$A" 80000000 "Old claim." "Handled explanation"
tick 80000
[ "$(hu)" = 1 ] || fail "the note was not delivered"
# Same line, inside the grouping window, from a session with no transcript yet:
# its own note, which waits and has never reached main.
offers "$A" 80000000 "Old claim." "Handled explanation" "$B" 80030000 "Old claim." "Never delivered explanation"
tick 80060
sed -i 's/ pending$/ completed/' "$F/tasks"
tick 80120
grep -qx handled "$S/main-watch/item-heads-up-80000000-face0000" || fail "the delivered note was not marked handled"
[ "$(hu)" = 1 ] || fail "the waiting note was sent with no checkout"
ntasks=$(wc -l < "$F/tasks")

# The cleaner takes the receipt four days later. The ledger is rewritten every
# tick, so it survives.
rm -f "$S/main-watch/item-heads-up-80000000-face0000"
tick $((80120 + 4 * 86400))
[ "$(hu)" = 1 ] || fail "a handled note was posted again after its temp receipt was removed"
[ "$(wc -l < "$F/tasks")" = "$ntasks" ] || fail "a handled note got a new task after its temp receipt was removed"

# A restart empties the temp folder: the ledger goes too and is rebuilt from the
# archive. The handled note stays handled; the one main never got is still its
# own note and arrives once its checkout is known.
rm -f "$S"/main-watch/item-heads-up-* "$S/main-watch/heads-up.json"
tick $((80180 + 4 * 86400))
[ "$(hu)" = 1 ] || fail "a handled note was posted again after the temp folder was emptied"
# The same session shows the same text again, at a new time. With a ledger that
# joins the note main handled; with the ledger gone it must not become a new one.
offers "$A" 80000000 "Old claim." "Handled explanation" "$B" 80030000 "Old claim." "Never delivered explanation" \
  "$A" 500000000 "Old claim." "Handled explanation"
tick $((80200 + 4 * 86400))
[ "$(hu)" = 1 ] || fail "a handled note shown again at a new time was posted as new after the temp folder was emptied"
transcript "$B" "$T/ws/wt-waiting-note"
tick $((80240 + 4 * 86400))
[ "$(hu)" = 2 ] || fail "a note main never got was not posted after the temp folder was emptied"
has "never-handled note" "Never delivered explanation"
case $(cat "$T/last-body") in *"Handled explanation"*) fail "the handled note rode along with the new one" ;; esac

# Handled is on the lasting list in the SAME tick that marks it: a restart
# before the next tick must not bring the note back.
C=face0000-0000-0000-0000-0000000000c3
transcript "$C" "$T/ws/wt-same-tick"
before=$(hu)
offers "$C" 990000000 "Fresh claim." "Same tick explanation"
tick 990000
tick 990060
[ "$(hu)" = $((before + 1)) ] || fail "the fresh note was not delivered exactly once"
grep -qx handled "$S/main-watch/item-heads-up-990000000-face0000" || fail "the fresh note was not marked handled on the tick after delivery"
rm -f "$S"/main-watch/item-heads-up-* "$S/main-watch/heads-up.json"
tick 990120
[ "$(hu)" = $((before + 1)) ] || fail "a note handled one tick ago was posted again after the temp folder was emptied"
