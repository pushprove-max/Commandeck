#!/usr/bin/env bash
# new-test-count.sh <base> -- issue 433: how many tests the unit's own change adds, for the new-test cap the pass
# script holds a change to (reviewLoop.newTestCap). Prints the count on its first line, then each new label.
# The change is the unit's own: from where HEAD left <base> (git merge-base), never a review base, so work already on
# main is not counted again. Test files are the skip/only guard's (hooks/lib/test-path.sh). A new test is a name added
# in a test file: `check "<label>"` in a shell file, `def test*` in a Python file, `it(` or `test(` with a label in any
# other. A test kept in its file under its name (edited in place) is not new; a moved or renamed one is. An `.each`
# table counts once. `test.skip(cond, 'why')` gates are no test; `test.skip('case', fn)` is. JS/TS is read by the
# project's own typescript when it has one (nested tests and `t.test()` subtests included), else by a label regex, said on
# stderr; a typescript that fails to load or parse exits 2 naming the failure. A name is the string's value (`\'` is `'`).
# Checks made in a loop or through a helper count as one or none: the count is a review gate on names, not a proof of
# count. An empty diff prints 0.
set -uo pipefail
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
BASE=${1:?usage: new-test-count.sh <base>}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/../hooks/lib/test-path.sh" || { echo "new-test-count: cannot load hooks/lib/test-path.sh" >&2; exit 2; }
if [ "$BASE" = --changed ]; then
  # --changed <base> <head> (issue 676): each test file that exists at <base> and differs by <head>, an added line
  # included, for the merge's loosened-check report: a check loosened by adding lines is still an edit. A git failure exits 2.
  CB=${2:?usage: new-test-count.sh --changed <base> <head>} CH=${3:?usage: new-test-count.sh --changed <base> <head>}
  NAMES=$(git --literal-pathspecs diff --no-renames --name-only -z "$CB" "$CH" | tr '\0' '\n') \
    || { echo "new-test-count: git diff failed for $CB" >&2; exit 2; }
  while IFS= read -r f; do
    [ -n "$f" ] && is_test_path "$f" && git cat-file -e "$CB:$f" 2>/dev/null && printf '%s\n' "$f"
  done <<<"$NAMES"
  exit 0
fi
if [ "$BASE" = --edited ]; then
  # --edited <base> [<head>] (issue 496): `<path><TAB><lost lines><TAB><lost check lines>` per test file that exists at <base>
  # and loses a non-blank line by <head> (default: the index). An added line is no edit, so a new case stays free. A rename
  # counts as a delete: every old line is lost. A git failure exits 2.
  EB=${2:?usage: new-test-count.sh --edited <base> [<head>]} EH=${3-} SPAN=()
  [ -n "$EH" ] && SPAN=("$EB" "$EH") || SPAN=(--cached "$EB")
  NAMES=$(git --literal-pathspecs diff --no-renames --name-only -z "${SPAN[@]}" | tr '\0' '\n') \
    || { echo "new-test-count: git diff failed for $EB" >&2; exit 2; }
  while IFS= read -r f; do
    [ -n "$f" ] && is_test_path "$f" && git cat-file -e "$EB:$f" 2>/dev/null || continue
    # --text: a `-diff` attribute would print "Binary files differ", with no hunk to read a lost line from.
    D=$(git --literal-pathspecs diff --text --no-color --no-renames --no-ext-diff --no-textconv -U0 "${SPAN[@]}" -- "$f") \
      || { echo "new-test-count: git diff failed for $f" >&2; exit 2; }
    # Header lines (`--- a/x`) come before the first hunk, so they are never read as a lost line.
    awk -v p="$f" 'BEGIN { OFS = "\t" } /^@@/ { on = 1; next } on && /^-/ && substr($0, 2) ~ /[^ \t]/ { n++
      if (substr($0, 2) ~ /(^|[^A-Za-z0-9_])(expect|assert)([^A-Za-z0-9_]|$)|^[ \t]*check[ \t]/) c++ }
      END { if (n) print p, n, c + 0 }' <<<"$D"
  done <<<"$NAMES"
  exit 0
