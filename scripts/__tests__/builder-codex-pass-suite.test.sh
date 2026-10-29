#!/usr/bin/env bash
# builder-codex-pass.sh: a diff past the reviewer's input limit goes as a file list; with fullSuiteBeforeFinal on,
# the closing pass runs the full suite first, a red run is its NO-GO and --verify takes a closing GO only with a
# green line; and the pass prompt asks for each finding's class.
# The fixture is the one builder-codex-pass.test.sh uses.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

# The state these cases start from: a first pass.
printf 'echo built\n' > "$W/a.sh"
pass 1 adversarial

# A diff past the reviewer's input limit is not pasted (Codex refuses an input over its limit, and the pass ended with no
# review): the prompt holds the file list and how to read each file, and none of the diff body. Same range, same pass.
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 11 >/dev/null)
printf 'echo eleven-BODY-PROBE\n' > "$W/a.sh"
(cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-11 COMMANDECK_PASS_DIFF_HARD=50 bash "$PASS_SH" "$U" 11 review >"$TMP/out" 2>"$TMP/err") \
  || { echo "FAIL the over-limit pass r11 did not run: $(cat "$TMP/err")"; FAIL=$((FAIL+1)); }
check "a diff over the input limit goes as a file list with the read instruction, and none of the diff body" "1 1 0" \
  "$(input 11 | grep -c '^a.sh') $(input 11 | grep -cF ": git diff ") $(input 11 | grep -c 'BODY-PROBE')"
# The Claude reviewer's git wrapper refuses -C before the subcommand (exit 2), and both reviewers run in the worktree.
check "the read instruction has no git -C, which the reviewer's git wrapper refuses" 0 "$(input 11 | grep -cF 'git -C')"

# Issue 243: with fullSuiteBeforeFinal on in main's config, the closing pass runs the merge check's own command whole
# (--changed taken off) on its tip first. Its line is in the prompt and the round file; a red run is the pass's NO-GO,
# naming what failed; and --verify takes a closing GO only with a green line for the commit it read.
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 20 >/dev/null)
printf '#!/usr/bin/env bash\necho "args:$*"\necho "3 passed, 0 failed"\n' > "$TMP/suite-ok.sh"
printf '#!/usr/bin/env bash\necho "FAIL red-probe.test.sh"\necho "2 passed, 1 failed"\nexit 1\n' > "$TMP/suite-red.sh"
printf 'echo twelve\n' > "$W/a.sh"
pass 12 final
check "the setting off: no suite runs, no Suite line, and a closing GO verifies" "0 0 0" \
  "$(grep -c '^Suite: ' "$B/$U-r12-reports.md") $(input 12 | grep -c '^Suite: ') $(verify)"
cfg '.fullSuiteBeforeFinal = true'
check "the setting on, a closing GO with no Suite line is refused by --verify" "2 1" "$(verify) $(grep -c 'no green full-suite line' "$TMP/verr")"
cfg 'del(.testCommand)'; printf 'echo thirteen\n' > "$W/a.sh"; HEAD13=$(git -C "$W" rev-parse HEAD)
(cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-13 bash "$PASS_SH" "$U" 13 final >"$TMP/out" 2>"$TMP/err"); RC=$?
check "the setting on with no test command: the closing pass refuses, naming the setting, and commits nothing" "2 1 $HEAD13" \
  "$RC $(grep -c 'fullSuiteBeforeFinal is on' "$TMP/err") $(git -C "$W" rev-parse HEAD)"
cfg ".testCommand = \"bash $TMP/suite-ok.sh --changed\""
pass 13 final; SHA13=$(git -C "$W" rev-parse HEAD)
check "a green suite: its line is in the round file and first in the prompt, the run had no --changed" "1 1 1 0" \
  "$(grep -c "^Suite: $SHA13 pass 3 passed, 0 failed [0-9]*s $TMP/scratch/$U-suite-${SHA13:0:8}.log cmd:$(cksum <<<"bash $TMP/suite-ok.sh --changed" | cut -d' ' -f1)\$" "$B/$U-r13-reports.md") \
$(input 13 | sed -n 2p | grep -c "^Suite: $SHA13 pass ") $(grep -cx 'args:' "$TMP/scratch/$U-suite-${SHA13:0:8}.log") $(grep -c -- '--changed' "$TMP/scratch/$U-suite-${SHA13:0:8}.log")"
check "and the closing GO with its green line verifies" 0 "$(verify)"
# Issue 307: --verify prints the line it read from the pass's own recorded prompt; the merge reuses that copy only.
check "--verify prints that line as its Suite proof" 1 "$(grep -c "^Suite proof: Suite: $SHA13 pass 3 passed" "$TMP/vout")"
cfg ".testCommand = \"bash $TMP/suite-red.sh\""; printf 'echo fourteen\n' > "$W/a.sh"
pass 14 final
check "a red suite: the round file ends NO-GO and names the failing test, though the reviewer said GO" "1 1 1" \
  "$(tail -1 "$B/$U-r14-reports.md" | grep -cx 'VERDICT: NO-GO') $(grep -c 'red-probe.test.sh' "$B/$U-r14-reports.md") $(grep -c '^Suite: [0-9a-f]* fail ' "$B/$U-r14-reports.md")"
check "and --verify refuses the reviewer's GO on that red run" 2 "$(verify)"
cfg 'del(.fullSuiteBeforeFinal)'

# Issue 225: each finding carries a class tag, the same tag for the same kind in every pass.
check "the pass prompt asks for each finding's class" 1 "$(grep -c '\[P<0-3>\] (class: <tag>) <title>' "$B/$U-r14-prompt-1.md")"
# Host change (owner order 2026-10-25): the reviewer is asked for the search class_sites runs, under blocking findings only.
check "the pass prompt asks for a Class search line under each blocking finding" "1 1 1" \
  "$(grep -c 'Under each blocking finding write one line, Class search: rg <arguments>, a read-only rg search run from the repository root whose hits are every place with the same mistake' "$B/$U-r14-prompt-1.md") \
$(grep -c 'the <file>:<line> of that finding among them; the author must answer for each hit' "$B/$U-r14-prompt-1.md") \
$(grep -c 'A known gap carries no Class search line' "$B/$U-r14-prompt-1.md")"

# A final refused for its missing sites section, then for its new-code check, then for its missing test command cost a fix
# round each: all three are named in one refusal. Pass 14 ended NO-GO and no evidence section is written for it.
cfg '.fullSuiteBeforeFinal = true'; cfg 'del(.testCommand)'; printf 'echo fifteen\n' > "$W/a.sh"; HEAD15=$(git -C "$W" rev-parse HEAD)
(cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-15 bash "$PASS_SH" "$U" 15 final >"$TMP/out" 2>"$TMP/err"); RC=$?
check "a final after a NO-GO with no evidence and no test command lists all three refusals at once (issue 451)" "2 1 3 1 1 1 $HEAD15" \
  "$RC $(grep -cx 'REFUSED: 3 checks failed:' "$TMP/err") $(grep -c '^- ' "$TMP/err") $(grep -c "^- pass 14 ended NO-GO, and .* has no usable '## Sites checked (pass 14)' section" "$TMP/err") \
$(grep -c "^- pass 14 ended NO-GO, and .* has no usable '## New code checked (pass 14)' section" "$TMP/err") $(grep -c '^- fullSuiteBeforeFinal is on' "$TMP/err") $(git -C "$W" rev-parse HEAD)"
cfg 'del(.fullSuiteBeforeFinal)'; cfg ".testCommand = \"bash $TMP/suite-red.sh\""


echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
