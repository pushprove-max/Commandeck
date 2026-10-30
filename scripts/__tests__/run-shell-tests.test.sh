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
# A stub with no panes: under a live Orca the detached result went to the real main pane, so the fixture's queue stayed empty.
mkdir -p "$TMP/nopane"; printf '#!/usr/bin/env bash\necho "{\\"result\\":[]}"\n' > "$TMP/nopane/orca-ide"; chmod +x "$TMP/nopane/orca-ide"
OUT=$(cd "$R" && env -u COMMANDECK_FOREGROUND CLAUDECODE=1 COMMANDECK_SCRATCH="$TMP/scratch" PATH="$TMP/nopane:$PATH" bash "$RUNNER" scripts/__tests__/touched.test.sh </dev/null 2>&1); RC=$?
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
# The ordinary file --own-lane leaves out is neither run nor counted: not a failure for having no result.
: > "$RAN"; OUT=$(cd "$R" && timeout 30 bash "$RUNNER" --own-lane scripts/__tests__/untouched.test.sh scripts/__tests__/seat.test.sh 2>&1); RC=$?
check "--own-lane runs only the own-lane file, and the ordinary file it leaves out is not a failure" "lane 0 1" \
  "$(cat "$RAN") $RC $(grep -c '^1 passed, 0 failed' <<<"$OUT")"
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

# A test whose run is killed before its result is written failed: it is never left out of the count as if skipped.
printf '#!/usr/bin/env bash\nkill -9 "$(ps -o ppid= -p "$PPID" | tr -d " ")"\n' > "$R/scripts/__tests__/touched.test.sh"
OUT=$(cd "$R" && timeout 30 bash "$RUNNER" scripts/__tests__/touched.test.sh 2>&1); RC=$?
check "a test killed before its result is written counts as failed" "1 1" "$RC $(grep -c '^0 passed, 1 failed' <<<"$OUT")"
sed -i.bak '1a\
# own-lane: killed in its lane' "$R/scripts/__tests__/touched.test.sh"; rm -f "$R/scripts/__tests__/touched.test.sh.bak"
OUT=$(cd "$R" && timeout 30 bash "$RUNNER" --own-lane scripts/__tests__/touched.test.sh scripts/__tests__/seat.test.sh 2>&1); RC=$?
check "... and so does an own-lane test killed in its --own-lane run, beside the ordinary file it leaves out" "1 1" "$RC $(grep -c '^0 passed, 1 failed' <<<"$OUT")"
git -C "$R" checkout -q -- .

# Every ordering of the hand-off's outcome found so far (Decision G13-3, revision 7), in order. The outcome is the
# hand-off's exit code alone, from a fixed list; only 3 (not routed) and 4 (unreachable) run the handed-off files here.
# r7, the reason write that failed: now the Mac cannot make the hand-off's temp files (TMPDIR unwritable), in a linked
# worktree routed to the PC. Exit 2, nothing runs here, no ssh call.
W=$TMP/wt; git -C "$R" worktree add -q --detach "$W"
mkdir -p "$TMP/home/.config/devenv" "$TMP/ro" "$TMP/sshbin"; chmod 555 "$TMP/ro"
echo pc > "$TMP/home/.config/devenv/peer"; echo pc > "$TMP/home/.config/devenv/chain-host"
printf '#!/usr/bin/env bash\necho ssh >> "$RAN"\nexit 255\n' > "$TMP/sshbin/ssh"; chmod +x "$TMP/sshbin/ssh"
check "the fixture's TMPDIR cannot be written" 1 "$(touch "$TMP/ro/probe" 2>/dev/null; [ -e "$TMP/ro/probe" ]; echo $?)"
: > "$RAN"; OUT=$(cd "$W" && env -u COMMANDECK_HOOK_FIRE_LOG -u COMMANDECK_OFFLOADED HOME="$TMP/home" COMMANDECK_HOST_OS=Darwin \
  TMPDIR="$TMP/ro" PATH="$TMP/sshbin:$PATH" timeout 30 bash "$RUNNER" scripts/__tests__/touched.test.sh 2>&1); RC=$?
