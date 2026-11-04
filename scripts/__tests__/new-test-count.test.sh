#!/usr/bin/env bash
# new-test-count.sh (issue 433): a change that added more tests than the cap reached review with no count named. The
# counter feeds the pass script's cap, so a test it misses lets a change past the cap, and a moved or already-merged
# test it counts refuses a change that adds none.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# repo <name> -- a project whose main holds one shell test with one check, and a unit branch cut from it.
repo() {
  R=$T/$1; mkdir -p "$R/scripts/__tests__" "$R/src"
  git -C "$R" init -q -b main && git -C "$R" config user.name t && git -C "$R" config user.email t@t
  printf 'check "the old case" 0 0\n' > "$R/scripts/__tests__/a.test.sh"
  git -C "$R" add -A && git -C "$R" commit -qm base && git -C "$R" checkout -q -b unit
}
count() { (cd "$R" && bash "$REAL/scripts/new-test-count.sh" main | head -1); }

repo added; printf 'check "the new case one" 0 0\ncheck "the new case two" 0 0\n' >> "$R/scripts/__tests__/a.test.sh"
check "a shell test file's added check lines count as new tests (issue 433)" "2 1" \
  "$(count) $(cd "$R" && bash "$REAL/scripts/new-test-count.sh" main | grep -cx 'the new case one')"

repo moved; printf '# a header\n' > "$R/scripts/__tests__/b.test.sh"; : > "$R/scripts/__tests__/a.test.sh"
printf 'check "the old case" 0 0\n' >> "$R/scripts/__tests__/b.test.sh"
check "a moved test counts as new" 1 "$(count)"

repo ts; printf "it('adds a row', () => {});\ntest(\"keeps a row\", () => {});\nconst x = fit;\n" > "$R/src/a.test.ts"
check "an it( or test( case added to a .test.ts file counts (issue 433)" 2 "$(count)"

# Work merged on main after the unit's own fork is not the unit's change, whatever review base main set.
repo merged; git -C "$R" checkout -q main; printf 'check "merged work" 0 0\n' >> "$R/scripts/__tests__/a.test.sh"
git -C "$R" commit -qam merged; git -C "$R" checkout -q unit; git -C "$R" rebase -q main
printf 'check "the unit case" 0 0\n' >> "$R/scripts/__tests__/a.test.sh"
check "tests already on main before a review base are not counted (issue 433)" 1 "$(count)"

repo spec; for i in $(seq 31); do printf "test('case %s', () => {});\n" "$i"; done > "$R/src/a.spec.ts"
check "31 test( cases added to src/a.spec.ts count 31 (issue 433)" 31 "$(count)"

# --edited (issue 496): a lost line is what an edit to an existing test is, so appending stays free.
ed() { (cd "$R" && bash "$REAL/scripts/new-test-count.sh" --edited "$@") 2>&1 | tr '\t' ' '; }
# Catches an edit that rewrites a check in place reading as no edit, a rename hiding the old lines, and a git failure reading as none.
repo edit; printf 'check "the old case" 1 1\n# note\n' > "$R/scripts/__tests__/a.test.sh"; git -C "$R" add -A; E1=$(ed main)
repo moved2; git -C "$R" mv scripts/__tests__/a.test.sh scripts/__tests__/z.test.sh; git -C "$R" commit -qam mv; E2=$(ed main HEAD)
check "edited_lists_lost_lines: a rewritten check and a renamed test each list their lost lines; a git failure is exit 2" \
  "scripts/__tests__/a.test.sh 1 1 | scripts/__tests__/a.test.sh 1 1 | 2" \
  "$E1 | $E2 | $( (cd "$R" && bash "$REAL/scripts/new-test-count.sh" --edited nosuchrev >/dev/null 2>&1); echo $?)"
# Catches the gate counting a new case as an edit, which would stop every Builder that adds a test to an existing file.
repo appended; printf 'check "more" 0 0\n' >> "$R/scripts/__tests__/a.test.sh"; git -C "$R" commit -qam more
check "added_lines_not_edits: a case appended to an existing test lists nothing" "" "$(ed main HEAD)"

# A line-1 count and exit code of the counter in the current repo, with no typescript on the module path.
run() { (cd "$R" && env -u NODE_PATH bash "$REAL/scripts/new-test-count.sh" main); }
# Catches a project without typescript failing or counting nothing, which lets any JS/TS change past the cap.
repo nots; printf "it('adds a row', () => {});\ntest.skip(isMac, 'mac only');\ntest.skip('a skipped case', () => {});\nconst x = it;\n" > "$R/src/a.test.ts"
check "no typescript: label regex" "2 adds a row a skipped case" "$(run | paste -sd' ' -)"

