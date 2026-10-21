#!/usr/bin/env bash
# Issue 258: a Builder that ended its turn with no DONE line or verdict was posted to main at once, and main spent a
# turn on a Builder one typed line would have set going again. What this pins: such a Builder, read done or idle, is
# typed one STOPPED line and main hears nothing yet; still stopped one repost window later, main is posted with
# "Nudged"; at most two nudges per pane, so a third stop is posted at once; never a nudge while an open decision
# names the unit; and a pane that is gone is posted without one.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
# The decisions ledger is read through decision.sh; with no ledger nothing is held.
mkdir -p "$REPO/hooks/lib"; cp "$SOURCE/scripts/decision.sh" "$REPO/scripts/"; cp "$SOURCE/hooks/lib/project.sh" "$REPO/hooks/lib/"
tick 5000
nudges() { cat "$T/typed" 2>/dev/null | grep -c -- "--terminal $1 --text Signal STOPPED" || true; }
stopped() { posts "$1 builder stopped without reporting"; }

# One stop: nudged, main not posted; still stopped past the repost window: posted, saying it was nudged.
bseat wt-n1 term_wt-n1 task_wt-n1 9000; state term_wt-n1 working; tick 10000
state term_wt-n1 idle; tick 10060
[ "$(nudges term_wt-n1)" = 1 ] || fail "an idle Builder that stopped without reporting was not nudged once: $(cat "$T/typed" 2>/dev/null)"
[ "$(stopped wt-n1)" = 0 ] || fail "a Builder just nudged was posted to main"
tick 10120
[ "$(nudges term_wt-n1)$(stopped wt-n1)" = 10 ] || fail "a nudged Builder was nudged again or posted inside the repost window"
tick 10400
[ "$(nudges term_wt-n1)" = 1 ] || fail "a Builder still stopped was nudged a second time for the same stop"
grep -q 'wt-n1 builder stopped without reporting.*Nudged 5 min ago' "$T/sends" || fail "a Builder still stopped one window after its nudge was not posted with Nudged"

# A second stop after it worked again is nudged once more; the third posts at once, with no nudge.
for t in 11000 12000; do state term_wt-n1 working; tick $t; state term_wt-n1 "done"; tick $((t + 60)); done
[ "$(nudges term_wt-n1)" = 2 ] || fail "a pane's second stop was not nudged, or its third was"
[ "$(posts 'wt-n1 builder stopped without reporting')" -ge 2 ] || fail "a pane's third stop was not posted at once: $(grep wt-n1 "$T/sends")"

# An open decision naming the unit: the stop is the owner's to settle, so main is posted and the pane is not typed into.
mkdir -p "$REPO/.claude/metrics"
jq -nc '{id: "q-1999-01-01-n2", askedAt: "1999-01-01T00:00:00Z", question: "Keep the reply for wt-n2?", proposedDefault: "keep",
  source: "builder wt-n2", answeredAt: null, answer: null}' > "$REPO/.claude/metrics/decisions.jsonl"
bseat wt-n2 term_wt-n2 task_wt-n2 13000; state term_wt-n2 working; tick 14000; state term_wt-n2 "done"; tick 14060
[ "$(nudges term_wt-n2)$(stopped wt-n2)" = 01 ] || fail "a Builder whose unit has an open decision was nudged, or not posted"
rm -f "$REPO/.claude/metrics/decisions.jsonl"

# A pane that is gone has no one to type to: posted with no nudge.
bseat wt-n3 term_wt-n3 task_wt-n3 15000; state term_wt-n3 working; tick 16000
sed -i '/^term_wt-n3 /d' "$F/agents"; tick 16060; tick $((16060 + 1300))
[ "$(nudges term_wt-n3)" = 0 ] || fail "a gone pane was nudged"
[ "$(stopped wt-n3)" -ge 1 ] || fail "a gone Builder was not posted: $(grep wt-n3 "$T/sends")"

echo "PASS main-watch-nudge.test.sh"
