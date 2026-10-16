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
check "a fix-round session starts from its hand-off and opens the brief only when a finding needs it" "A fix-round session starts from its hand-off alone, and opens this brief and the evidence file only when a finding needs them."
check "every launch is checked first with the pass script's --check, which commits nothing" "Before every launch run \`bash {scripts}/{pass-script} --check {unit} <N> <kind>\`"
check "no Builder writes a new end-to-end test" "Builders never write new end-to-end tests: no test installs or uninstalls the plugin, or runs setup.sh or uninstall.sh whole."
# main's rulings file: the pass reads stated limits from one heading only, so the template must carry it.
BODY=$(cat "${T%/*}/main-rulings.md")
check "the rulings template has the heading the pass reads limits from" "## Stated limits"
# Main writes a "leave as is" ruling under the heading its rules name; a ruling under any other is raised again as a blocker.
H=$(sed -n 's/.*stays as it is goes under `\(#[^`]*\)`.*/\1/p' "${T%/*}/main-session.md")
LIMITS_AWK=$(grep -o "awk '[^']*Stated limits[^']*'" "${T%/templates/*}/scripts/builder-codex-pass.sh")
BODY=$(printf '# Rulings\n%s\n- the retry stays as it is.\n## Later\n- not a limit\n' "$H" | eval "$LIMITS_AWK")
[ "$BODY" = "- the retry stays as it is." ] && BODY="limits read: exactly the ruling"
check "a 'leave as is' ruling under the heading main's rules name is the limit the pass reads, and nothing else is" "limits read: exactly the ruling"
# The plugin's own test rules carry the same rule.
BODY=$(awk 'NF { printf "%s ", $0; next } { print "" } END { print "" }' "${T%/templates/*}/CONTRIBUTING.md" | sed -E 's/ +/ /g')
check "the contributor test rules forbid a new end-to-end test" "No test installs or uninstalls the plugin, or runs \`setup.sh\` or \`uninstall.sh\` whole"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