# Catches an .each table counted per row, or per line of a multi-line table, which spends the cap on one test.
repo each; printf "it.each([[1], [2], [3]])('row %%s', (n) => {});\ntest.each([\n  [4],\n  [5],\n])('multi %%s', (n) => {});\n" > "$R/src/a.test.ts"
check ".each counted once" "2 row %s multi %s" "$(run | paste -sd' ' -)"

# Catches the Python test-file names missing from is_test_path, so a pytest change reads as adding no test.
repo py; mkdir -p "$R/tests"; printf 'def test_one():\n    assert 1\n\nasync def test_two():\n    assert 2\n\ndef helper():\n    pass\n' > "$R/tests/test_a.py"
printf 'def test_three():\n    assert 3\n' > "$R/tests/b_test.py"
check "a test_*.py file is counted" "3 test_three test_one test_two" "$(run | paste -sd' ' -)"

# Catches an empty diff failing or printing nothing, which the pass script reads as a count error.
repo empty; OUT=$(run); RC=$?
check "an empty diff prints 0" "0 0" "$(head -1 <<<"$OUT") $RC"

# tsstub -- a stand-in typescript in the project's node_modules, so no real one is needed. TS_STUB picks it: `none` finds
# no test, `lit` finds each it('...') call with its literal's text as written, `parse` throws in createSourceFile, `load`
# throws while it loads.
tsstub() { mkdir -p "$R/node_modules/typescript"; cat > "$R/node_modules/typescript/index.js" <<'JS'
const kind = process.env.TS_STUB;
if (kind === 'load') throw new Error('stub typescript load failure');
const K = (k) => (n) => !!n && n.k === k;
const calls = (src) => (kind === 'none' ? [] : [...src.matchAll(/\b(it|test)\(('(?:[^'\\]|\\.)*')/g)])
  .map((m) => ({ k: 'call', expression: { k: 'id', text: m[1] }, arguments: [{ k: 'str', getText: () => m[2] }, { k: 'af' }] }));
module.exports = {
  ScriptKind: { JSX: 2, TSX: 4, JS: 1, TS: 3 }, ScriptTarget: { Latest: 99 },
  isParenthesizedExpression: K('paren'), isAsExpression: K('paren'), isSatisfiesExpression: K('paren'),
  isNonNullExpression: K('paren'), isTypeAssertionExpression: K('paren'), isPropertyAccessExpression: K('prop'),
  isCallExpression: K('call'), isTaggedTemplateExpression: K('tag'), isStringLiteral: K('str'),
  isNoSubstitutionTemplateLiteral: K('tpl'), isArrowFunction: K('af'), isFunctionExpression: K('fn'), isIdentifier: K('id'),
  createSourceFile: (p, src) => {
    if (kind === 'parse') throw new Error('stub parse failure');
    return { k: 'sf', calls: calls(src), getLineAndCharacterOfPosition: () => ({ line: 0 }) };
  },
  forEachChild: (n, f) => { (n.calls || []).forEach(f); },
};
JS
}

# Issue 596: the runner names a test by its string's value, so `it('it\'s fine')` is `it's fine` to the regex and to the
# parser alike; a name kept as written would never match the runner's name in a test-edit approval.
repo esc; printf "it('it\\\\'s fine', () => {});\n" > "$R/src/a.test.ts"
NOTS=$(run 2>/dev/null | paste -sd' ' -)
check "a test name with an escaped apostrophe is counted under the runner's name" "1 it's fine" "$NOTS"
tsstub; check "a test name with an escaped apostrophe reads the same with and without typescript" "1 it's fine|1 it's fine" \
  "$NOTS|$(TS_STUB=lit run 2>/dev/null | paste -sd' ' -)"

# Issue 628: a typescript found in the project is the only reader; a broken one stops the count with its error, never a
# silent text count that can miscount past the cap. The `none` stub finds no test where the regex finds one.
repo tsp; printf "it('one', () => {});\n" > "$R/src/a.test.ts"; tsstub
check "a project with typescript is read by the parser, not the label regex" 0 "$(TS_STUB=none run 2>/dev/null | head -1)"
OUT=$(TS_STUB=parse run 2>&1); RC=$?
check "a reader that fails with typescript loaded exits 2 naming the failure" "2 1" "$RC $(grep -c 'stub parse failure' <<<"$OUT")"
OUT=$(TS_STUB=load run 2>&1); RC=$?
check "a typescript that throws while loading exits 2 naming the failure" "2 1" "$RC $(grep -c 'stub typescript load failure' <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
