#!/usr/bin/env bash
# builder-codex-pass.sh fix rounds: the owner's open and answered decisions reach the reviewers and the hand-off; a
# review after a closing pass's P1 runs as the closing pass; a class that comes back in two passes in a row asks for
# the approach that fixes the class; and each finding names its test file and commands.
# The fixture is the one builder-codex-pass.test.sh uses.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

# The state these cases start from: a first pass.
printf 'echo built\n' > "$W/a.sh"
pass 1 adversarial
mkdir -p "$W/x/__tests__"; echo t > "$W/x/__tests__/y.test.sh"
printf '## 1. RULING-PROBE: keep the probe\n' > "$REPO/.claude/briefs/$U-main-rulings.md"
printf '## Cleared findings
- [P1] CLEAR-PROBE -- a.sh:1
' >> "$REPO/.claude/briefs/$U-main-rulings.md"
(cd "$W" && COMMANDECK_MAIN=$REPO bash "$PASS_SH" --ack-rulings "$U" >/dev/null 2>&1)
printf 'handle=term_frs\ntask=task_frs\nunit=%s\nrole=builder\nsession=old-sid\n' "$U" > "$SC/seat-$U-builder.txt"
# The cleared session's own log names the hand-off too (it read the pass's output); it is not the new one.
mkdir -p "$PROJ"; echo "$B/$U-fix-r7.md" > "$PROJ/old-sid.jsonl"; touch -t 209901010000 "$PROJ/old-sid.jsonl"

(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 40 >/dev/null)
# Issue 265: a fix round changed a behaviour the owner still had an open question on. The pass hands its reviewers the
# owner's decisions that name the unit; the hand-off lists the open ones as HOLD, read again as it is written.
LED=$REPO/.claude/metrics/decisions.jsonl; mkdir -p "${LED%/*}"
row() { jq -nc --arg id "$1" --arg q "$2" --arg a "$3" '{id: $id, askedAt: "1999-01-01T00:00:00Z", question: $q, proposedDefault: "keep",
  source: "builder unit", answeredAt: (if $a == "" then null else "1999-01-02T00:00:00Z" end), answer: (if $a == "" then null else $a end)}'; }
{ row q-1999-01-01-open "Keep the old reply?" ""; row q-1999-01-01-done "Drop the cache?" "drop it"; } > "$LED"
printf 'echo eighteen\n' > "$W/a.sh"
check "a final NO-GO with a P1 from the Builder's pane hands over" 0 "$(fpass "$W" 18 final "$NOGO")"
check "the prompt names the open decision and the answered one with its answer" "1 1" \
  "$(input 18 | grep -c 'Open question to the owner q-1999-01-01-open: Keep the old reply?') $(input 18 | grep -c 'The owner answered q-1999-01-01-done (Drop the cache?): drop it')"
check "the hand-off has the HOLD section with the open id only, after the findings" "1 1 0 1" \
  "$(hand 18 | grep -cx '## Open decisions (HOLD)') $(hand 18 | sed -n '/^## Open decisions/,/^## /p' | grep -c 'q-1999-01-01-open') \
$(hand 18 | sed -n '/^## Open decisions/,/^## /p' | grep -c 'q-1999-01-01-done') $(hand 18 | grep '^## ' | sed -n '/What pass 18 found/,$p' | grep -cx '## Open decisions (HOLD)')"
# Issues 260 and 266: a review after a closing pass that found a P1 merged nothing on its GO; it runs as the closing pass.
printf 'echo nineteen\n' > "$W/a.sh"; chk19() { (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO bash "$PASS_SH" --check "$U" 19 review 2>&1); }
check "--check prints the same pick: final in place of review" 1 "$(chk19 | grep -c '^final in place of review: .*this is the closing pass, its GO merges and no separate final follows')"
echo '{"id":' >> "$LED"
P2A=$'- [P2] (class: lost-reply) P2-PROBE -- a.sh:1 -- it drops a reply -- bash a.sh\nVERDICT: NO-GO'
check "the review after a closing pass's P1 runs as final" "0 1 1" \
  "$(fpass "$W" 19 review "$P2A") $(grep -c '^final in place of review: ' "$TMP/out") $(grep -cx 'Pass: final' "$B/$U-r19-reports.md")"
check "a ledger that cannot be read is said so in the prompt and the hand-off, never shown as none" "1 1" \
  "$(input 19 | grep -c 'decisions ledger .* could not be read') $(hand 19 | grep -c 'decisions ledger .* could not be read')"