fi
FROM=$(git merge-base "$BASE" HEAD) || { echo "new-test-count: cannot find where HEAD left $BASE" >&2; exit 2; }
# The change as the pass will commit it, uncommitted and untracked files included: staged into a copy of the index.
IDX=$(mktemp) || exit 2; trap 'rm -f "$IDX"' EXIT
cp "$(git rev-parse --absolute-git-dir)/index" "$IDX" 2>/dev/null || : > "$IDX"
export GIT_INDEX_FILE=$IDX
git add -A && git reset -q -- .claude/briefs 2>/dev/null || { echo "new-test-count: cannot stage the change in a copy of the index" >&2; exit 2; }
FILES=$(git diff --cached --name-only --no-renames "$FROM") || { echo "new-test-count: git diff $FROM failed" >&2; exit 2; }
TESTS=$(while IFS= read -r f; do [ -n "$f" ] && is_test_path "$f" && echo "$f"; done <<<"$FILES")
# read, not $(cat <<'JS'): Bash 3.2 mis-parses a quoted here-document inside a command substitution.
IFS= read -r -d '' NTC_JS <<'JS' || true
// Reads direct JS/TS test calls with the TypeScript parser. stdin: [{path, src}]; stdout: [[name, ...], ...], or under
// NTC_SPANS=1 [[[name, first line, last line], ...], ...].
// The parser, not a text scan, so a string, comment, regex or template literal is never misread as code.
// Exit 3: the project has no typescript (the caller reads by its label regex). Exit 2: a typescript that is there fails
// to load or to parse, which no text count may hide.
const { createRequire } = require('module');
const req = createRequire(`${process.env.NTC_ROOT}/package.json`);
let ts, where;
try {
  where = req.resolve('typescript');
} catch (e) {
  process.stderr.write(`new-test-count: no typescript in ${process.env.NTC_ROOT}/node_modules; JS/TS test names are read by a label regex\n`);
  process.exit(3);
}
try {
  ts = req(where);
} catch (e) {
  process.stderr.write(`new-test-count: typescript at ${where} fails to load (${e.message}): run npm ci in ${process.env.NTC_ROOT}\n`);
  process.exit(2);
}
const MODS = new Set(['only', 'skip', 'concurrent', 'sequential', 'todo', 'fails', 'failing', 'each']);
const TEST = new Set(['it', 'test']);
const unwrap = (e) => {
  while (ts.isParenthesizedExpression(e) || ts.isAsExpression(e) || ts.isSatisfiesExpression(e)
    || ts.isNonNullExpression(e) || ts.isTypeAssertionExpression(e)) e = e.expression;
  return e;
};
// The callee less its modifier chain (`.only.each`) and an `.each` table call or tagged template before the call.
const base = (e) => {
  for (;;) {
    e = unwrap(e);
    if (ts.isPropertyAccessExpression(e) && MODS.has(e.name.text)) { e = e.expression; continue; }
    if ((ts.isCallExpression(e) || ts.isTaggedTemplateExpression(e)) && isEachTable(e)) { e = ts.isCallExpression(e) ? e.expression : e.tag; continue; }
    return e;
  }
};
const isEachTable = (n) => {
  let e = unwrap(ts.isCallExpression(n) ? n.expression : n.tag);
  while (ts.isPropertyAccessExpression(e) && MODS.has(e.name.text)) {
    if (e.name.text === 'each') return true;
    e = unwrap(e.expression);
  }
  return false;
};
// A test: a call whose callee, less modifiers, is the name `it` or `test`, or `.it`/`.test` on a receiver with a second
// argument (`t.test`, `ns.it`; `re.test(s)` takes one). An `.each` table call itself is not one; the call after it is.
// An alias or helper is not followed: an accepted gap.
// A skip gate, `test.skip(!ready, 'why')` inside a test: a `.skip` call whose first argument is no literal name and
// whose second is no function. `test.skip('name', () => {})` names a test and counts.
const isSkipGate = (n) => {
  let e = unwrap(n.expression), skip = false;
  while (ts.isPropertyAccessExpression(e) && MODS.has(e.name.text)) { skip = skip || e.name.text === 'skip'; e = unwrap(e.expression); }
  const [a, b] = n.arguments;
  return skip && !(a && (ts.isStringLiteral(a) || ts.isNoSubstitutionTemplateLiteral(a))) && !(b && (ts.isArrowFunction(b) || ts.isFunctionExpression(b)));
};
const isTest = (n) => {
  if (!ts.isCallExpression(n) || isEachTable(n) || isSkipGate(n)) return false;
  const e = base(n.expression);
  if (ts.isIdentifier(e)) return TEST.has(e.text);
  return ts.isPropertyAccessExpression(e) && TEST.has(e.name.text) && n.arguments.length >= 2;
};

