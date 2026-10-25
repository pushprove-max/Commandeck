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

# The merge-queue tests were split in five to fit the time cap; the four not named after merge-queue.sh carry
# `# covers:` so a change to it alone still runs all five. Each fixture test keeps the real file's header comments.
for t in "$REAL"/scripts/__tests__/merge-queue*.test.sh; do
  n=$(basename "$t" .test.sh); { sed -n '1,5{/^#/p}' "$t"; echo "echo $n >> \"\$RAN\""; } > "$R/scripts/__tests__/$n.test.sh"
done
echo 'echo queue' > "$R/scripts/merge-queue.sh"
git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -qm queue
echo '# edited' >> "$R/scripts/merge-queue.sh"
ran
check "an edit to merge-queue.sh alone runs all five merge-queue tests, and no other" \
  "merge-queue merge-queue-glob merge-queue-listing merge-queue-train merge-queue-train-detach" "$GOT"
git -C "$R" checkout -q -- .

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
# runs detached, and its result reaches main as a question; the tests it runs are not main's foreground.
: > "$RAN"; printf '#!/usr/bin/env bash\necho "fg=$COMMANDECK_FOREGROUND" >> "$RAN"\n' > "$R/scripts/__tests__/touched.test.sh"
OUT=$(cd "$R" && env -u COMMANDECK_FOREGROUND CLAUDECODE=1 COMMANDECK_SCRATCH="$TMP/scratch" bash "$RUNNER" scripts/__tests__/touched.test.sh </dev/null 2>&1); RC=$?
PID=$(sed -n 's/.*running detached as pid \([0-9]*\);.*/\1/p' <<<"$OUT")
check "in main's foreground the run returns 0 at once, naming its log" "0 1" "$RC $(grep -c "watch $TMP/scratch/shell-tests.log" <<<"$OUT")"
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

# The merge check runs in main's environment, which main-watch and the session give a real pane folder, scratch and
# seat: relay-order.test.sh, green in a Builder's pane, went red at merge (its stub pane was looked for in main's
# checkout). A test sees only the COMMANDECK_ variables CI gives it and the runner's own, as in CI.
printf '#!/usr/bin/env bash\necho "pane=${COMMANDECK_MAIN_PANE_DIR-} scratch=${COMMANDECK_SCRATCH-} seat=${COMMANDECK_SEAT-} nm=${COMMANDECK_TEST_NODE_MODULES-} fg=$COMMANDECK_FOREGROUND" >> "$RAN"\n' \
  > "$R/scripts/__tests__/touched.test.sh"
: > "$RAN"; (cd "$R" && COMMANDECK_MAIN_PANE_DIR=/real/main COMMANDECK_SCRATCH=/real/scratch COMMANDECK_SEAT=main \
  COMMANDECK_TEST_NODE_MODULES=/ci/nm timeout 30 bash "$RUNNER" scripts/__tests__/touched.test.sh >/dev/null 2>&1)
check "a test inherits no session or main-watch COMMANDECK_ variable; CI's and the runner's reach it" \
  "pane= scratch= seat= nm=/ci/nm fg=1" "$(cat "$RAN")"
git -C "$R" checkout -q -- .

# Host issue 3009: a test with no orca-ide stub of its own once closed a real pane. The runner puts a stub first on
# PATH that refuses `terminal close` and names the test file; a test's own stub, prepended later, still wins.
printf '#!/usr/bin/env bash\norca-ide terminal close --terminal h1 --json >> "$RAN" 2>&1; echo "rc=$?" >> "$RAN"\n' > "$R/scripts/__tests__/touched.test.sh"
: > "$RAN"; (cd "$R" && timeout 30 bash "$RUNNER" scripts/__tests__/touched.test.sh >/dev/null 2>&1)
check "a test without its own stub cannot close a pane: refused, the test file named" "1 1 rc=1" \
  "$(grep -c '"test-unstubbed-close"' "$RAN") $(grep -c "refused in .*scripts/__tests__/touched.test.sh" "$RAN") $(grep '^rc=' "$RAN")"
mkdir -p "$TMP/own"; printf '#!/usr/bin/env bash\necho own-stub\n' > "$TMP/own/orca-ide"; chmod +x "$TMP/own/orca-ide"
printf '#!/usr/bin/env bash\nPATH=%s/own:$PATH orca-ide terminal close --terminal h1 >> "$RAN" 2>&1\n' "$TMP" > "$R/scripts/__tests__/touched.test.sh"
: > "$RAN"; (cd "$R" && timeout 30 bash "$RUNNER" scripts/__tests__/touched.test.sh >/dev/null 2>&1)
check "a test's own stub, put first on PATH by the test, still wins" "own-stub" "$(cat "$RAN")"
git -C "$R" checkout -q -- .

# Host issue 2997: a script named only by an unrelated test (here a test that runs seat.sh) is not run by plain
# --changed, which is the merge check's speed; --callers adds it, and only when asked.
printf '#!/usr/bin/env bash\n# runs scripts/seat.sh\necho uses-seat >> "$RAN"\n' > "$R/scripts/__tests__/uses-seat.test.sh"
git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -qm "a caller's test"
echo '# edited' >> "$R/scripts/seat.sh"
ran
check "plain --changed runs only the same-name test of a touched script, not a test that merely names it" "seat" "$GOT"
ran --callers
check "--callers also runs the test that names the touched script" "seat uses-seat" "$GOT"
git -C "$R" checkout -q -- .

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
