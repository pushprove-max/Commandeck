#!/usr/bin/env bash
# The Builder brief template is the only place a Builder learns these rules;
# each was carried as a local patch by a user and lost in an update, or cost a
# build its time: a red hang test run to the command's limit, evidence
# written at the end so every item showed unbuilt (#90), a new setting read
# only in its new format, hand-written polls on a test log (#84), and
# the "change nothing after GO" rule kept after a failed merge, with answers
# after the done marker left unread (#93), a file that timed out twice run a
# third time, and test results with no load beside them.
set -uo pipefail
T="$(cd "$(dirname "$0")/../.." && pwd)/templates/_builder-brief-template.md"
PASS=0 FAIL=0
check() { if grep -qF -- "$2" <<<"$BODY"; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (no \"$2\")"; fi }
# One line per paragraph, so a rule wrapped across lines is still one string.
BODY=$(awk 'NF { printf "%s ", $0; next } { print "" } END { print "" }' "$T" | sed -E 's/ +/ /g')
check "the first turn opens the brief and its files together, and later looks are batched" "In your first turn, open this brief and every file it names, together; after that, send every look whose inputs you already know in one turn."
check "a red hang test sets its own short timeout" "A red test that shows a hang sets its own short timeout"
check "each evidence heading is written the moment its item turns green (#90)" "The moment an item's test turns green, add its section to the evidence file: \`## #<issue> <title>\`, then the guarding test name and file on the next line."
check "a changed setting keeps reading the deployed format" "keeps reading the format already deployed from its first commit, and has a test that the release accepts the deployed format"
check "a poll on test output goes to run_in_background, a blocking wait to wait-test-run.sh only (#84)" "start the run with \`run_in_background\`, which tells you when it exits. To block on it, wait only with \`bash {scripts}/wait-test-run.sh <runner-pid> <output-file>\`"
check "a refused merge or main's word lifts the no-change rule (#93)" "The rule is lifted when the merge refuses the branch or main tells you to change something"
check "an answer after the done marker is still read (#93)" "An answer from main that arrives after it is still yours: read it and act on it."
check "a file that times out twice is one question to main, not a third run" "a second timeout is one question to main"
check "a red proof goes through red-proof.sh, never a hand-broken tree" "/red-proof.sh <file> <line> <replacement> -- <test"
check "a main-only finding goes under the deferred heading every later pass reads" "goes as one line under \`## Main-only (deferred)\` in the evidence file"
check "a test result carries the machine's load and time beside it" "\`bash -c '. {scripts}/host-services.sh && hs_stamp'\` prints it with the time"
# main's rulings file: the pass reads stated limits from one heading only, so the template must carry it.
BODY=$(cat "${T%/*}/main-rulings.md")
check "the rulings template has the heading the pass reads limits from" "## Stated limits"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
