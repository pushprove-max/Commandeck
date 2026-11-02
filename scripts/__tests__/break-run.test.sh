#!/usr/bin/env bash
# break-run.test.sh -- break-run.sh <plan> <k> (issue 472). The break gate wants a recorded run of a Break line's test
# with the condition removed. What this pins: the run counts only when the named check itself fails, so another check
# failing never credits it; a label with quotes and parentheses is matched as plain text; the k-th Break line skips
# `Break: none` and fenced examples; a bad k, plan, line or file exits 2.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd -P)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
git init -q -b main "$T/p"; mkdir -p "$T/p/.claude"
echo '{"testCommand": "bash"}' > "$T/p/.claude/commandeck.json"
# br <plan> <k> -- the exit code, then the row (stdout) if any.
br() { local out rc; out=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$T/p" bash "$REAL/scripts/break-run.sh" "$@" 2>/dev/null); rc=$?; echo "$rc:$out"; }
# t <file> <printed lines...> -- a test file that prints them and fails (exit 1).
t() { local f=$1; shift; { echo '#!/usr/bin/env bash'; printf 'echo %q\n' "$@"; echo 'exit 1'; } > "$T/p/$f"; }
plan() { printf '%s\n' "$@" > "$T/p/plan.md"; }

t a.test.sh 'ok   wanted' 'FAIL unrelated (expected [1], got [2])'
plan 'Break: a.test.sh -- wanted -- x.sh site'
check "only the named check failing counts (issue 472)" "1:" "$(br plan.md 1)"
t a.test.sh 'FAIL wanted more (expected [1], got [2])'
check "a longer label that starts with the name is another check (issue 472)" "1:" "$(br plan.md 1)"
t a.test.sh 'ok   wanted' 'FAIL other'
check "a passing record of the label with another failure is no break run (issue 472)" "1:" "$(br plan.md 1)"
t a.test.sh 'FAIL wanted (expected [1], got [2])' 'FAIL unrelated'
check "the named check failing is a break run, and the row is the one the gate greps (issue 472)" \
  "0:- a.test.sh -- wanted -- red: bash a.test.sh" "$(br plan.md 1)"
t a.test.sh 'FAIL wanted'
check "a bare FAIL line of the label counts" "0:- a.test.sh -- wanted -- red: bash a.test.sh" "$(br plan.md 1)"
printf '#!/usr/bin/env bash\necho "FAIL wanted (x)"\nexit 0\n' > "$T/p/a.test.sh"
check "a zero exit is no break run even with the record" "1:" "$(br plan.md 1)"

L='a "quoted" (check) [x] $y.*'
t q.test.sh "FAIL $L (expected [1], got [2])"
plan "Break: q.test.sh -- $L -- x.sh site"
check "a quoted label runs as one argument (issue 472)" "0:- q.test.sh -- $L -- red: bash q.test.sh" "$(br plan.md 1)"
t q.test.sh 'FAIL a "quoted" (check) [x] $y.* more'
check "and a label that only starts the failing name is not matched (issue 472)" "1:" "$(br plan.md 1)"

# The k-th line is the one the break gate counts: a fence and `Break: none` hold none.
t b.test.sh 'FAIL second'
plan 'Break: none' '```' 'Break: a.test.sh -- fenced -- x' '```' 'Break: q.test.sh -- first -- x' 'Break: b.test.sh -- second -- y site'
check "the fenced and none lines are skipped: the second Break line is the plan's second real one" \
  "0:- b.test.sh -- second -- red: bash b.test.sh" "$(br plan.md 2)"
check "no k-th line, a bad k, no plan or a missing test file exit 2" "2: 2: 2: 2:" \
  "$(br plan.md 3) $(br plan.md 0) $(br nope.md 1) $(plan 'Break: gone.test.sh -- x -- y'; br plan.md 1)"

# A .test.mjs runs its .test.sh wrapper and reads node's cross; any other file runs the project's testCommand.
printf '#!/usr/bin/env bash\necho "  ✖ node check (1.2ms)"\nexit 1\n' > "$T/p/n.test.sh"; : > "$T/p/n.test.mjs"
plan 'Break: n.test.mjs -- node check -- z'
check "a node check's cross line is its failure record, run through the .test.sh wrapper" "0:- n.test.mjs -- node check -- red: bash n.test.sh" "$(br plan.md 1)"
t c.check 'FAIL custom (x)'
plan 'Break: c.check -- custom -- z'
check "another file runs the project's testCommand with the file as its argument" "0:- c.check -- custom -- red: bash c.check" "$(br plan.md 1)"

# --- apply mode (#542): <plan> <k> <file> <line> [<replacement>] breaks the line in place, runs, and puts the file back ---
# bra <args...> -- the exit code, then stdout; stderr is left in $T/err. x.sh is the code file, a.test.sh fails (with the
# check's record) only while x.sh lacks the word "good" on any line, and copies x.sh to seen.txt on every run.
bra() { local out rc; out=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$T/p" bash "$REAL/scripts/break-run.sh" "$@" 2>"$T/err"); rc=$?; echo "$rc:$out"; }
GD=$T/p/.git
codefile() { printf 'one\ngood\nthree\nlast no newline' > "$T/p/x.sh"; cp "$T/p/x.sh" "$T/orig"; }
guard() { printf '#!/usr/bin/env bash\ncp x.sh seen.txt\ngrep -q good x.sh && exit 0\n%s\necho "FAIL wanted (x)"\nexit 1\n' "${1-:}" > "$T/p/a.test.sh"; }
plan 'Break: a.test.sh -- wanted -- x.sh site'
codefile; guard
check "a break run restores the file byte for byte" "0:- a.test.sh -- wanted -- red: bash a.test.sh with x.sh:2 broken:same:1:none:none" \
  "$(bra plan.md 1 x.sh 2 'broken'):$(cmp -s "$T/orig" "$T/p/x.sh" && echo same || echo changed):$(grep -c '^broken$' "$T/p/seen.txt"):$([ -e "$GD/break-run.bak" ] && echo bak || echo none):$([ -e "$GD/break-run.path" ] && echo path || echo none)"
check "a break with no replacement empties the line" "0::1:same" \
  "$(bra plan.md 1 x.sh 2 | cut -c1-2):$(sed -n '2p' "$T/p/seen.txt" | wc -c | tr -d ' '):$(cmp -s "$T/orig" "$T/p/x.sh" && echo same || echo changed)"

t a.test.sh 'FAIL wanted (x)'
check "an already-red test is refused before the break" "2::same:1" \
  "$(bra plan.md 1 x.sh 2 'broken'):$(cmp -s "$T/orig" "$T/p/x.sh" && echo same || echo changed):$(grep -c 'already' "$T/err")"
t a.test.sh 'ok fine'; printf 'echo "FAIL wanted"\nexit 0\n' >> "$T/p/a.test.sh"
check "a test that prints the check's FAIL even at exit 0 is refused before the break" "2" "$(bra plan.md 1 x.sh 2 'broken' | cut -d: -f1)"

guard
check "a break that changes no line is refused naming the line" "2::same:1" \
  "$(bra plan.md 1 x.sh 3 'three'):$(cmp -s "$T/orig" "$T/p/x.sh" && echo same || echo changed):$(grep -c 'line 3' "$T/err")"
check "a line past the end is refused and the file is untouched" "2:same:1:2:2:2" \
  "$(bra plan.md 1 x.sh 5 'broken' | cut -d: -f1):$(cmp -s "$T/orig" "$T/p/x.sh" && echo same || echo changed):$(grep -c 'past the end' "$T/err"):$(bra plan.md 1 x.sh 0 z | cut -d: -f1):$(bra plan.md 1 x.sh 3x z | cut -d: -f1):$(bra plan.md 1 nope.sh 1 z | cut -d: -f1)"

R='say "hi" '\''q'\'' $HOME `id` $(id) \n \\ \"'
guard
bra plan.md 1 x.sh 2 "$R" > /dev/null
check "a replacement with quotes, a dollar sign and backslashes lands as written" "$R" "$(sed -n '2p' "$T/p/seen.txt")"

guard
check "a wrong check label is refused naming the label" "1::same:1" \
  "$(plan 'Break: a.test.sh -- nonesuch -- s'; bra plan.md 1 x.sh 2 'broken'):$(cmp -s "$T/orig" "$T/p/x.sh" && echo same || echo changed):$(grep -c "nonesuch" "$T/err")"
plan 'Break: a.test.sh -- wanted -- x.sh site'

# A run stopped by a signal, or killed outright, mid-test. The test hangs only while x.sh is broken, 4 seconds at most.
guard 'touch started; sleep 4'
sigrun() { # <signal> -- start a run on a broken line, send the signal once the test has started, wait for the end
  local pid i; rm -f "$T/p/started"; codefile
  set -m; (cd "$T/p" && exec env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$T/p" bash "$REAL/scripts/break-run.sh" plan.md 1 x.sh 2 broken >/dev/null 2>"$T/err") & pid=$!; set +m
  for i in $(seq 1 60); do [ -e "$T/p/started" ] && break; sleep 0.1; done
  kill "-$1" "$pid"; for i in $(seq 1 60); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  wait "$pid" 2>/dev/null; return 0
}
sigrun INT
check "a run stopped by INT or TERM restores the file (INT)" "started:same:none" \
  "$([ -e "$T/p/started" ] && echo started):$(cmp -s "$T/orig" "$T/p/x.sh" && echo same || echo changed):$([ -e "$GD/break-run.bak" ] && echo bak || echo none)"
sigrun TERM
check "a run stopped by INT or TERM restores the file (TERM)" "started:same:none" \
  "$([ -e "$T/p/started" ] && echo started):$(cmp -s "$T/orig" "$T/p/x.sh" && echo same || echo changed):$([ -e "$GD/break-run.bak" ] && echo bak || echo none)"

sigrun KILL
BROKEN=$(sed -n '2p' "$T/p/x.sh")
check "a leftover backup from a killed run is refused naming the restore" "broken:2:1:same" \
  "$BROKEN:$(bra plan.md 1 x.sh 2 'again' | cut -d: -f1):$(grep -c "cp .*break-run.bak.* .*x.sh" "$T/err"):$(cmp -s "$T/orig" "$GD/break-run.bak" && echo same || echo changed)"
# Pass 5 (class leftover-backup-bypass): the plain form must refuse too. Run on the tree a killed run left broken, the
# test fails with the check's record, so a plain run that skipped the check would print a red-proof row off a mutation
# nobody made on purpose. It is refused naming the restore, the test never starts, and the file and backup stay as left.
rm -f "$T/p/started"
check "a leftover backup from a killed run refuses the plain form too, before the test runs" "2::1:none:broken:same" \
  "$(bra plan.md 1):$(grep -c "cp .*break-run.bak.* .*x.sh" "$T/err"):$([ -e "$T/p/started" ] && echo started || echo none):$(sed -n '2p' "$T/p/x.sh"):$(cmp -s "$T/orig" "$GD/break-run.bak" && echo same || echo changed)"
cp "$GD/break-run.bak" "$T/p/x.sh"; rm -f "$GD/break-run.bak" "$GD/break-run.path"; pkill -f "sleep 4" 2>/dev/null
check "and once the file is restored the next run goes through" "0" "$(bra plan.md 1 x.sh 2 'broken' | cut -d: -f1)"


# Pass 4 (class shared-backup-race): two runs in one git directory would share break-run.bak, .path and .new, and a
# plain run would test a file another run has broken. While A holds its break, a second apply run (on another line) and
# a plain run are refused naming the holder, touch nothing, and A still restores its file byte for byte.
codefile; guard 'touch started; for i in $(seq 1 50); do [ -e go ] && break; sleep 0.1; done'; rm -f "$T/p/started" "$T/p/go"
(cd "$T/p" && env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$T/p" bash "$REAL/scripts/break-run.sh" plan.md 1 x.sh 2 broken > "$T/a-out" 2>&1; echo "rc=$?" >> "$T/a-out") & APID=$!
for i in $(seq 1 100); do [ -e "$T/p/started" ] && break; sleep 0.1; done
B=$(bra plan.md 1 x.sh 1 other | cut -d: -f1); BE=$(grep -c 'another break run (pid [0-9]*) holds' "$T/err"); BL=$(sed -n 1p "$T/p/x.sh")
C=$(bra plan.md 1 | cut -d: -f1); CE=$(grep -c 'another break run' "$T/err")
touch "$T/p/go"; wait "$APID"
check "a second break run while one holds the tree is refused naming it, and the first restores its file" \
  "2:1:one:2:1:rc=0:same:none" \
  "$B:$BE:$BL:$C:$CE:$(tail -1 "$T/a-out"):$(cmp -s "$T/orig" "$T/p/x.sh" && echo same || echo changed):$([ -e "$GD/break-run.bak" ] && echo bak || echo none)"

# Pass 11 (class partial-backup-data-loss): the exit trap restores whatever break-run.bak holds, so a backup copy that
# fails part-way must never become break-run.bak. A cp that writes 4 bytes and then fails leaves the uncommitted file
# byte for byte, no backup, path or partial copy behind, and exits 2 naming the failed backup.
codefile; guard; mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\nif [ "$1" = -p ]; then head -c 4 "$2" > "${@: -1}"; echo "cp: simulated short write" >&2; exit 1; fi\nexec /bin/cp "$@"\n' > "$T/bin/cp"; chmod +x "$T/bin/cp"
O=$(PATH="$T/bin:$PATH" bra plan.md 1 x.sh 2 'broken' | cut -d: -f1)
check "a backup copy that fails part-way leaves the file untouched and no backup behind" "2:same:none:none:0:1" \
  "$O:$(cmp -s "$T/orig" "$T/p/x.sh" && echo same || echo changed):$([ -e "$GD/break-run.bak" ] && echo bak || echo none):$([ -e "$GD/break-run.path" ] && echo path || echo none):$(ls "$GD" | grep -c '^break-run\.\(copy\|new\)'):$(grep -c 'cannot back up' "$T/err")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
