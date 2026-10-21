#!/usr/bin/env bash
# run-shell-tests.sh --changed: the merge check ran all the shell tests on every
# merge, 12 minutes of wall clock, and two merges went red on a slow test's time
# alone. The check now runs only the tests the change touches: a touched test,
# and the same-name test of a touched script or hook. These cases pin that set.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
RUNNER=$REAL/scripts/run-shell-tests.sh
PASS=0 FAIL=0
# Run by hand from a Claude session the runner would detach itself (issue 230): these cases read its output here.
export COMMANDECK_FOREGROUND=1
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

# Issue 230: in main's own foreground (a Claude session in the main checkout) a run returns at once with its log,
# runs detached, and its result reaches main as a status message; the tests it runs are not main's foreground.
: > "$RAN"; printf '#!/usr/bin/env bash\necho "fg=$COMMANDECK_FOREGROUND" >> "$RAN"\n' > "$R/scripts/__tests__/touched.test.sh"
OUT=$(cd "$R" && env -u COMMANDECK_FOREGROUND CLAUDECODE=1 COMMANDECK_SCRATCH="$TMP/scratch" bash "$RUNNER" scripts/__tests__/touched.test.sh </dev/null 2>&1); RC=$?
PID=$(sed -n 's/.*running detached, pid \([0-9]*\);.*/\1/p' <<<"$OUT")
check "in main's foreground the run returns 0 at once, naming its log" "0 1" "$RC $(grep -c "log $TMP/scratch/shell-tests.log" <<<"$OUT")"
[ -z "$PID" ] || tail --pid="$PID" -f /dev/null
check "the detached run ran the test outside main's foreground, and main heard its result" "fg=1 1" \
  "$(cat "$RAN") $(cat "$TMP/scratch"/queue/*.jsonl 2>/dev/null | grep -c 'run-shell-tests.sh: exit 0')"
git -C "$R" checkout -q -- .

# Issue 268: the report showed a red file's last 12 lines, so a case that failed early went unnamed.
printf '#!/usr/bin/env bash\necho "FAIL EARLY-PROBE case"\nfor i in $(seq 30); do echo "ok   case $i"; done\nexit 1\n' > "$R/scripts/__tests__/touched.test.sh"
OUT=$(cd "$R" && timeout 30 bash "$RUNNER" scripts/__tests__/touched.test.sh 2>&1)
check "a red file's report names a case that failed before its last 12 lines" 1 "$(grep -c 'FAIL EARLY-PROBE case' <<<"$OUT")"
git -C "$R" checkout -q -- .

# Issue 282: a parked or own-lane file is skipped only on its marker in the first five lines; one further down runs.
printf '#!/usr/bin/env bash\n# parked: waits on a fix\necho parked >> "$RAN"\nexit 1\n' > "$R/scripts/__tests__/touched.test.sh"
printf '#!/usr/bin/env bash\n# own-lane: slow by design\necho lane >> "$RAN"\n' > "$R/scripts/__tests__/untouched.test.sh"
printf '#!/usr/bin/env bash\n#\n#\n#\n#\n# parked: too late to count\necho late >> "$RAN"\n' > "$R/scripts/__tests__/seat.test.sh"
: > "$RAN"; OUT=$(cd "$R" && timeout 30 bash "$RUNNER" scripts/__tests__/touched.test.sh scripts/__tests__/untouched.test.sh scripts/__tests__/seat.test.sh 2>&1); RC=$?
check "a parked file and an own-lane file are skipped with their reasons, and a marker past line 5 runs its file" "0 late 1 1" \
  "$RC $(sort "$RAN" | paste -sd' ' -) $(grep -c '^skip touched.test.sh *waits on a fix' <<<"$OUT") $(grep -c '^skip untouched.test.sh *own lane: slow by design' <<<"$OUT")"
: > "$RAN"; (cd "$R" && timeout 30 bash "$RUNNER" --own-lane scripts/__tests__/untouched.test.sh scripts/__tests__/seat.test.sh >/dev/null 2>&1)
check "--own-lane runs only the own-lane file" lane "$(cat "$RAN")"
git -C "$R" checkout -q -- .

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