rm -f "$LED"
check "the first NO-GO of a class asks for no class approach" 0 "$(hand 19 | grep -c 'came back in two passes in a row')"
# A closing pass that left a P2 only: every finding blocks the merge, so the review after it is the closing pass. The
# same class again asks for the approach that fixes the class (issue 261), with one retry path tested state by state (issue 303).
printf 'echo twenty\n' > "$W/a.sh"
check "after a closing pass that left P2 only, the next review runs as final" "0 1 1" \
  "$(fpass "$W" 20 review "$P2A") $(grep -c '^final in place of review' "$TMP/out") $(grep -cx 'Pass: final' "$B/$U-r20-reports.md")"
check "a second NO-GO on one class adds the approach line, its retry rule and the open-decision clause" "1 1 1" \
  "$(hand 20 | grep -c 'Findings of class lost-reply came back in two passes in a row (r19, r20). Do not fix them input by input') \
$(hand 20 | grep -c 'one retry path that does not depend on where the state came from, and its test removes each piece of state between two runs') $(hand 20 | grep -c 'If the approach touches an open decision, ask main first.')"
check "the earlier-passes block asks a finding like an earlier one to keep its class" 1 \
  "$(input 20 | grep -c 'keeps that finding.s class tag')"
# Issue 264: each finding names its test file, the case filter its header names, and the commands.
mkdir -p "$W/hooks/__tests__"; printf 'exit 0\n' > "$W/hooks/bash-guardrails.sh"; echo f > "$W/x/__tests__/fixture.txt"
printf '#!/usr/bin/env bash\n# BASH_GUARDRAILS_TEST_CASE=<label part> runs one case.\n' > "$W/hooks/__tests__/bash-guardrails.test.sh"
# r4: a finding's place is the first one on its line, not a place its text quotes; a numbered finding is one too.
P2B=$'- [P2] (class: other-class) GUARD-PROBE -- hooks/bash-guardrails.sh:1 -- it lets one through, as `x -- q.sh:9 -- y` -- bash x\n2. [P2] (class: other-class) BARE-PROBE -- a.sh:1 -- no test -- bash a.sh\nVERDICT: NO-GO'
check "a NO-GO of two other classes runs" 0 "$(fpass "$W" 21 review "$P2B")"
TPF=$(hand 21 | sed -n '/^## Tests per finding/,/^## /p')
check "a finding on a hook names its same-name test, its case variable and its run command, no red proof (issue 323); that test exists" "1 1 1 0 1" \
  "$(grep -c '^- hooks/bash-guardrails.sh:1: test hooks/__tests__/bash-guardrails.test.sh' <<<"$TPF") $(grep -c 'BASH_GUARDRAILS_TEST_CASE' <<<"$TPF") \
$(grep -c "run: BASH_GUARDRAILS_TEST_CASE='<case label>' bash $REAL/scripts/run-shell-tests.sh hooks/__tests__/bash-guardrails.test.sh" <<<"$TPF") $(grep -c -e 'red proof:' -e 'red-proof\.sh' <<<"$TPF") \
$([ -f "$W/$(grep -o 'test hooks/__tests__/[^ ;,]*' <<<"$TPF" | head -1 | cut -d' ' -f2)" ] && echo 1)"
check "a finding on a file with no same-name test says so" 1 "$(grep -c '^- a.sh:1: no same-name test: name the test file in the evidence before the fix' <<<"$TPF")"
check "a place the finding's text quotes gets no test line" 0 "$(grep -c 'q.sh:9' <<<"$TPF")"
check "two different classes add no approach line" 0 "$(hand 21 | grep -c 'came back in two passes in a row')"
check "the hand-off's sections run findings so far, findings, tests per finding, rulings, touched tests (the round file's and rulings' own headings inside them)" \
  "Findings so far,What pass 21 found,Sol,Tests per finding,Main's rulings,1. RULING-PROBE: keep the probe,Cleared findings,Test files this build touched" \
  "$(hand 21 | sed -n 's/^## //p' | sed 's/ (.*//' | paste -sd, -)"
check "the touched-tests list names test files only, not a fixture beside them" "1 0" \
  "$(hand 21 | sed -n '/^## Test files/,$p' | grep -c 'y.test.sh') $(hand 21 | grep -c 'fixture.txt')"


echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
