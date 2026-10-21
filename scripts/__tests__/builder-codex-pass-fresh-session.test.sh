#!/usr/bin/env bash
# builder-codex-pass.sh: a pass that ran long ends GO in a context grown through it, so the next round starts fresh;
# a commit after a closing GO makes the review over it the closing pass; and no fresh-round helper outlives the file.
# The fixture is the one builder-codex-pass.test.sh uses.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

# The state these cases start from: a first pass.
printf 'echo built\n' > "$W/a.sh"
pass 1 adversarial
printf 'handle=term_frs\ntask=task_frs\nunit=%s\nrole=builder\nsession=old-sid\n' "$U" > "$SC/seat-$U-builder.txt"
# The cleared session's own log names the hand-off too (it read the pass's output); it is not the new one.
mkdir -p "$PROJ"; echo "$B/$U-fix-r7.md" > "$PROJ/old-sid.jsonl"; touch -t 209901010000 "$PROJ/old-sid.jsonl"
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 40 >/dev/null)

# Issue 302: a pass that ran long ends GO in a context grown through it; the next round starts fresh as after a NO-GO.
rm -f "$TMP/frs-calls"; printf 'echo twenty-two\n' > "$W/a.sh"
check "a GO after a long pass writes the continue hand-off and starts the helper" "0 1 1" \
  "$(fpass "$W" 22 review 'VERDICT: GO' COMMANDECK_LONG_PASS_SECONDS=0) $(grep -c 'Pass 22 ended GO; continue from the evidence file' "$B/$U-after-r22.md" 2>/dev/null) $(grep -c '^FRESH SESSION after pass 22: end your turn now' "$TMP/out")"
for _ in $(seq 100); do grep -q 'now names\|stays in' "$SC/$U-after-r22.log" 2>/dev/null && break; sleep 0.1; done
check "and the helper typed the pointer to it" 1 "$(grep -cF "Your task spec is the file $B/$U-after-r22.md." "$TMP/frs-calls")"
# A closing GO, then a commit after it: the review over it runs as final.
printf 'echo twenty-three\n' > "$W/a.sh"; fpass "$W" 23 final 'VERDICT: GO' >/dev/null
printf 'echo twenty-four\n' > "$W/a.sh"
check "a commit after a closing GO: review runs as final" "0 1" "$(fpass "$W" 24 review 'VERDICT: GO') $(grep -cx 'Pass: final' "$B/$U-r24-reports.md")"
wait
check "no fresh-round helper of this file is left running" 0 "$(pgrep -f "$TMP/" | grep -vx "$$" | wc -l | tr -d ' ')"


echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
