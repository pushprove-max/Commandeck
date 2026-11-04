#!/usr/bin/env bash
# test-edit-labels.sh (issue 504): main approves a test edit by test name, so each lost line of a code file must map to the one
# test it belongs to or be refused by line. No code line earns (file): one (file) approval would cover every helper of a file.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
R=$T/proj; mkdir -p "$R"
git -C "$R" init -q -b main && git -C "$R" config user.name t && git -C "$R" config user.email t@t
# A shell test with a check split over two lines and a plain check; a JS test with two blocks; a data fixture.
printf '%s\n' 'check "one" 1 \' '  "1"' 'check "two" 0 0' > "$R/a.test.sh"
printf '%s\n' 'describe("s", () => {' '  it("alpha", () => {' '    expect(1)' '  });' '  it("beta", () => { expect(2) });' '});' > "$R/b.test.js"
printf '%s\n' '{' '  "a": 1,' '  "b": 2' '}' > "$R/f.test.json"
git -C "$R" add -A && git -C "$R" commit -qm base
labels() { (cd "$R" && git add -A && bash "$REAL/scripts/test-edit-labels.sh" "$1" HEAD | paste -sd, -); } # <path>

# Catches a check line mapped to the wrong test, or a continuation line left out of its check, so one approval covers the
# wrong test; or an it block read as one line, so its body and closing line would need no approval of that test.
: > "$R/a.test.sh"; SH=$(labels a.test.sh)
printf '%s\n' 'describe("s", () => {' '  it("beta", () => { expect(2) });' '});' > "$R/b.test.js"
check "a check line maps to its label" "one	2,two	1|alpha	3" "$SH|$(labels b.test.js)"

# Catches the data kinds losing (file), the owner's one remaining use of it: each lost line of a fixture is that one row.
printf '%s\n' '{' '  "a": 1' '}' > "$R/f.test.json"
check "a data line maps to (file)" "(file)	2" "$(labels f.test.json)"

# Every shape found so far, in the order found. Catches any code line that is no labelled test reaching (file), or a label
# that spans two tests: either lets one approval cover what it does not name. Each case must exit 2, name <file>:<n>, print
# its `(line)` row with the exact old text, and print no (file).
BAD= N=0
gone() { # <file> <lost line number> <old lines...>
  local f=$1 at=$2 rc=0 want; shift 2
  N=$((N + 1)); printf '%s\n' "$@" > "$R/$f"; git -C "$R" add -A; git -C "$R" commit -qm "$N"
  awk -v n="$at" 'NR != n' "$R/$f" > "$T/new" && cat "$T/new" > "$R/$f"; git -C "$R" add -A
  want=${!at}
  (cd "$R" && bash "$REAL/scripts/test-edit-labels.sh" "$f" HEAD >"$T/out" 2>"$T/err") || rc=$?
  [ "$rc" = 2 ] && grep -qF "$f:$at" "$T/err" && grep -qxF "(line)	$at	$want" "$T/out" && ! grep -q '^(file)' "$T/out" || BAD+=" $N:$f"
  git -C "$R" reset -q --hard
}
gone s1.test.sh 1 "check 'x' 1 1"
gone s2.test.sh 1 'check"x" 1 1'
gone s3.test.sh 1 'fresh; check "x" 1 1'
gone j4.test.js 1 'it.only("o", () => {' '});'
gone j5.test.js 2 'test.each([1, 2])("case %i", (n) => {' '  expect(n).toBeGreaterThan(0);' '});'
gone j6.test.js 2 'it(name, () => {' '  expect(1);' '});'
gone j7.test.js 2 'it("x", () => {' '  expect(1);'
gone p8.test.py 2 'def test_a():' '    assert 1'
gone s9.test.sh 2 'check "x" "a' 'b" 1'
gone s10.test.sh 1 'check "(file)" 1 1'
gone s11.test.sh 1 'check "x #1" 1 1'
gone s12.test.sh 1 'check "$v" 1 1'
gone s13.test.sh 2 'run_case() { check "$1" 1 1; }' 'run_case "x"'
gone s14.test.sh 3 'assert_case() { check "$1" 1 1; }' 'run_case() { assert_case "$1"; }' 'run_case "x"'
gone s15.test.sh 1 'FAIL=$((FAIL+1))'
gone s16.test.sh 2 '. ./lib.sh' 'run_case "x"'
gone j17.test.js 5 'function registerCase(name) {' '  it(name, () => { expect(1).toBe(1); });' '}' 'function runCases() {' '  registerCase("unapproved");' '}' 'runCases();'
gone j18.test.js 1 'const c = registerCase("x");'
gone j19.test.ts 1 'import "./shared-tests";'
gone s20.test.sh 1 '# a comment'
gone s21.test.sh 2 'cat <<X' '# in a here-document' 'X'
gone s22.test.sh 1 'helper() { :; }' 'check "one" 1 1'
gone s23.test.sh 1 'check "a" 1 1; check "b" 2 2'
gone j24.test.js 1 'it("a", f); it("b", g);'
gone s25.test.sh 1 'check "a" 1 1 \' 'check "b" 2 2'
gone j26.test.js 1 'it("outer", () => {' '  it("inner", () => {' '  });' '});'
# Catches a failure of the reader reading as no edits: a bad base must not exit 0 or look like a refused line.
RC=$(cd "$R" && bash "$REAL/scripts/test-edit-labels.sh" a.test.sh no-such-base >/dev/null 2>&1; echo $?)
check "an unknown test shape is refused by line" "26 3" "$((N - $(wc -w <<<"$BAD")))$BAD $RC"

# Catches: two tests with one name sharing one approval: each gets its own identity, so a yes names one of them.
printf '%s\n' 'check "same" 1 1' 'check "other" 1 1' 'check "same" 2 2' > "$R/e.test.sh"; git -C "$R" add -A && git -C "$R" commit -qm dup
printf '%s\n' 'check "other" 1 1' > "$R/e.test.sh"
ALL=$(labels e.test.sh); printf '%s\n' 'check "same" 1 1' 'check "other" 1 1' > "$R/e.test.sh"
check "two tests of one name differ" "same #1	1,same #2	1|same #2	1" "$ALL|$(labels e.test.sh)"

# Issue 596: the runner names a test by its string's value, so an escaped quote in the label reads as the plain quote and
# the label runs to the unescaped closing quote (an approval of the runner's name must match).
printf '%s\n' "it('it\\'s fine', () => { expect(1) });" 'it("x", () => { expect(2) });' > "$R/q.test.js"
git -C "$R" add -A && git -C "$R" commit -qm q; printf '%s\n' 'it("x", () => { expect(2) });' > "$R/q.test.js"
check "a single-quoted label with an escaped apostrophe reads with a plain apostrophe" "it's fine	1" "$(labels q.test.js)"
printf '%s\n' 'it("say \"hi\"", () => { expect(1) });' 'it("x", () => { expect(2) });' > "$R/q.test.js"
git -C "$R" add -A && git -C "$R" commit -qm q2; printf '%s\n' 'it("x", () => { expect(2) });' > "$R/q.test.js"
check "a double-quoted label with an escaped quote reads with a plain quote" 'say "hi"	1' "$(labels q.test.js)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