function parse(path, src) {
  const kind = /\.[cm]?jsx$/.test(path) ? ts.ScriptKind.JSX : /\.tsx$/.test(path) ? ts.ScriptKind.TSX
    : /\.[cm]?js$/.test(path) ? ts.ScriptKind.JS : ts.ScriptKind.TS;
  const sf = ts.createSourceFile(path, src, ts.ScriptTarget.Latest, true, kind);
  const out = [];
  // Every call node is visited, so tests nested in tests count.
  const line = (p) => sf.getLineAndCharacterOfPosition(p).line + 1;
  const row = (n) => (process.env.NTC_SPANS ? [name(n), line(n.getStart(sf)), line(n.getEnd())] : name(n));
  const walk = (n) => { if (isTest(n)) out.push(row(n)); ts.forEachChild(n, walk); };
  walk(sf);
  return out;

  // The first argument's literal text, a backslash before a quote, a backtick or a backslash dropped (the runner's name;
  // js_regex reads by the same rule, any other escape kept as written), else its source text.
  function name(n) {
    const a = n.arguments[0];
    const lit = a && (ts.isStringLiteral(a) || ts.isNoSubstitutionTemplateLiteral(a));
    return !a ? '' : lit ? a.getText(sf).slice(1, -1).replace(/\\(['"`\\])/g, '$1') : a.getText(sf);
  }
}

let input = '';
process.stdin.on('data', (d) => { input += d; });
process.stdin.on('end', () => {
  let at = '';
  try {
    process.stdout.write(JSON.stringify(JSON.parse(input).map(({ path, src }) => { at = path; return parse(path, src); })));
  } catch (e) {
    process.stderr.write(`new-test-count: the typescript reader failed${at ? ` on ${at}` : ''}: ${e.message}\n`);
    process.exit(2);
  }
});
JS
# The reader loads typescript from the project (NTC_ROOT), not the plugin: a project without one is read by a label regex.
NTC_ROOT=$(git rev-parse --show-toplevel)
export NTC_JS NTC_ROOT
NTC_FROM=$FROM NTC_FILES=$TESTS python3 -I - <<'PY'
import json, os, re, subprocess, sys

root, base = os.environ['NTC_ROOT'], os.environ['NTC_FROM']
files = [f for f in os.environ['NTC_FILES'].split('\n') if f]

def show(rev, path):
    r = subprocess.run(['git', '-C', root, '--literal-pathspecs', 'show', f'{rev}:{path}'], capture_output=True)
    return r.stdout.decode('utf-8', 'replace') if r.returncode == 0 else ''

SH_CHECK = re.compile(r'^\s*check\s+(?:"((?:[^"\\]|\\.)*)"|\'([^\']*)\')')
def sh_tests(src):
    return [h.group(1) if h.group(1) is not None else h.group(2) for h in map(SH_CHECK.match, src.split('\n')) if h]

PY_DEF = re.compile(r'^\s*(?:async\s+)?def\s+(test\w*)\s*\(')
def py_tests(src):
    return [h.group(1) for h in map(PY_DEF.match, src.split('\n')) if h]

# Without typescript: a label after it( or test( (any modifier), after a one-line .each table call, or after the `])(`
# or backtick-paren that closes a table written over several lines. A gate has no string first argument, so it never matches.
STR = r'(?:"((?:[^"\\\n]|\\.)+)"|\'((?:[^\'\\\n]|\\.)+)\'|`((?:[^`\\\n]|\\.)+)`)'
JS_LABEL = re.compile(r'(?:\b(?:it|test)(?:\.(?!each\b)\w+)*\(|\b(?:it|test)(?:\.\w+)*\.each\b.*\)\(|^\s*(?:\]|`)\)\() *' + STR)
# The runner's name: a backslash before a quote, a backtick or a backslash dropped, the parser's rule.
UNESC = re.compile(r'\\([\'"`\\])')
def js_regex(src):
    out = []
    for l in src.split('\n'):
        h = None if l.lstrip().startswith('//') else JS_LABEL.search(l)
        if h: out.append(UNESC.sub(r'\1', next(g for g in h.groups() if g is not None)))
    return out

def fail(msg):
    sys.stderr.write(msg.rstrip('\n') + '\n')
    sys.exit(2)

def js_tests_all(items):
    # [(path, src)] -> one list of test names per item, from the TypeScript parser (NTC_JS). Only a project with no
    # typescript (the reader's exit 3, its line passed on) is read by the label regex; any other failure exits 2.
    if not items: return []
    r = subprocess.run(['node', '-e', os.environ['NTC_JS']], input=json.dumps([{'path': p, 'src': s} for p, s in items]),
                       capture_output=True, text=True)
    if r.returncode == 3:
        sys.stderr.write(r.stderr)
        return [js_regex(s) for _, s in items]
    if r.returncode != 0:
        fail(r.stderr.strip() or f'new-test-count: the typescript reader exited {r.returncode}')
    try:
        out = json.loads(r.stdout)
    except ValueError:
        out = None
    if not isinstance(out, list) or len(out) != len(items):
        fail('new-test-count: the typescript reader printed no list of names, one per file')
    return out

def read(rev, paths):
    srcs = [(f, show(rev, f)) for f in paths]
    js = iter(js_tests_all([(f, src) for f, src in srcs if not f.endswith(('.sh', '.py'))]))
    out = []
    for f, src in srcs:
        out += [(f, n) for n in (sh_tests(src) if f.endswith('.sh') else py_tests(src) if f.endswith('.py') else next(js))]
    return out

# A head test is kept only when its own file held a test of the same name at base (one for one); every other test,
# moved, renamed or copied, is new.
gone, added = list(read(base, files)), []
for t in read('', files):
    if t in gone: gone.remove(t)
    else: added.append(t)
print(len(added))
for _, n in added: print(n)
PY
