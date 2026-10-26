#!/usr/bin/env bash
# Issue 341: every fix brief opens its findings so far, by class, and asks a fix that touches a save to update that save's
# row of the evidence file's failure table; a class that comes back is redesigned in order (data design and failure table, a design-only pass to GO, then the
# code, then a whole-branch pass), and the pass after that fix reads the whole branch. After a NO-GO, or a design-only
# pass, the next pass needs the fix's new code checked against the plan.
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
# P1s: a P1 is never capped (issue 366), so the loop runs past the fifth pass on record with a hand-off each NO-GO.
CLS=$'- [P1] (class: lost-reply) CLASS-PROBE -- a.sh:1 -- it drops a reply -- bash a.sh\nVERDICT: NO-GO'
printf 'echo two\n' > "$W/a.sh"; fpass "$W" 2 review "$CLS" >/dev/null
check "the first NO-GO of a class asks for no class fix" 0 "$(hand 2 | grep -c 'The same class again')"
# F3: every fix brief carries the findings so far, grouped by class, and F2: the classes the failure table lacks.
check "the fix brief after the first NO-GO lists its findings so far under their class (and again under what the pass found)" "1 1 2" \
  "$(hand 2 | grep -c '^## Findings so far') $(hand 2 | grep -c '^### lost-reply (1 finding)') $(hand 2 | grep -c 'CLASS-PROBE')"
check "every fix brief says the closing pass rebases onto main first (issue 344)" 1 "$(hand 2 | grep -c 'A closing (final) pass first rebases this unit onto current local main')"
check "a fix brief asks the save's row of the failure table to change with the fix, and lists no classes" "1 0" \
  "$(hand 2 | grep -c "^A fix that touches a save updates that save's row in the evidence file's failure table") $(hand 2 | grep -c '^Classes not yet in the failure table')"
printf '## Failure table\n\n| Save | Steps | Left behind if it stops after each step | The one recovery |\n|---|---|---|---|\n| reply file | write, rename | a half file | the next pass rewrites it |\n' > "$B/$U-evidence.md"
printf 'echo three\n' > "$W/a.sh"; fpass "$W" 3 review "$CLS" >/dev/null
check "the fix round after a class's second return says fix the design, one test for every ordering, send main nothing" "1 1 1 0" \
  "$(hand 3 | grep -c 'Fix the design for the whole class (one fence or stamp) and add one test that covers every ordering found so far') \
$(hand 3 | grep -c 'Send main nothing for it') $(hand 3 | grep -c 'The class fix has one retry path') $(hand 3 | grep -c 'three times')"
# Owner order 2026-10-25 (host change): a redesign coded unchecked brought a new defect each pass, so the design is
# reviewed alone, to GO, before any code.
check "the redesign comes in order: data design and failure table first, a design-only pass to GO, then the code, then a whole-branch pass" "1 1 1" \
  "$(hand 3 | grep -c 'First update the Data design answers in the plan and the failure table in the evidence file so they account for every case found so far, and commit nothing else: run the next pass (final) on that design alone (a commit with no code runs as a design-only pass: its reviewer judges the design, and its GO merges nothing) and fix the design until a pass is GO') \
$(hand 3 | grep -c 'Only then change the code') $(hand 3 | grep -c 'run the next pass on the whole branch (final)')"
check "a later fix brief lists the class under Findings so far and still lists no missing classes" "0 1" "$(hand 3 | grep -c '^Classes not yet in the failure table') $(hand 3 | grep -c '^### lost-reply (1 finding)')"
check "the class-again block starts the background sweep and asks for a Sweep line per site" "1 1" \
  "$(hand 3 | grep -c 'Start one background read-only agent now') $(hand 3 | grep -c 'Sweep: <file>:<line>: fixed')"
printf 'echo four\n' > "$W/a.sh"; fpass "$W" 4 review "$CLS" >/dev/null
check "the pass after a redesign fix reads the whole branch, though it was asked as a review" 1 "$(grep -cx 'Pass: final' "$B/$U-r4-reports.md")"
H4=$(hand 4)
check "a third return (the previous hand-off holds the second-return line) asks main once through ask-main.sh, and the block names neither send --type question nor orchestration ask" "1 1 0 0" \
  "$(grep -c "bash $REAL/scripts/ask-main.sh \"lost-reply: third return\" " <<<"$H4") $(grep -c 'main asks the owner only for a policy call' <<<"$H4") \
$(grep -c 'send --type question' <<<"$H4") $(grep -c 'orchestration ask' <<<"$H4")"