check "every ordering of the hand-off's outcome found so far: the Mac cannot make its temp files: exit 2, nothing runs here or there" \
  "2  1" "$RC $(sort "$RAN" | paste -sd' ' -) $(grep -c 'nothing ran here' <<<"$OUT")"
chmod 755 "$TMP/ro"
# The rest through a copy of the runner whose peer-offload.sh is a stub: PO_STUB=fail makes it fail to load (r8, the
# reason read that failed), and otherwise its pr_offload logs `off` and returns PO_STUB. Between two runs nothing is
# kept: each run decides from its own code alone. A `# host: mac` file runs here after every code but a failure (2).
mkdir -p "$TMP/stub/scripts"; cp "$REAL"/scripts/*.sh "$TMP/stub/scripts/"
printf '[ "$PO_STUB" != fail ] || return 1\npr_offload() { echo off >> "$RAN"; return "$PO_STUB"; }\n' > "$TMP/stub/scripts/peer-offload.sh"
printf '#!/usr/bin/env bash\n# host: mac\necho mac >> "$RAN"\n' > "$R/scripts/__tests__/mac.test.sh"
for step in "fail 2 " "0 0 mac off" "1 1 mac off" "2 2 off" "3 0 mac off touched" "4 0 mac off touched" "5 1 mac off"; do
  set -- $step; stub=$1 want=$2; shift 2
  : > "$RAN"; OUT=$(cd "$R" && PO_STUB=$stub timeout 30 bash "$TMP/stub/scripts/run-shell-tests.sh" \
    scripts/__tests__/touched.test.sh scripts/__tests__/mac.test.sh 2>&1); RC=$?
  check "every ordering of the hand-off's outcome found so far: the hand-off ends $stub: exit $want, and only $* run" \
    "$want $*" "$RC $(sort "$RAN" | paste -sd' ' -)"
done
check "... an unreachable PC (4) says it runs the files here, once" 1 "$(PO_STUB=4 bash -c 'cd "$1" && bash "$2" scripts/__tests__/touched.test.sh' _ "$R" "$TMP/stub/scripts/run-shell-tests.sh" 2>&1 | grep -c 'running here, once')"
rm -f "$R/scripts/__tests__/mac.test.sh"

# Issue 349: a run writes a live table, <git dir>/commandeck-test-live/<pid>.tsv, that the units mod reads: `run`, `file`
# for every file the run decides on, `start` and `end` as each file launches and ends. Gone when the run exits.
TAB=$(printf '\t'); LD=$(git -C "$R" rev-parse --absolute-git-dir)/commandeck-test-live
LREL=scripts/__tests__/live.test.sh
printf '#!/usr/bin/env bash\ncp "$(git rev-parse --absolute-git-dir)"/commandeck-test-live/*.tsv "$SEEN"\n' > "$R/$LREL"
export SEEN=$TMP/seen
(cd "$R" && timeout 30 bash "$RUNNER" "$LREL" >/dev/null 2>&1)
check "a run's live table lists its files while they run and is gone when the run exits" "1 1 1 0" \
  "$(grep -c "^run$TAB" "$SEEN") $(grep -c "^file$TAB$LREL\$" "$SEEN") $(grep -c "^start$TAB$LREL$TAB" "$SEEN") $(ls "$LD"/*.tsv 2>/dev/null | wc -l | tr -d ' ')"
rm -f "$R/$LREL"

# Two files, one marked own-lane. Without the flag the own-lane file is skipped at once (listed, `end skip 0`, before any
# start); with --own-lane the ordinary file is left out and never enters the table.
OREL=scripts/__tests__/ord.test.sh LANEREL=scripts/__tests__/lane.test.sh
printf '#!/usr/bin/env bash\ncp "$(git rev-parse --absolute-git-dir)"/commandeck-test-live/*.tsv "$SEEN-ord"\n' > "$R/$OREL"
printf '#!/usr/bin/env bash\n# own-lane: fixture\ncp "$(git rev-parse --absolute-git-dir)"/commandeck-test-live/*.tsv "$SEEN-lane"\n' > "$R/$LANEREL"
(cd "$R" && timeout 30 bash "$RUNNER" "$OREL" "$LANEREL" >/dev/null 2>&1)
ENDN=$(grep -n "^end$TAB$LANEREL${TAB}skip${TAB}0\$" "$SEEN-ord" | cut -d: -f1); STARTN=$(grep -n "^start$TAB$OREL$TAB" "$SEEN-ord" | cut -d: -f1)
check "a skipped own-lane file finishes as skip in the live table, and under --own-lane the ordinary file it leaves out never enters it: no flag" \
  "2 1 1 0" "$(grep -c "^file$TAB" "$SEEN-ord") $([ "${ENDN:-99}" -lt "${STARTN:-0}" ] && echo 1 || echo 0) $(grep -c "^start$TAB$OREL$TAB" "$SEEN-ord") $(ls "$LD"/*.tsv 2>/dev/null | wc -l | tr -d ' ')"
(cd "$R" && timeout 30 bash "$RUNNER" --own-lane "$OREL" "$LANEREL" >/dev/null 2>&1)
check "... --own-lane: the table lists the lane file and its start, and no line names the ordinary file" \
  "1 1 0 0" "$(grep -c "^file$TAB$LANEREL\$" "$SEEN-lane") $(grep -c "^start$TAB$LANEREL$TAB" "$SEEN-lane") $(grep -c 'ord.test.sh' "$SEEN-lane") $(ls "$LD"/*.tsv 2>/dev/null | wc -l | tr -d ' ')"
rm -f "$R/$OREL" "$R/$LANEREL"

# Issue 422: --skip-passed reruns only what did not pass at this exact tree, read from a ledger of local results,
# <git dir>/commandeck-test-runs.tsv. Three files: b is red while $BRED exists (outside the tree), a reads a selector.
S=$TMP/skip; mkdir -p "$S/scripts/__tests__"
printf '#!/usr/bin/env bash\necho "a${A_TEST_CASE+:$A_TEST_CASE}" >> "$RAN"\n' > "$S/scripts/__tests__/a.test.sh"
printf '#!/usr/bin/env bash\necho b >> "$RAN"\n[ ! -e "$BRED" ]\n' > "$S/scripts/__tests__/b.test.sh"
printf '#!/usr/bin/env bash\necho c >> "$RAN"\n' > "$S/scripts/__tests__/c.test.sh"
git -C "$S" init -q && git -C "$S" add -A && git -C "$S" -c user.name=t -c user.email=t@t commit -qm base
export BRED=$TMP/bred; LEDGER=$(git -C "$S" rev-parse --absolute-git-dir)/commandeck-test-runs.tsv
skip() { : > "$RAN"; OUT=$(cd "$S" && env -u A_TEST_CASE "$@" timeout 30 bash "$RUNNER" "${ARGS[@]}" 2>&1); RC=$?; GOT=$(sort "$RAN" | paste -sd" " -); }
REUSED='^-- ok   a\.test\.sh +0s \(passed at this tree in an earlier run\)$'
touch "$BRED"; ARGS=(); skip
grep -v $'\tscripts/__tests__/c.test.sh\t' "$LEDGER" > "$LEDGER.t"; mv "$LEDGER.t" "$LEDGER"; rm -f "$BRED"
ARGS=(--skip-passed); skip
check "--skip-passed reruns the failed and the missing file and skips the green one" "0 b c 1 1" \
  "$RC $GOT $(grep -cE "$REUSED" <<<"$OUT") $(grep -c '^3 passed, 0 failed' <<<"$OUT")"
printf '2026-10-27T00:00:00Z\tscripts/__tests__/a.te\n' >> "$LEDGER"; skip
check "a cut or glued ledger line brings back no older pass" "a b c" "$GOT"
skip; GONE=$GOT; echo x > "$S/new-untracked"; skip; rm -f "$S/new-untracked"
check "--skip-passed skips nothing after any tree change" "| a b c" "$GONE| $GOT"
ARGS=(); skip
check "without --skip-passed every file runs" "a b c" "$GOT"
rm -f "$LEDGER"; ARGS=(scripts/__tests__/a.test.sh); skip A_TEST_CASE=x; ROWS=$(cat "$LEDGER" 2>/dev/null | wc -l | tr -d ' ')
ARGS=(--skip-passed scripts/__tests__/a.test.sh); skip; WHOLE=$GOT
skip A_TEST_CASE=x
check "a selected-case run neither records nor reuses a pass" "0 a a:x 1 1" \
  "$ROWS $WHOLE $GOT $(grep -c 'a test-case selector is set (A_TEST_CASE); --skip-passed reuses and records nothing' <<<"$OUT") $(wc -l < "$LEDGER" | tr -d ' ')"

# A pass is recorded or reused only for a tree no edit touched after the run's snapshot: an edit kept, reverted, or made and
# removed (a file created and deleted) must all rerun the file. Every fixture repo is fresh, `value` is bad in it, and the
# file t passes only on good. Sync files sit outside the tree; every wait is bounded. A token is "<first rc>><retry rc>
# <files the retry ran> <reuse lines>": 0>1 t 0 is a first run that passed and a retry that ran t and failed it.
export READY=$TMP/ready RELEASE=$TMP/release EXAMINED=$TMP/examined FINISH=$TMP/finish
await() { local _; for _ in $(seq 200); do [ -e "$1" ] && return 0; sleep 0.05; done; return 1; }
mk() { rm -rf "$1"; mkdir -p "$1/scripts/__tests__"; printf 'bad\n' > "$1/value"; printf '#!/usr/bin/env bash\n%s\n' "$2" > "$1/scripts/__tests__/t.test.sh"
  git -C "$1" init -q && git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm base; }
bg() { : > "$RAN"; rm -f "$READY" "$RELEASE" "$EXAMINED" "$FINISH"
  (cd "$1" && timeout 30 bash "$RUNNER" --skip-passed > /dev/null 2>&1) & BGPID=$!; await "$READY"; }
fin() { wait "$BGPID"; RC1=$?; }
tok() { echo "$RC1>$RC $GOT $(grep -c 'passed at this tree' <<<"$OUT")"; }
rows() { cat "$1" 2>/dev/null | wc -l | tr -d ' '; }
WAITS='touch "$READY"; n=0; until [ -e "$RELEASE" ] || [ $((n++)) -ge 400 ]; do sleep 0.05; done'
FINW='touch "$EXAMINED"; n=0; until [ -e "$FINISH" ] || [ $((n++)) -ge 400 ]; do sleep 0.05; done'
ARGS=(--skip-passed)
# 1, kept: good while t waits, bad again once the run is over.
T1=$TMP/o1; mk "$T1" "$WAITS"'; echo t >> "$RAN"; [ "$(cat "$(dirname "$0")/../../value")" = good ]'
bg "$T1"; printf 'good\n' > "$T1/value"; touch "$RELEASE"; fin
printf 'bad\n' > "$T1/value"; S=$T1 skip; TOK1=$(tok)
# 2, reverted: t reads good, says so (EXAMINED), and waits; bad is back before it exits 0.
T2=$TMP/o2; mk "$T2" "$WAITS"'; echo t >> "$RAN"; v=$(cat "$(dirname "$0")/../../value"); '"$FINW"'; [ "$v" = good ]'
bg "$T2"; printf 'good\n' > "$T2/value"; touch "$RELEASE"; await "$EXAMINED"; printf 'bad\n' > "$T2/value"; touch "$FINISH"; fin
S=$T2 skip; TOK2=$(tok)
# 3, created and removed: t passes only while `extra` exists; it is gone before t exits.
T3=$TMP/o3; mk "$T3" "$WAITS"'; echo t >> "$RAN"; [ -e "$(dirname "$0")/../../extra" ]; r=$?; '"$FINW"'; exit $r'
bg "$T3"; touch "$T3/extra" "$RELEASE"; await "$EXAMINED"; rm -f "$T3/extra"; touch "$FINISH"; fin
S=$T3 skip; TOK3=$(tok)
# 4, the reuse side: the stub awk (the skip loop reads the ledger with it) edits the tree once, between the snapshot and the
# recheck: first a file created and kept, then a file created and removed there. Neither reuses p or adds a row.
P=$TMP/pass; mkdir -p "$P/scripts/__tests__" "$TMP/awkbin"
printf '#!/usr/bin/env bash\necho p >> "$RAN"\n' > "$P/scripts/__tests__/p.test.sh"
git -C "$P" init -q && git -C "$P" add -A && git -C "$P" -c user.name=t -c user.email=t@t commit -qm base
printf '#!/usr/bin/env bash\ncase ${*: -1} in *commandeck-test-runs.tsv) touch "$INJECT"; [ -z "${INJECT_RM-}" ] || rm -f "$INJECT" ;; esac\nexec %q "$@"\n' "$(command -v awk)" > "$TMP/awkbin/awk"
chmod +x "$TMP/awkbin/awk"
PLEDGER=$(git -C "$P" rev-parse --absolute-git-dir)/commandeck-test-runs.tsv
S=$P skip; PROWS=$(rows "$PLEDGER")
S=$P skip INJECT="$P/injected" PATH="$TMP/awkbin:$PATH"; TOK4=$RC" $GOT $(grep -c 'passed at this tree' <<<"$OUT") $(($(rows "$PLEDGER") - PROWS))"
rm -f "$P/injected"
S=$P skip INJECT="$P/injected" INJECT_RM=1 PATH="$TMP/awkbin:$PATH"; TOK4B=$RC" $GOT $(grep -c 'passed at this tree' <<<"$OUT") $(($(rows "$PLEDGER") - PROWS))"
# 5, the hash race: a git stub makes the run's first `add -A` on an index copy, then writes good into value, once.
T5=$TMP/o5; mk "$T5" 'echo t >> "$RAN"; [ "$(cat "$(dirname "$0")/../../value")" = good ]'
mkdir -p "$TMP/gitbin"; RG=$(command -v git)
printf '#!/usr/bin/env bash\nif [ "${1-}" = add ] && [ "${2-}" = -A ] && [ -n "${GIT_INDEX_FILE-}" ] && [ ! -e "$GMARK" ]; then\n  %q "$@"; rc=$?; : > "$GMARK"; printf "good\\n" > "$GVAL"; exit $rc\nfi\nexec %q "$@"\n' "$RG" "$RG" > "$TMP/gitbin/git"
chmod +x "$TMP/gitbin/git"
S=$T5 skip GMARK="$TMP/gmark" GVAL="$T5/value" PATH="$TMP/gitbin:$PATH"; RC1=$RC
printf 'bad\n' > "$T5/value"; S=$T5 skip; TOK5=$(tok)
# The retry path for each piece of state, with a passing file q: (a) the ledger deleted, (b) every stamp deleted while q waits.
Q=$TMP/q; mk "$Q" "$WAITS"'; echo t >> "$RAN"'
QLEDGER=$(git -C "$Q" rev-parse --absolute-git-dir)/commandeck-test-runs.tsv; QGD=$(dirname "$QLEDGER")
touch "$RELEASE"; S=$Q skip; QROWS=$(rows "$QLEDGER")
rm -f "$QLEDGER"; S=$Q skip; TOKA="$QROWS $GOT"
rm -f "$QLEDGER"; bg "$Q"; rm -f "$QGD"/commandeck-test-stamp.*; touch "$RELEASE"; fin
BROWS=$(rows "$QLEDGER"); S=$Q skip; TOKB="$BROWS $GOT"
check "an edit after the run's snapshot, kept or reverted, is never recorded or reused: every ordering reruns the file" \
  "0>1 t 0 | 0>1 t 0 | 0>1 t 0 | 0 p 0 0 | 0 p 0 0 | 0>1 t 0 | 1 t | 0 t" \
  "$TOK1 | $TOK2 | $TOK3 | $TOK4 | $TOK4B | $TOK5 | $TOKA | $TOKB"

# The line cap (issue 436): a shell test file that regrew past 500 lines fails before it runs, with the cap named,
# and the run exits non-zero; one at the cap still runs.
C=$TMP/cap; mkdir -p "$C/scripts/__tests__"
{ printf '#!/usr/bin/env bash\necho at >> "$RAN"\n'; for _ in $(seq 498); do echo :; done; } > "$C/scripts/__tests__/at.test.sh"
{ printf '#!/usr/bin/env bash\necho over >> "$RAN"\n'; for _ in $(seq 499); do echo :; done; } > "$C/scripts/__tests__/over.test.sh"
git -C "$C" init -q && git -C "$C" add -A && git -C "$C" -c user.name=t -c user.email=t@t commit -qm base
: > "$RAN"; OUT=$(cd "$C" && timeout 30 bash "$RUNNER" scripts/__tests__/over.test.sh 2>&1); RC=$?
check "a shell test file over the line cap fails with the cap named (issue 436)" "1 1 0" \
  "$([ "$RC" -ne 0 ] && echo 1 || echo 0) $(grep -c 'FAIL over.test.sh over the 500-line cap for one shell test file' <<<"$OUT") $(grep -c over "$RAN")"
: > "$RAN"; OUT=$(cd "$C" && timeout 30 bash "$RUNNER" scripts/__tests__/at.test.sh 2>&1); RC=$?
check "a shell test file at the cap runs (issue 436)" "0 at" "$RC $(cat "$RAN")"

# #489: with slow files last a bare run ends on them alone, so the seconds saved from earlier runs start the slowest first.
# One fixture builder: four tests that log their name, one job so the log is the start order.
mkord() { rm -rf "$1"; mkdir -p "$1/scripts/__tests__"; git -C "$1" init -q
  for n in a b c d; do printf '#!/usr/bin/env bash\necho %s >> "$RUNLOG"\n' "$n" > "$1/scripts/__tests__/$n-l.test.sh"; done; }
BOXL=$TMP/ord; mkord "$BOXL"; LIST=$BOXL/secs.tsv; RUNLOG=$BOXL/ran; export RUNLOG
rl() { : > "$RUNLOG"; (cd "$BOXL" && env -u COMMANDECK_RUNNING_TEST COMMANDECK_SHELL_TEST_JOBS=1 COMMANDECK_SHELL_TEST_SECONDS=$LIST timeout 30 bash "$RUNNER" "$@" > "$BOXL/out" 2>"$BOXL/err"); }
printf '5\tb-l.test.sh\n90\td-l.test.sh\n' > "$LIST"
rl
# Catches: files started in sorted order whatever the saved seconds, so a run still ended on its slowest file.
check "longest_first_starts_slowest: known files start longest first, a file with no row after them" "d b a c" "$(paste -sd' ' - < "$RUNLOG")"
# Catches: the report following the start order instead of sorted order.
check "report_stays_sorted: the report keeps sorted order whatever order the files ran" "a-l b-l c-l d-l" \
  "$(sed -n 's/^ok   \([a-d]-l\)\.test\.sh.*/\1/p' "$BOXL/out" | paste -sd' ' -)"
