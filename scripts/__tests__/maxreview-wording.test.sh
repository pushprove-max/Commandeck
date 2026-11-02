#!/usr/bin/env bash
# #533: the maxreview skill reads the review wording live from scripts/builder-codex-pass.sh, so a hand-written copy
# cannot drift from the wording the Builder passes use. wording.sh runs only the lines between the pass script's
# `# wording: begin` and `# wording: end` markers; a missing or doubled marker, or a renamed wording variable, is
# refused, never answered from a hand-written fallback. SKILL.md holds the loop the issue states.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
WORDING=$REAL/skills/maxreview/wording.sh SKILL=$REAL/skills/maxreview/SKILL.md PASS_SH=$REAL/scripts/builder-codex-pass.sh
# wording <kind> [root]: the helper with the three variables the pass script sets outside the markers unset, as set -u needs them.
wording() { env -u BLOCK_LEVELS -u OPEN -u CLOSE bash "$WORDING" "$@"; }
# A copy of the repo's pass script and test rules, which the wording block reads.
mkcopy() { mkdir -p "$T/$1/scripts" "$T/$1/templates"; cp "$PASS_SH" "$T/$1/scripts/"; cp "$REAL/templates/test-rules.md" "$T/$1/templates/"; }

ADV=$(wording adversarial "$REAL" 2>"$T/aerr"); ARC=$?
check "wording.sh adversarial prints the live angles" "0 1 1 1 1" \
  "$ARC $(grep -c '^Angle 1 of 3, bypass and trust' <<<"$ADV") $(grep -c '^Angle 3 of 3, tests and words' <<<"$ADV") \
$(grep -c 'Is there a smaller change that fully solves the problem' <<<"$ADV") $(grep -c 'Class search: rg' <<<"$ADV")"
REV=$(wording review "$REAL" 2>"$T/rerr"); RRC=$?
check "wording.sh review prints the closing focus" "0 1 0 1" \
  "$RRC $(grep -c '^Correctness bugs, security problems and missing tests in the changed lines\.' <<<"$REV") $(grep -c '^Angle 1 of 3' <<<"$REV") \
$(grep -c 'List every finding you can defend' <<<"$REV")"

mkdir -p "$T/empty"
wording adversarial "$T/empty" >/dev/null 2>"$T/eerr"; ERC=$?
check "wording.sh refuses a folder with no pass script" "2 1" "$ERC $(grep -c 'REFUSED' "$T/eerr")"

# The guard: a wording variable renamed in the pass script (or a block with no ANGLES) is an error, not an empty answer.
mkcopy ren; sed 's/^LENS=/LENS_RENAMED=/' "$PASS_SH" > "$T/ren/scripts/builder-codex-pass.sh"
wording review "$T/ren" >"$T/rout" 2>"$T/rnerr"; RNC=$?
mkcopy ang; sed 's/^ANGLES=(/ANGLES_RENAMED=(/' "$PASS_SH" > "$T/ang/scripts/builder-codex-pass.sh"
wording adversarial "$T/ang" >/dev/null 2>"$T/anerr"; ANC=$?
check "a renamed wording variable breaks the guard" "2 0 2" "$RNC $(wc -c < "$T/rout" | tr -d ' ') $ANC"

# The markers: exactly one of each, begin first; the block holds the wording variables and not FORMAT.
BEGIN=$(grep -c '^# wording: begin$' "$PASS_SH"); END=$(grep -c '^# wording: end$' "$PASS_SH")
BL=$(grep -n '^# wording: begin$' "$PASS_SH" | cut -d: -f1); EL=$(grep -n '^# wording: end$' "$PASS_SH" | cut -d: -f1)
LL=$(grep -n '^LENS=' "$PASS_SH" | cut -d: -f1); FL=$(grep -n '^FORMAT=' "$PASS_SH" | cut -d: -f1)
mkcopy dbl; sed 's/^# wording: end$/&\n# wording: end/' "$PASS_SH" > "$T/dbl/scripts/builder-codex-pass.sh"
wording review "$T/dbl" >/dev/null 2>"$T/dberr"; DBC=$?
mkcopy non; grep -v '^# wording: begin$' "$PASS_SH" > "$T/non/scripts/builder-codex-pass.sh"
wording review "$T/non" >/dev/null 2>"$T/nnerr"; NNC=$?
check "the pass script carries one begin and one end wording marker" "1 1 yes yes 2 2" \
  "$BEGIN $END $([ "${BL:-0}" -lt "${LL:-0}" ] && [ "${LL:-0}" -lt "${EL:-0}" ] && echo yes || echo no) \
$([ "${FL:-0}" -lt "${BL:-0}" ] && echo yes || echo no) $DBC $NNC"

# The loop the issue states, in SKILL.md.
check "the skill names adversarial-review for every round" "1 1" \
  "$(grep -c 'codex-companion.mjs adversarial-review --base' "$SKILL") $(grep -c 'Every round, not only the first' "$SKILL")"
check "the skill holds the proof bar at intake" "1" \
  "$(grep -ci 'no exact failing input or command.*dropped' "$SKILL")"
check "the skill stops for the owner on a user-visible fix" "1" \
  "$(grep -ci 'anything users see.*stop.*owner.*before and after' "$SKILL")"
check "the skill keeps fast-lane review for a Fast-lane worktree" "1" \
  "$(grep -c 'Fast-lane worktree.*scripts/fast-lane.sh review' "$SKILL")"
check "the skill writes its record ending VERDICT: GO" "1 1" \
  "$(grep -c 'maxreview-r<N>-reports.md' "$SKILL") $(grep -c 'VERDICT: GO' "$SKILL")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
