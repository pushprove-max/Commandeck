#!/usr/bin/env bash
# run-shell-tests.sh --changed: the merge check ran all the shell tests on every
# merge, 12 minutes of wall clock, and two merges went red on a slow test's time
# alone. The check now runs only the tests the change touches: a touched test,
# and the same-name test of a touched script or hook. These cases pin that set.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
RUNNER=$REAL/scripts/run-shell-tests.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# A project with two tests, one script with its same-name test, and a README.
R=$TMP/repo; mkdir -p "$R/scripts/__tests__" "$R/hooks/__tests__"
for t in touched untouched seat; do
  printf '#!/usr/bin/env bash\necho %s >> "$RAN"\n' "$t" > "$R/scripts/__tests__/$t.test.sh"
done
echo 'echo seat' > "$R/scripts/seat.sh"; echo readme > "$R/README.md"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -qm base
export RAN=$TMP/ran
# Runs --changed in the project with the given args; GOT is the sorted tests that ran, space-joined.
ran() { : > "$RAN"; OUT=$(cd "$R" && timeout 30 bash "$RUNNER" --changed "$@" 2>&1); RC=$?; GOT=$(sort "$RAN" | paste -sd" " -); }

echo '# edited' >> "$R/scripts/__tests__/touched.test.sh"; echo '# edited' >> "$R/scripts/seat.sh"
ran
check "a touched test and a touched script's same-name test run, and no other" "seat touched" "$GOT"
check "... and the run passes" 0 "$RC"

git -C "$R" checkout -q -- . && echo edited >> "$R/README.md"
ran
check "a change touching no test or script runs none" "" "$GOT"
check "... exits 0 and says so in one line" "0 1" "$RC $(grep -c 'no shell test was touched' <<<"$OUT")"

git -C "$R" checkout -q -- . && git -C "$R" rm -q scripts/__tests__/untouched.test.sh scripts/seat.sh
ran
check "a deleted test or script selects nothing" "" "$GOT"
git -C "$R" reset -q && git -C "$R" checkout -q -- .

# A base git cannot resolve is an error, never a green run of nothing.
ran no-such-base
check "an unknown base fails" 2 "$RC"

# A git diff that fails is an error, never a green run of nothing.
echo '# edited' >> "$R/scripts/seat.sh"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=diff.renames GIT_CONFIG_VALUE_0=invalid ran
check "a failed diff fails, running nothing" "2 " "$RC $GOT"
git -C "$R" checkout -q -- .

# A test module (.test.mjs) runs through its shell wrapper of the same name: an edit to the module alone ran nothing.
printf '#!/usr/bin/env bash\necho view >> "$RAN"\n' > "$R/scripts/__tests__/view.test.sh"; echo '// view' > "$R/scripts/__tests__/view.test.mjs"
echo '// lone' > "$R/hooks/__tests__/lone.test.mjs"
git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -qm modules
echo '// edited' >> "$R/scripts/__tests__/view.test.mjs"; echo '// edited' >> "$R/hooks/__tests__/lone.test.mjs"
ran
check "an edited test module runs its wrapper; one with no wrapper selects nothing" "view" "$GOT"
git -C "$R" checkout -q -- .

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
