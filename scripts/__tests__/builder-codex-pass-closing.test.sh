#!/usr/bin/env bash
# builder-codex-pass.sh closing passes: every finding, P0 to P3, blocks the merge, cleared or not; a change to hooks/
# asks for an executed probe; a red suite with an empty log still binds; and a pass before any decisions ledger
# carries no decisions block.
# The fixture is the one builder-codex-pass.test.sh uses.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

# The state these cases start from: a first pass.
printf 'echo built\n' > "$W/a.sh"
pass 1 adversarial
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 20 >/dev/null)

# Every finding, P0 to P3, blocks the merge: no P2 tail merges with findings open and filed later as debt.
# Main's "Cleared findings" names a finding by its title and place alone, and is handed to the next reviewer as
# out of scope; a cleared finding never turns a NO-GO into a merge. Source: main's answer 1 in this unit's plan
# (.claude/plans/p2-tail-322-2026-10-22.md, "Main answers"). CLEAR-PROBE exempts nothing: the cases below prove
# the cleared NO-GO is still refused, and the clearance only reaches the next reviewer's prompt.
printf '## Cleared findings\n- [P1] CLEAR-PROBE -- a.sh:1\n' >> "$REPO/.claude/briefs/$U-main-rulings.md"; printf 'echo two\n' > "$W/a.sh"
(cd "$W" && COMMANDECK_MAIN=$REPO bash "$PASS_SH" --ack-rulings "$U" >/dev/null)
STUB_REPLY=$'- [P2] (class: probe) CLEAR-PROBE -- a.sh:1 -- wrong -- bash a.sh\nVERDICT: NO-GO' pass 2 final
check "a closing NO-GO whose every finding main cleared is refused, with no closing GO proof" "2 0" "$(verify) $(grep -c 'closing GO' "$TMP/vout")"
printf 'echo three\n' > "$W/a.sh"
STUB_REPLY=$'- [P2] (class: probe) P2-PROBE -- a.sh:1 -- wrong -- bash a.sh\nVERDICT: NO-GO' pass 3 review
check "after a closing NO-GO, the next review runs as the closing pass and hands on the cleared finding as not to list" "1 1 1" \
  "$(grep -c '^final in place of review: the closing pass .* ended NO-GO' "$TMP/out") $(grep -cx 'Pass: final' "$B/$U-r3-reports.md") \
$(input 3 | sed -n '/A finding inside a stated limit is not a finding: do not list it:/,/^$/p' | grep -c 'CLEAR-PROBE -- a.sh:1')"
check "a closing NO-GO with only P2 findings is refused" 2 "$(verify)"
printf 'echo four\n' > "$W/a.sh"
STUB_REPLY=$'- [P3] (class: probe) P3-PROBE -- a.sh:1 -- a nit -- bash a.sh\nVERDICT: NO-GO' pass 4 review
check "a closing NO-GO with only a P3 is refused" 2 "$(verify)"
printf 'echo five\n' > "$W/a.sh"
STUB_REPLY=$'- [P3] (class: probe) P3-PROBE -- a.sh:1 -- a nit -- bash a.sh\nVERDICT: GO' pass 5 review
check "a closing GO that names a P3 is a NO-GO round and is refused" "1 2" "$(tail -1 "$B/$U-r5-reports.md" | grep -cx 'VERDICT: NO-GO') $(verify)"
printf 'echo six\n' > "$W/a.sh"
STUB_REPLY=$'- [P1] (class: probe) P1-PROBE -- a.sh:1 -- it breaks -- bash a.sh\nVERDICT: NO-GO' pass 6 review
check "a closing pass with a P1 is refused" 2 "$(verify)"
# Markdown around the severity tag is still a finding: the report reads it in the plain form every reader greps,
# and a GO beside a tag the plain form cannot be made from (here inside the brackets) is a NO-GO too.
printf 'echo seven\n' > "$W/a.sh"
STUB_REPLY=$'- **[P3]** (class: probe) BOLD-PROBE -- a.sh:1 -- a nit -- bash a.sh\nVERDICT: GO' pass 7 review
check "a closing GO that names a bold P3 is a NO-GO round, its finding in plain form, and is refused" "1 1 2" \
  "$(tail -1 "$B/$U-r7-reports.md" | grep -cx 'VERDICT: NO-GO') $(grep -c '^- \[P3\] (class: probe) BOLD-PROBE' "$B/$U-r7-reports.md") $(verify)"