# Issue 362: a class that comes back after a pass in between (not only the one before) is the same flaw seen again, and
# names the pass it was seen in.
CLO=$'- [P1] (class: other-thing) OTHER-PROBE -- a.sh:1 -- another flaw -- bash a.sh\nVERDICT: NO-GO'
printf 'echo five\n' > "$W/a.sh"; fpass "$W" 5 review "$CLO" >/dev/null
check "a NO-GO of another class is no repeat of the class before it" 0 "$(hand 5 | grep -c 'The same class again')"
printf 'echo six\n' > "$W/a.sh"; fpass "$W" 6 review "$CLS" >/dev/null
check "the class back after a pass of another class between is named as back after an earlier pass" 1 "$(hand 6 | grep -c 'came back after an earlier pass')"
# Issue 362: after a NO-GO, the next pass does not start until the evidence file holds the Builder's search for the same
# pattern at the other call sites: a Search: line, then a line per site, fixed or not affected and why. Called directly,
# without the fixture's helper that writes the section.
check "the hand-off after a NO-GO tells the Builder to write the sites section and the new-code check before the next pass" "1 1" \
  "$(hand 6 | grep -c 'add `## Sites checked (pass 6)`') $(hand 6 | grep -c 'add `## New code checked (pass 6)`')"
rawpass() { (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-$1 STUB_REPLY="$3" bash "$PASS_SH" "$U" "$1" "$2" >"$TMP/out" 2>"$TMP/err"); echo $?; }
printf 'echo seven\n' > "$W/a.sh"
check "after a NO-GO the next pass refuses without a sites section, names it, and starts no round" "2 1 no" \
  "$(rawpass 7 review 'VERDICT: GO') $(grep -c "has no usable '## Sites checked (pass 6)' section" "$TMP/err") $([ -e "$B/$U-r7-reports.md" ] && echo yes || echo no)"
printf '\n## Sites checked (pass 5)\nSearch: grep -rn x .\n- a.sh:1 fixed\n\n## Sites checked (pass 6)\nSearch: grep -rn y .\n' >> "$B/$U-evidence.md"
check "a section for another pass, or one with a search and no site line, does not count" "2 no" \
  "$(rawpass 7 review 'VERDICT: GO') $([ -e "$B/$U-r7-reports.md" ] && echo yes || echo no)"
printf -- '- b.sh:3 not affected, it only reads the value\n' >> "$B/$U-evidence.md"
# Owner order 2026-10-25 (host change): a fix's new reads and writes broke rules its own plan already stated, so the pass
# after a NO-GO also needs the Builder's check of its new code against the plan.
check "Sites checked alone is refused: the new code was not checked against the plan" "2 1 no" \
  "$(rawpass 7 review 'VERDICT: GO') $(grep -c "has no usable '## New code checked (pass 6)' section" "$TMP/err") $([ -e "$B/$U-r7-reports.md" ] && echo yes || echo no)"
printf '\n## New code checked (pass 6)\n- a.sh:1 looks fine\n' >> "$B/$U-evidence.md"
check "a New code line that names no plan rule and no reason is refused" 2 "$(rawpass 7 review 'VERDICT: GO')"
printf -- '- a.sh:2 meets What can go wrong, a dropped reply: the reply is kept\n' >> "$B/$U-evidence.md"
check "with the search, a site line and a New code line under the right pass, the pass runs" "0 yes" \
  "$(rawpass 7 review 'VERDICT: GO') $([ -e "$B/$U-r7-reports.md" ] && echo yes || echo no)"
# Issue 366: pass 7 is a closing pass, a fresh reviewer handed neither list; narrowed pass 3 was handed both.
check "a narrowed pass's reviewers are handed both lists, and told a missing site or a broken plan rule is a finding; a closing pass's are not" "1 1 0 0 0 0" \
  "$(input 3 | grep -c 'Sites checked: the Builder') $(input 3 | grep -c 'New code checked: the Builder') \
$(input 7 | grep -c 'b.sh:3 not affected') $(input 7 | grep -c 'Sites checked: the Builder') $(input 7 | grep -c 'a.sh:2 meets What can go wrong, a dropped reply') $(input 7 | grep -c 'New code checked: the Builder')"
# A redesign is reviewed alone (a pass whose commit is only the plan); the code written after its GO has been read by no
# pass yet, so it owes the New code check though the pass before it was a GO.
mkdir -p "$W/.claude/plans"; echo 'Data design: one fence' > "$W/.claude/plans/$U.md"
check "a design-only pass commits only the plan" "0 .claude/plans/$U.md" \
  "$(rawpass 8 review 'VERDICT: GO') $(git -C "$W" show --name-only --format= HEAD | paste -sd' ' -)"
printf 'echo fence\n' > "$W/a.sh"
check "the code after a design-only GO is refused without New code checked for that pass" "2 1" \
  "$(rawpass 9 review 'VERDICT: GO') $(grep -c "pass 8 reviewed a design alone" "$TMP/err")"
printf '\n## New code checked (pass 8)\n- a.sh:1 meets Data design, one fence\n' >> "$B/$U-evidence.md"
check "...and taken with it" 0 "$(rawpass 9 review 'VERDICT: GO')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
