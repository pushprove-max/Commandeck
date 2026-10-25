#!/usr/bin/env bash
# Issue 341: every fix brief opens its findings so far, by class, and names the classes the evidence file's failure table
# lacks; a class that comes back is redesigned in order (data design and failure table, then the code, then a whole-branch
# pass), and the pass after that fix reads the whole branch.
# builder-codex-pass.sh fix rounds when a finding class keeps coming back. The second return (the same class in two
# NO-GOs in a row) is fixed by design: one fence or stamp for the class, one test covering every ordering found so
# far, and main is sent nothing. The third return (the previous hand-off already carries that line) is one question
# to main through ask-main.sh, which addresses main and waits on its reply; the hand-off names neither a bare
# `send --type question` nor `orchestration ask`. The fixture is the one builder-codex-pass.test.sh uses.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

printf 'echo built\n' > "$W/a.sh"
pass 1 adversarial
printf 'handle=term_frs\ntask=task_frs\nunit=%s\nrole=builder\nsession=old-sid\n' "$U" > "$SC/seat-$U-builder.txt"
mkdir -p "$PROJ"; echo "$B/$U-fix-r7.md" > "$PROJ/old-sid.jsonl"; touch -t 209901010000 "$PROJ/old-sid.jsonl"
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 40 >/dev/null)
CLS=$'- [P2] (class: lost-reply) CLASS-PROBE -- a.sh:1 -- it drops a reply -- bash a.sh\nVERDICT: NO-GO'
printf 'echo two\n' > "$W/a.sh"; fpass "$W" 2 review "$CLS" >/dev/null
check "the first NO-GO of a class asks for no class fix" 0 "$(hand 2 | grep -c 'The same class again')"
# F3: every fix brief carries the findings so far, grouped by class, and F2: the classes the failure table lacks.
check "the fix brief after the first NO-GO lists its findings so far under their class (and again under what the pass found)" "1 1 2" \
  "$(hand 2 | grep -c '^## Findings so far') $(hand 2 | grep -c '^### lost-reply (1 finding)') $(hand 2 | grep -c 'CLASS-PROBE')"
check "every fix brief says the closing pass rebases onto main first (issue 344)" 1 "$(hand 2 | grep -c 'A closing (final) pass first rebases this unit onto current local main')"
check "and names the class the evidence file's failure table lacks" 1 "$(hand 2 | grep -c '^Classes not yet in the failure table of the evidence file: lost-reply')"
printf '## Failure table\n\n| pass | class | what failed | fixed by | test |\n|---|---|---|---|---|\n| 2 | lost-reply | a reply is dropped | - | - |\n' > "$B/$U-evidence.md"
printf 'echo three\n' > "$W/a.sh"; fpass "$W" 3 review "$CLS" >/dev/null
check "the fix round after a class's second return says fix the design, one test for every ordering, send main nothing" "1 1 1 0" \
  "$(hand 3 | grep -c 'Fix the design for the whole class (one fence or stamp) and add one test that covers every ordering found so far') \
$(hand 3 | grep -c 'Send main nothing for it') $(hand 3 | grep -c 'The class fix has one retry path') $(hand 3 | grep -c 'three times')"
check "the redesign comes in order: data design and failure table first, then the code, then a whole-branch pass" "1 1 1" \
  "$(hand 3 | grep -c 'First update the Data design and the failure table in the evidence file') $(hand 3 | grep -c 'Then change the code') $(hand 3 | grep -c 'The next pass reads the whole branch')"
check "a class in the failure table is not named as missing" "0 1" "$(hand 3 | grep -c '^Classes not yet in the failure table') $(hand 3 | grep -c '^### lost-reply (1 finding)')"
check "the class-again block starts the background sweep and asks for a Sweep line per site" "1 1" \
  "$(hand 3 | grep -c 'Start one background read-only agent now') $(hand 3 | grep -c 'Sweep: <file>:<line>: fixed')"
printf 'echo four\n' > "$W/a.sh"; fpass "$W" 4 review "$CLS" >/dev/null
check "the pass after a redesign fix reads the whole branch, though it was asked as a review" 1 "$(grep -cx 'Pass: final' "$B/$U-r4-reports.md")"
H4=$(hand 4)
check "a third return (the previous hand-off holds the second-return line) asks main once through ask-main.sh, and the block names neither send --type question nor orchestration ask" "1 1 0 0" \
  "$(grep -c "bash $REAL/scripts/ask-main.sh \"lost-reply: third return\" " <<<"$H4") $(grep -c 'main asks the owner only for a policy call' <<<"$H4") \
$(grep -c 'send --type question' <<<"$H4") $(grep -c 'orchestration ask' <<<"$H4")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
