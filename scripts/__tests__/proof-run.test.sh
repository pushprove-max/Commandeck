#!/usr/bin/env bash
# proof-run.test.sh -- the proof run's numbers are what a release is compared
# by, so the harness must print every measure for both profiles, must not let
# an unmeasured row read as a number, and must fail when a measured row
# breaks: a harness that always says "holds" proves nothing. What this pins:
# the rows, their limits, exit 0 on this tree, and exit 1 with the broken row
# named when the plugin it measures does not uninstall.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

bash "$ROOT/scripts/proof-run.sh" >"$T/out" 2>&1; check "the proof run exits 0 on this tree" 0 $?
check "it says every measured row holds" 1 "$(grep -c '^proof run: every measured row holds$' "$T/out")"
for p in claude claude-openai; do
  rows() { grep -c "^$p  *$1" "$T/out"; }
  check "$p: startup bytes for the four seats" 4 "$(rows 'startup bytes, \(main\|builder\|worker\|chief-of-staff\)  *[0-9][0-9]* (limit 10240)$')"
  check "$p: every startup number is under the line" 0 "$(grep "^$p  *startup bytes" "$T/out" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/ && $(i + 1) == "(limit") n = $i; if (n + 0 >= 10240 || n == "") bad++ } END { print bad + 0 }')"
  check "$p: the per-prompt bytes" 1 "$(rows 'per-prompt bytes, largest seat  *[0-9][0-9]* (limit 10240)$')"
  check "$p: hook cost from real fires, with the refused call counted" 1 "$(rows 'hook cost, all hooks  *[1-9][0-9]* hooks, [1-9][0-9]* fires, [1-9][0-9]* blocks, [0-9]* retried identical, slowest p95 [0-9]* ms$')"
  # The harness sends one refused call twice: two blocks, and the second is the first retried.
  check "$p: hook cost per hook, with the retry counted" 1 "$(rows '  hook  *git-safety.sh: [0-9]* fires, 2 blocks, 1 retried identical')"
  check "$p: the 150K line fires for a standard-context project" 1 "$(rows 'standard context, 150K line  *fires at 160K$')"
  check "$p: the other tool's parts are identical while installed" 1 "$(rows 'coexistence while installed  *the other tool.*identical')"
  check "$p: uninstall with the data kept" 1 "$(rows 'uninstall, data kept  *identical but for the kept data')"
  check "$p: uninstall with the data deleted" 1 "$(rows 'uninstall, data deleted  *identical$')"
  # No model runs in the harness: these four must say so, never a number.
  check "$p: the rows that need a live unit say they were not measured" 4 \
    "$(rows '\(tokens and turns per role\|cache hit rate and write share\|review passes to GO, findings\|standard context, restart resumes\)  *not measured: no model runs here')"
done
check "the stand-in is named as one" 2 "$(grep -c 'a stand-in: not this machine' "$T/out")"

# --- a plugin that does not uninstall: the row says so and the run fails ---
mkdir "$T/broken"
for d in hooks scripts config templates dashboard skills .claude-plugin CHANGELOG.md; do cp -R "$ROOT/$d" "$T/broken/"; done
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/broken/scripts/uninstall.sh"
bash "$T/broken/scripts/proof-run.sh" --profile claude >"$T/out2" 2>&1; check "a plugin whose uninstall does nothing fails the proof run" 1 $?
check "the broken row is named" 1 "$(grep -c '^claude  *uninstall, data deleted  *DIFFERS: ' "$T/out2")"
check "and the last line says a row failed" 1 "$(tail -1 "$T/out2" | grep -c 'FAILED')"
check "one profile was asked for and one was run" 0 "$(grep -c '^claude-openai ' "$T/out2")"

[ "$FAIL" = 0 ] || { echo "--- output"; cut -c1-240 "$T/out"; }
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
