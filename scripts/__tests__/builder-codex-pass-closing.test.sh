#!/usr/bin/env bash
# builder-codex-pass.sh closing passes: a class-tagged P1 main cleared does not block the merge; a change to hooks/
# asks for an executed probe; a red suite with an empty log still binds; and a pass before any decisions ledger
# carries no decisions block.
# The fixture is the one builder-codex-pass.test.sh uses.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

# The state these cases start from: a first pass.
printf 'echo built\n' > "$W/a.sh"
pass 1 adversarial
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 20 >/dev/null)

# Issue 225: each finding carries a class tag, and main's "Cleared findings" names a finding by its title and place
# alone: a tagged P1 main cleared blocks nothing, so the closing pass's P2 tail still merges.
printf '## Cleared findings\n- [P1] CLEAR-PROBE -- a.sh:1\n' >> "$REPO/.claude/briefs/$U-main-rulings.md"; printf 'echo fifteen\n' > "$W/a.sh"
(cd "$W" && COMMANDECK_MAIN=$REPO bash "$PASS_SH" --ack-rulings "$U" >/dev/null)
STUB_REPLY=$'- [P1] (class: lost-reply) CLEAR-PROBE -- a.sh:1 -- it breaks -- bash a.sh\nVERDICT: NO-GO' pass 15 final
check "a class-tagged P1 main cleared does not block the closing pass's merge" 0 "$(verify)"

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
check "a pass before any ledger carries no decisions block" 0 "$(input 17 | grep -c 'decisions that name this unit')"


echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
