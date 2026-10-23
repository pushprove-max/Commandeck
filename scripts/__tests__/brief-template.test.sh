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
check "a main-only finding goes under the deferred heading every later pass reads" "goes as one line under \`## Main-only (deferred)\` in the evidence file"
check "a test result carries the machine's load and time beside it" "\`bash -c '. {scripts}/host-services.sh && hs_stamp'\` prints it with the time"
check "a fix-round session starts from its hand-off and opens the brief only when a finding needs it" "A fix-round session starts from its hand-off alone, and opens this brief and the evidence file only when a finding needs them."
check "every launch is checked first with the pass script's --check, which commits nothing" "Before every launch run \`bash {scripts}/{pass-script} --check {unit} <N> <kind>\`"
# A closing run of a file already green on the same tree was the third run the
# validation guard refuses: one Builder bypassed it, another could skip it unsaid.
check "the closing run covers only touched files whose inputs changed since their last green run" "ONE run of every test file this build touched whose inputs changed since its last green run starts in the background beside the closing pass"
check "a touched file already green on the current tree is cited, not run again" "a touched file already green on the current tree is cited instead (its log path and totals), never run again"
check "the evidence lists each touched test file as run or cited" "The evidence file lists each touched test file as run or cited: \`Closing run: <file>: run, <n> passed, <n> failed\` or \`Closing run: <file>: cited <log path>, <n> passed, <n> failed\`."
# The leak check searches an image's text chunks only: its pixels are a human check.
check "a new or changed image needs the owner's review line in the evidence" "A new or changed image needs the owner's review: the evidence file carries \`image reviewed by the owner: <file>\` for each"
check "no Builder writes a new end-to-end test" "Builders never write new end-to-end tests: no test installs or uninstalls the plugin, or runs setup.sh or uninstall.sh whole."
# Issue 282: an exception a comment justified hid a real gap for months; the Builder template and the global rules carry the rule.
EXC='An exception, allowlist or exemption entry in a guard or its test stands only when the same test proves the alternative it claims, or the entry cites an owner ruling id. A comment is not proof.'
check "the Builder template: an exception entry stands only on a proof in its test or a ruling id" "$EXC"
SAVED=$BODY BODY=$(awk 'NF { printf "%s ", $0; next } { print "" } END { print "" }' "${T%/*}/global-rules.md" | sed -E 's/ +/ /g')
check "the global rules: an exception entry stands only on a proof in its test or a ruling id" "$EXC"
BODY=$SAVED
# Issue 303: a class-stop fix kept a second retry path that only one source of state reached.
RETRY='The class fix has one retry path that does not depend on where the state came from, and its test removes each piece of state between two runs (ticks) and shows the retry still happens.'
check "the Builder template: a class fix has one retry path, tested state by state" "$RETRY"
# Issues 260 and 266: a review run as the closing pass is the last one; a separate final after it reviewed the same tip again.
check "the Builder template: final in place of review means no separate final follows" 'A `review` that prints `final in place of review`'
check "and that review is the closing pass whose GO merges" 'is the closing pass: its GO merges, and no separate final follows.'
SAVED=$BODY BODY=$(awk 'NF { printf "%s ", $0; next } { print "" } END { print "" }' "${T%/*}/main-session.md" | sed -E 's/ +/ /g')
check "main's class rule: one retry path, tested state by state" "$RETRY"
BODY=$SAVED
# Issue 325 (owner ruling of 2026-10-23, over issue 323's every-finding rule): only a bug normal use
# would hit blocks the merge; a bypass or odd-setup finding is a one-line known gap. One wording in the template and the global rules.
KG='A review finding blocks the merge only when normal use would hit the bug'
GAP='A finding that needs an agent deliberately bypassing a guard, or an odd setup, is a one-line known gap in the evidence file and does not block.'
check "only a bug normal use would hit blocks the merge, and only a GO naming no blocking finding closes" "$KG"
check "a bypass or odd-setup finding is a known gap that does not block" "$GAP"
check "no blocking finding is left open at merge" "There is no narrowed-pass exit and no blocking finding left open at merge."
SAVED=$BODY BODY=$(awk 'NF { printf "%s ", $0; next } { print "" } END { print "" }' "${T%/*}/global-rules.md" | sed -E 's/ +/ /g')
check "the global rules carry the same two sentences" "$KG"
check "the global rules: a bypass or odd-setup finding is a known gap" "$GAP"
BODY=$SAVED
# The cache-budget hook refuses a foreground wait over 270 s, so the owner-answer wait is 240 s waits, resumed.
check "the owner-answer wait fits the cache budget: 240 s waits resumed up to 9 minutes" "\`check --wait --timeout-ms 240000\`, resumed until 9 minutes in all"
if grep -qi 'P2/P3 only' "$T"; then FAIL=$((FAIL+1)); echo "FAIL the template still lets a P2/P3-only pass merge"; else PASS=$((PASS+1)); echo "ok   no P2/P3-only exit"; fi
# Issues 254 and 255: the gate merges a unit unless main holds it, and main's post-merge lines go under the last
# heading, which the merge reads to the end: the template's own section is empty. Issue 306 R10: no rung line.
check "the template names the hold line the merge gate reads" "unless main adds a line \`Merge: hold\` to this brief"
[ "$(tail -n 1 "$T")" = "## Post-merge" ] && ! grep -q 'Ponytail: item' "$T" && BODY="post-merge last and empty, no rung line"
check "the Post-merge section is the template's last line, and no rung line is asked for" "post-merge last and empty, no rung line"
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
# Issue 323: red proofs are retired. A template line still ordering one kept Builders running red-proof batches,
# and a pass or merge that wants a Mutation-verified: line refuses commits Builders no longer write.
R=${T%/templates/*}
LEFT=$(cd "$R" && grep -l -i -E 'red[- ]proof|Mutation-verified|mutation[- ]note' templates/* hooks/*.sh scripts/*.sh 2>/dev/null | paste -sd' ' -)
if [ -z "$LEFT" ]; then PASS=$((PASS+1)); echo "ok   no template, prompt, pass or merge check mentions red proofs or a mutation line (issue 323)"
else FAIL=$((FAIL+1)); echo "FAIL red proofs or a mutation line still in: $LEFT"; fi
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