printf 'echo eight\n' > "$W/a.sh"
STUB_REPLY=$'1. [**P2**] (class: probe) ODD-PROBE -- a.sh:1 -- wrong -- bash a.sh\n+ [P2] (class: probe) PLUS-PROBE -- a.sh:1 -- wrong -- bash a.sh\n@ AT-PROBE full 1 1 1 - - x whole GO P2\nVERDICT: GO' pass 8 review
check "a closing GO beside a severity tag in any other form is a NO-GO round and is refused" "1 2" \
  "$(tail -1 "$B/$U-r8-reports.md" | grep -cx 'VERDICT: NO-GO') $(verify)"
printf 'echo nine\n' > "$W/a.sh"
STUB_REPLY=$'* `[P2]` (class: probe) TICK-PROBE -- a.sh:1 -- wrong -- bash a.sh\nVERDICT: GO' pass 9 review
check "a closing GO beside a code-span P2 is a NO-GO round, its finding in plain form, and is refused" "1 1 2" \
  "$(tail -1 "$B/$U-r9-reports.md" | grep -cx 'VERDICT: NO-GO') $(grep -c '^- \[P2\] (class: probe) TICK-PROBE' "$B/$U-r9-reports.md") $(verify)"
printf 'echo ten\n' > "$W/a.sh"
STUB_REPLY=$'### P1: HEAD-PROBE -- a.sh:1 -- it breaks -- bash a.sh\nVERDICT: GO' pass 10 review
check "a closing GO beside a heading that names a P1 is a NO-GO round and is refused" "1 2" \
  "$(tail -1 "$B/$U-r10-reports.md" | grep -cx 'VERDICT: NO-GO') $(verify)"
# r2: the gate is a fixed rule, not a model of Markdown: a level token or a class tag on any line but the verdict
# is a finding, however it is wrapped or wherever it sits.
n=11
for f in '- [__P2__] (class: probe) US-PROBE -- a.sh:1 -- wrong -- bash a.sh' \
  '__[P2]__ (class: probe) US2-PROBE -- a.sh:1 -- wrong -- bash a.sh' \
  'Finding: (P1) MID-PROBE -- a.sh:1 -- it breaks -- bash a.sh' \
  '- (class: probe) NOLEVEL-PROBE -- a.sh:1 -- wrong -- bash a.sh'; do
  printf 'echo %s\n' "$n" > "$W/a.sh"
  STUB_REPLY="$f"$'\nVERDICT: GO' pass $n review
  check "a closing GO beside a finding in another form is a NO-GO round and is refused: $f" "1 2" \
    "$(tail -1 "$B/$U-r$n-reports.md" | grep -cx 'VERDICT: NO-GO') $(verify)"
  n=$((n + 1))
done
check "an underscore-wrapped P2 reaches the report in plain form" 1 "$(grep -c '^- \[P2\] (class: probe) US-PROBE' "$B/$U-r11-reports.md")"
printf 'echo fifteen\n' > "$W/a.sh"
STUB_REPLY='VERDICT: GO' pass 15 review
# r4: what the gate counts is what the next reviewer is handed, so a finding in any form reaches it and the merge's
# check of what was handed on; a numbered or plus-marked finding reads as a "- " one, as every reader of the report greps.
check "every earlier finding the gate counted, in any form, reaches the next reviewer" "1 1 1 1 1 1 1" \
  "$(for r in '^- \[P2\] (class: probe) ODD-PROBE' '^- \[P2\] (class: probe) PLUS-PROBE' '^- \[P2\] (class: probe) TICK-PROBE' \
  '^### P1: HEAD-PROBE' '^\[P2\] (class: probe) US2-PROBE' '^Finding: (P1) MID-PROBE' '^- (class: probe) NOLEVEL-PROBE'; do
  input 15 | grep -c "$r"; done | paste -sd' ' -)"
check "a finding line that opens with @ is handed on escaped, never as an earlier pass of its own" "1 0" \
  "$(input 15 | grep -c '^\\@ AT-PROBE') $(input 15 | grep -c '^Earlier pass AT-PROBE')"
