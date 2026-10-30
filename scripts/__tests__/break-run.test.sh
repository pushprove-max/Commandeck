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
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