printf '12\tb-l\n7\tc/l.test.sh\n3\td-l.test.sh\tx\nxx\ta-l.test.sh\n40\tc-l.test.sh\n' > "$LIST"
rl; RCL=$?
# Catches: a half row, a row with a slash, an extra field or a non-number being used (or aborting the run) instead of skipped.
check "corrupt_seconds_row_ignored: bad rows are skipped, the one good row orders the run and the run passes" "c a b d 0" \
  "$(paste -sd' ' - < "$RUNLOG") $RCL"
FAKEHOME=$BOXL/home; mkdir -p "$FAKEHOME/.commandeck"; printf '90\td-l.test.sh\n5\tb-l.test.sh\n' > "$FAKEHOME/.commandeck/shell-test-seconds.tsv"
BEFORE=$(cksum < "$FAKEHOME/.commandeck/shell-test-seconds.tsv")
: > "$RUNLOG"; (cd "$BOXL" && env -u COMMANDECK_SHELL_TEST_SECONDS HOME=$FAKEHOME COMMANDECK_RUNNING_TEST=outer.test.sh COMMANDECK_SHELL_TEST_JOBS=1 timeout 30 bash "$RUNNER" > "$BOXL/out" 2>&1)
# Catches: a run inside a test reading or writing the host's list (the clear-out unsets the guard before it is read).
check "nested_run_leaves_list_alone (a run inside a test neither orders by the host's list nor changes it)" "a b c d | $BEFORE" \
  "$(paste -sd' ' - < "$RUNLOG") | $(cksum < "$FAKEHOME/.commandeck/shell-test-seconds.tsv")"

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