check "a closing GO with nothing named merges: rule closing GO, no Open at merge line" "0 1 0" \
  "$(verify) $(grep -c 'rule: closing GO$' "$TMP/vout") $(grep -c 'Open at merge' "$TMP/vout")"

# Issue 250: a change to a hook is checked by running it; the pass prompt names the probe script only then.
mkdir -p "$W/hooks" && printf 'exit 0\n' > "$W/hooks/h.sh"
pass 16 review
check "a pass over a change to hooks/ asks for an executed probe; one with no hook change does not" "1 0" \
  "$(grep -c 'hook-probe.sh <hook>' "$B/$U-r16-prompt-1.md") $(grep -c 'hook-probe.sh' "$B/$U-r15-prompt-1.md")"

# r1: a red run that printed nothing still binds: the NO-GO follows the run's exit, not its log text.
cfg '.fullSuiteBeforeFinal = true | .testCommand = "exit 1"'; printf 'echo seventeen\n' > "$W/a.sh"
pass 17 final
check "a red suite with an empty log: the round file ends NO-GO, though the reviewer said GO" "1 1" \
  "$(tail -1 "$B/$U-r17-reports.md" | grep -cx 'VERDICT: NO-GO') $(grep -c 'The full suite is red on .*exit 1' "$B/$U-r17-reports.md")"
# r12: a green run that rewrote a tracked file tested a tree the tip does not hold; restoring the file after the
# pass must not leave a "pass" line the merge would reuse.
cfg '.testCommand = "printf mutated > a.sh; test \"$(cat a.sh)\" = mutated"'; printf 'echo eighteen\n' > "$W/a.sh"
pass 18 final
git -C "$W" checkout -q -- a.sh
check "a green suite that changed tracked files: no pass line, the round ends NO-GO, and --verify refuses" "0 1 1 2" \
  "$(grep -c '^Suite: [0-9a-f]* pass ' "$B/$U-r18-reports.md") $(grep -c '^Suite: [0-9a-f]* changed ' "$B/$U-r18-reports.md") \
$(tail -1 "$B/$U-r18-reports.md" | grep -cx 'VERDICT: NO-GO') $(verify)"
cfg 'del(.fullSuiteBeforeFinal)'
# Issue 325 (owner ruling of 2026-10-23): only a bug normal use would hit blocks the merge. A bypass or
# odd-setup finding is a plain known-gap line (no level, no class tag), so a closing GO that names one still merges;
# a finding normal use hits stays a NO-GO, known gaps beside it or not.
printf 'echo nineteen\n' > "$W/a.sh"
STUB_REPLY=$'KNOWN GAPS:\n- GAP-PROBE -- a.sh:1 -- needs an agent that edits the guard by hand\nVERDICT: GO' pass 19 review
check "a closing GO that names only a known gap ends GO, merges, and the report keeps the gap" "1 0 1 1" \
  "$(tail -1 "$B/$U-r19-reports.md" | grep -cx 'VERDICT: GO') $(verify) $(grep -c '^- GAP-PROBE' "$B/$U-r19-reports.md") $(grep -c '^KNOWN GAPS:' "$B/$U-r19-reports.md")"
printf 'echo twenty\n' > "$W/a.sh"
STUB_REPLY=$'- [P2] (class: probe) NORMAL-PROBE -- a.sh:1 -- plain use breaks -- bash a.sh\nKNOWN GAPS:\n- GAP-PROBE -- a.sh:1 -- odd setup\nVERDICT: GO' pass 20 review
check "a normal-use finding beside a known gap is a NO-GO round and is refused" "1 2" \
  "$(tail -1 "$B/$U-r20-reports.md" | grep -cx 'VERDICT: NO-GO') $(verify)"
check "the reviewer's prompt states the rule: normal use blocks, bypass and odd setup go under KNOWN GAPS:" "1 0" \
  "$(grep -c 'blocks the merge only when normal use would hit the bug.*KNOWN GAPS:' "$B/$U-r20-prompt-1.md") $(grep -c 'Every finding, P0 to P3, blocks the merge' "$B/$U-r20-prompt-1.md")"
check "a pass before any ledger carries no decisions block" 0 "$(input 17 | grep -c 'decisions that name this unit')"


echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
