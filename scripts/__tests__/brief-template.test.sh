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
# Host issue 3164: the first class stop starts one background sweep of every site where the class's flaw can occur.
check "the class rule names the background sweep and the Sweep line" "The first class stop also starts one background read-only agent that lists every site in the changed files, and the scripts they source, where the class's flaw can occur, checked against the class's ruling. Fix or justify each site before the next pass: the evidence file gets one line per site, \`Sweep: <file>:<line>: fixed\` or \`Sweep: <file>:<line>: safe, <why>\`."
# Host issue 336: a file whose inputs did not change since an earlier green commit is cited at that commit.
check "the closing-run rule names the cite-at-commit line and the complete run on the tip" "is cited with that commit: \`Closing run: <file>: cited <log path> at <commit>, <n> passed, <n> failed\`. Once the closing pass ends GO, one complete run of every touched file on that tip (\`bash {scripts}/run-shell-tests.sh --changed <base> --callers\`) is the last run before the hand-off."
check "the closing-run rule names test-inputs.sh and its unchanged line" "\`bash {scripts}/test-inputs.sh <commit> <file>...\` prints \`unchanged <file>\`"
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
# Message cuts (issue 2894's twin): the second return of a class is the Builder's to fix by design and costs main nothing;
# the third is one ask-main.sh question, and main answers redesign unless the owner must make a policy call.
check "the class rule says fix the design on the second return: one fence or stamp, one test for every ordering" "When the class comes back a second time, fix the design: one fence or stamp for the whole class, and one test that covers every ordering found so far."
check "the class rule says send main nothing on the second return, and one ask-main.sh question on the third" "Write in the evidence file what the class is, and send main nothing for it: the review loop goes on. When the class returns a THIRD time, the fix-round hand-off says so: fix the other findings first, then ask main one question with \`ask-main.sh\` naming the class and the redesign you propose, and build what main answers."
# Issue 341: the Builder brief carries the Data design and failure table rules, and the redesign order on a class's first repeat.
check "the Builder brief has a Data design section the Builder copies into the evidence file and keeps true" "The batch's Data design section above binds. Before the first edit copy it into the evidence file as \`## Data design\`, and keep it true"
check "the evidence file carries a failure table kept current before every pass" "The evidence file also carries \`## Failure table\`, one row per failure a test or a pass found, kept current before every pass"
check "a class's redesign goes data design and failure table first, then the code, then a whole-branch pass" "The redesign goes in this order: update the Data design and the failure table in the evidence file first, then the code, then take a whole-branch pass"
if grep -qF '## Data design' "${T%/*}/_batch-brief-template.md" && grep -qF 'builder-launch.sh refuses a batch without it. For each piece of state' "${T%/*}/_batch-brief-template.md"; then PASS=$((PASS+1)); echo "ok   the batch brief template has the required Data design section"; else FAIL=$((FAIL+1)); echo "FAIL the batch brief template has no required Data design section"; fi
# Issue 344 (host issue 3171): the closing pass rebases first and runs the tests that cover what moved.
check "the closing pass rebases onto current local main first and runs the covering tests; a conflict or a red test stops it" "Before it reads anything it rebases your branch onto current local main and, when main moved, runs the shell tests that cover what you or main changed (not the full suite); a conflict stops the pass, aborted and named, for main to resolve, and a red test stops it before the reviewer."
if grep -qF 'about 100 tokens' <<<"$BODY"; then FAIL=$((FAIL+1)); echo "FAIL the class rule still sends main a 100-token status note"; else PASS=$((PASS+1)); echo "ok   the class rule sends main no status note"; fi
# Issues 260 and 266: a review run as the closing pass is the last one; a separate final after it reviewed the same tip again.
check "the Builder template: final in place of review means no separate final follows" 'A `review` that prints `final in place of review`'
check "and that review is the closing pass whose GO merges" 'is the closing pass: its GO merges, and no separate final follows.'
SAVED=$BODY BODY=$(awk 'NF { printf "%s ", $0; next } { print "" } END { print "" }' "${T%/*}/main-session.md" | sed -E 's/ +/ /g')
check "main's class rule: one retry path, tested state by state" "$RETRY"
check "main-session.md sends the Builder to redesign on the third return and asks the owner only for a policy call" "answer redesign by default, and send the Builder to redesign the whole mechanism. Ask the owner only for a real policy call (what the product promises, security posture, a stated limit)."
check "main-session.md leaves the second return to the Builder, sending main nothing" "is the Builder's to fix by design, and it sends main nothing for it."
check "main's checklist rule names the 8-item cap, the 80-character subject and no ids" "At most 8 open items; a subject of 80 characters at most, with no ids (no message, task or dispatch id, commit hash or issue number)."
check "main's checklist rule says a done item is deleted, never marked completed" "An item done is deleted (TaskUpdate status deleted), never marked completed; the checkpoint's Closed section keeps it."
# Host issue 3165: main's card names the large-read rule inside its 40 lines; Details hold the example prompt.
check "main's card names the large-read rule and the 10 KB line" "a read over 10 KB (merge log, review report, run result) goes to a background read-only agent with one question"
check "main's Details hold the large-read example prompt" "Large reads (host issue 3165): a read over 10 KB goes to a background \`Explore\` helper with one precise question and the file path"
# Issue 343: a hand merge leaves its worktree, which the dashboard reads as a unit still building; main runs step 5.
check "main's Details: after a hand merge main runs step 5 of merge-unit-local.sh and removes the worktree" "After a hand merge, or a failed auto-merge you finish by hand, run step 5 of \`merge-unit-local.sh\` yourself: close the unit's panes, then \`merge-unit-local.sh <unit> --cleanup\` (never a forced remove)."
if [ "$(grep -n '^## Details' "${T%/*}/main-session.md" | cut -d: -f1)" -le 41 ]; then PASS=$((PASS+1)); echo "ok   main's card is still 40 lines (Details heading on line 41)"; else FAIL=$((FAIL+1)); echo "FAIL main's card is over 40 lines"; fi
# Issue 340: main's waiting rule names the 30-second line, and the card is still 40 lines.
check "main's card: any wait over about 30 s on external state runs in the background" "a long job, or any wait over about 30 s on external state (a directory-size scan included), in main's foreground -> its own pane, or \`run_in_background\`"
# Issue 345: settings decide. Main asks neither "Write a plan first?" nor "Which model and effort?"; it runs plan-tier.sh,
# says in one line what it picked, and a plan is still never a build order.
check "main's card: plan-tier.sh and the configured seats decide, told in one line" "before \`builder-launch.sh\`, ask nothing: run \`plan-tier.sh <batch file>\`, use the"
check "main's card: the owner changes the trigger file or /plugin settings, or says so in chat" "The owner changes the trigger file or \`/plugin\` settings, or says so in chat for that unit."
check "main's Details: neither question is asked" "ask neither \"Write a plan"
check "main's Details: a seat runs on its printed model and effort" "Each seat runs on its printed model and effort"
if ! grep -qF -e 'ask the owner "Write a plan' -e 'Then ask "Which model and effort?"' "${T%/*}/main-session.md" && grep -qF 'ask no question. Run `plan-tier.sh <batch file>`' "${T%/*}/AGENT_STARTUP.md"; then PASS=$((PASS+1)); echo "ok   neither main-session.md nor AGENT_STARTUP.md tells main to ask the plan or model question"; else FAIL=$((FAIL+1)); echo "FAIL a template still tells main to ask the plan or model question"; fi
check "a plan is still never a build order" "A plan is never a build order: with no build word from the owner, STOP at the plan file."
# Issue 333: an auto-decided answer has no ruling; main checks it against its ledger row, and still checks every other
# relayed answer against the ruling log. r2 (class delivery-retry): the ledger row alone, the one record relay-order.sh's
# retry also reads; a mode-file condition made main refuse a retry sent after /autodecide off.
check "main-session.md: an auto-decided message is checked against its ledger row alone" 'A message titled `auto-decided for the owner on <id>` is the relay'"'"'s own decision under auto-decide, not an owner ruling: there is no ruling to find. Act on it when the ledger row for `<id>` answers `<words> (auto-decided)`, whether or not auto-decide is still on; else ask the relay.'
if grep -qF 'autodecide.on' <<<"$BODY"; then FAIL=$((FAIL+1)); echo "FAIL main-session.md still makes main check autodecide.on"; else PASS=$((PASS+1)); echo "ok   main-session.md does not make main check autodecide.on"; fi
check "main-session.md: every other relayed answer is still checked against the ruling log" 'check each relayed answer against `~/.claude/rulings/<project>.jsonl` before acting.'
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
check "the owner-answer wait fits the cache budget: 240 s waits resumed up to 9 minutes" "\`check --wait --timeout-ms 240000 --ack <the deliveryId your last read returned>\`, resumed until 9 minutes in all"
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
# Issue 335: a Builder's question to main had no address and no wait on its own reply. Both templates name the one script,
# and neither names the old ways (a bare send, or the ask that cannot address a pane).
ST="$R/templates/AGENT_STARTUP.md"
BAD=$(grep -l -E 'orchestration ask|send --type question|--to main' "$T" "$ST" | paste -sd' ' -)
if [ -z "$BAD" ] && grep -q 'ask-main.sh' "$T" && grep -q 'ask-main.sh' "$ST"; then PASS=$((PASS+1)); echo "ok   the brief and AGENT_STARTUP.md both name ask-main.sh for a question to main, and neither names orchestration ask, send --type question or --to main for it"
else FAIL=$((FAIL+1)); echo "FAIL a template still names the old way, or lacks ask-main.sh: ${BAD:-none}"; fi
# A wait without --ack returns the oldest batch again at once, old mail first.
NOACK=$(grep -o 'check --wait[^`]*' "$T" | grep -v -- '--ack' | paste -sd' ' -)
if [ -z "$NOACK" ]; then PASS=$((PASS+1)); echo "ok   every check --wait in the Builder brief carries --ack"
else FAIL=$((FAIL+1)); echo "FAIL a check --wait in the brief has no --ack: $NOACK"; fi
# Message cuts: a progress note to main is a wake main cannot act on; both templates carry the one rule.
ONE='One status per decision: message main only for a decision only main or the owner can make. No progress notes; progress goes in the evidence file.'
if grep -qF "$ONE" "$T" && grep -qF "$ONE" "$ST"; then PASS=$((PASS+1)); echo "ok   the brief and AGENT_STARTUP.md both carry the one-status-per-decision rule"
else FAIL=$((FAIL+1)); echo "FAIL the one-status-per-decision rule is missing from the brief or AGENT_STARTUP.md"; fi
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
