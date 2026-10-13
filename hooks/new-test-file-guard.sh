#!/usr/bin/env bash
# PreToolUse hook (Write): advise when a NEW test file imports a subject that
# another test file already covers.
#
# WHY. Nothing else stops a second test file being opened for a module that
# already has one. The suite grows, every file pays for it on every run, and the
# duplicate is caught only by a human reading a diff -- long after the cost is
# paid. A new file is the cheapest moment to say "add the case to the file that
# already covers this".
#
# SUBJECT = a relative module the file LOADS AT RUNTIME, decided by the
# TypeScript parser, that resolves on disk to a file OUTSIDE any __tests__
# directory and is not a helper (`helpers/`, `fixtures/`, or a basename
# containing `test-utils`). Exactly five node kinds name one: an
# `ImportDeclaration` that is not type-only and has a side-effect, default,
# namespace or non-type named binding; an `ExportDeclaration` re-exporting from a
# specifier and not type-only; an `ImportEqualsDeclaration` over
# `require()` and not type-only; a dynamic `import()` call outside any type node;
# and a `require()` call. A type position loads nothing, so it is neither a
# subject nor coverage of one -- and the parser never offers a comment, a string
# or a template literal as any of the five, which a text matcher cannot avoid.
# Comparison is on the RESOLVED repo-relative path, never on a basename:
# `foo/date.ts` and `bar/date.ts` are different subjects and must not be
# conflated. EVERY import is checked, not the first -- checking only the first
# makes import order an escape hatch.
#
# There is deliberately NO exemption by file name. A `*guard*` / `*parity*`
# carve-out would be walked through by renaming the file. The escape valve is
# different: a subject that genuinely needs a second file for process isolation
# is created from the MAIN CHECKOUT, where this hook stands down. That is now
# actually implemented -- the header claimed it for weeks while the hook checked
# nothing, so the documented way out did not exist. Topology is the test
# (`--git-dir` differs from `--git-common-dir` only in a linked worktree), the
# same one every other hook here uses to decide who is a worker.
#
# CEILING, stated. A subject reached only through a barrel re-export resolves to
# the barrel, not to the module behind it, so a duplicate that imports through
# one is allowed. Widening this to walk re-exports means resolving the module
# graph on every Write; the reviewer's diff read is the net instead. A file
# written by a shell heredoc is not seen either: this is a tripwire on the
# common path, not a boundary -- inferring a file
# write out of an arbitrary shell string is not a winnable parse, and a guard
# with known bypasses that poses as complete is worse than none.
#
# ITS OWN FAILURES ALLOW. Exit 2 refuses, exit 0 allows, and every error path
# here allows -- a missing TypeScript install included: a guard that cannot
# answer must not block a legitimate write.
#
# NOT a lib/edit-payload.sh consumer, deliberately. That helper pools the text
# of a Write, an Edit and a MultiEdit into one string for the content-screening
# hooks. This one is not screening content: it asks whether a file is being
# CREATED, which only a Write states, and an Edit or MultiEdit never does. It
# reads tool_input itself for that reason, and lets every other shape through.
#
# Self-test: bash hooks/__tests__/new-test-file-guard.test.sh
set -u
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0

command -v node >/dev/null 2>&1 || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-}"
[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$ROOT" ] && [ -d "$ROOT" ] || exit 0

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || HOOK_DIR="$ROOT"

# A linked worktree installs no packages, so the guard's parser lives only in
# the checkout they share. Without this the guard found no TypeScript in any
# worker worktree, allowed every write by its own error rule, and so ran
# nowhere: it stands down in the main checkout by design.
SHARED_ROOT=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  && SHARED_ROOT=$(dirname "$SHARED_ROOT") || SHARED_ROOT=""

# PREFILTER, IN SHELL, BEFORE NODE. node is the most expensive process on the
# write path -- it starts, loads the TypeScript compiler and walks the suite --
# so every condition it would answer with `allow()` is answered here first, for
# the price of one jq. A payload that is not a Write, does not name a
# `.test.ts(x)` path, or names a file that already exists can only ever have
# been allowed.
case "$INPUT" in *.test.ts*) ;; *) exit 0 ;; esac

IFS=$'\t' read -r TOOL_NAME RAW_PATH <<EOF
$(printf '%s' "$INPUT" | jq -r '[.tool_name // "", .tool_input.file_path // ""] | @tsv' 2>/dev/null)
EOF
[ "$TOOL_NAME" = Write ] || exit 0
case "$RAW_PATH" in
  *.test.ts|*.test.tsx) ;;
  *) exit 0 ;;
esac
case "$RAW_PATH" in
  /*) ABS_PATH="$RAW_PATH" ;;
  *)  ABS_PATH="$ROOT/$RAW_PATH" ;;
esac
[ -e "$ABS_PATH" ] && exit 0

# THE MAIN CHECKOUT IS THE ESCAPE VALVE, so the guard stands down there. A
# linked worktree is the only place `--git-dir` and `--git-common-dir` differ.
# A path that is no checkout at all answers neither, and two empty strings are
# equal -- so the test requires a real answer before it stands down. Silence is
# not permission.
GIT_DIR_HERE=$(git -C "$ROOT" rev-parse --git-dir 2>/dev/null)
if [ -n "$GIT_DIR_HERE" ] \
   && [ "$GIT_DIR_HERE" = "$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)" ]; then
  exit 0
fi

# The heredoc is the SCRIPT, so the payload still reaches node on stdin.
GUARD=$(cat <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');

const allow = () => process.exit(0);

const root = realpath(process.argv[1]);
const hookDir = process.argv[2] || root;
const sharedRoot = process.argv[3] ? realpath(process.argv[3]) : '';

function realpath(p) {
  try { return fs.realpathSync(p); } catch { return p; }
}

/** realpath as far as the path exists, so a not-yet-written file still resolves
 *  its directory's symlinks -- which is what the repo-relative compare needs. */
function realpathish(p) {
  return path.join(realpath(path.dirname(p)), path.basename(p));
}

function isFile(p) {
  try { return fs.statSync(p).isFile(); } catch { return false; }
}

/** TypeScript is resolved from the repo under test first, then from beside this
 *  hook, then from the checkout a linked worktree shares (the only place the
 *  packages are installed), then from the process cwd. Nothing found means no
 *  answer, so allow. */
function loadTypeScript() {
  for (const base of [root, hookDir, sharedRoot].filter(Boolean)) {
    try { return createRequire(path.join(base, 'noop.js'))('typescript'); } catch { /* next */ }
  }
  try { return require('typescript'); } catch { return null; }
}

const SUFFIXES = ['', '.ts', '.tsx', '.js', '/index.ts', '/index.tsx', '/index.js'];
// Every test file in the repo is parsed: ~1,100 files is about eight tenths of
// a second end to end, paid once per NEW test file WRITTEN and never on a test
// run. A text prefilter would be faster and
// would also be WRONG -- a test file next to its subject imports it as `..`,
// naming nothing a filter could match, so the duplicate it covers would slip
// through.
const SKIP_DIRS = new Set(['node_modules', '.git', 'dist', 'build', 'coverage', '.next']);

let ts = null;

function subjectSpecifiers(filePath, text) {
  // The kind follows the extension. Parsing a `.ts` file as TSX reads
  // `<T>(x) => x` as a JSX tag, and a parse that goes wrong mid-file can lose
  // the imports below it -- which is the guessing this parser exists to stop.
  const kind = filePath.endsWith('.tsx') ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
  const source = ts.createSourceFile(filePath, text, ts.ScriptTarget.Latest, true, kind);
  const seen = new Set();
  const out = [];

  const add = node => {
    if (node && ts.isStringLiteral(node) && node.text.startsWith('.') && !seen.has(node.text)) {
      seen.add(node.text);
      out.push(node.text);
    }
  };

  // An `import()` inside a type node is an ImportTypeNode's argument, not a
  // load; the walk refuses to read one as a call however it is nested.
  const inTypePosition = node => {
    for (let p = node.parent; p; p = p.parent) if (ts.isTypeNode(p)) return true;
    return false;
  };

  const visit = node => {
    if (ts.isImportDeclaration(node)) {
      const clause = node.importClause;
      if (!clause) {
        add(node.moduleSpecifier);
      } else if (!clause.isTypeOnly) {
        const bindings = clause.namedBindings;
        if (clause.name || (bindings && ts.isNamespaceImport(bindings))) {
          add(node.moduleSpecifier);
        } else if (bindings && ts.isNamedImports(bindings) && bindings.elements.some(e => !e.isTypeOnly)) {
          add(node.moduleSpecifier);
        }
      }
    } else if (ts.isExportDeclaration(node)) {
      const named = node.exportClause && ts.isNamedExports(node.exportClause) ? node.exportClause.elements : null;
      if (node.moduleSpecifier && !node.isTypeOnly && (!named || named.some(e => !e.isTypeOnly))) {
        add(node.moduleSpecifier);
      }
    } else if (ts.isImportEqualsDeclaration(node)) {
      if (!node.isTypeOnly && ts.isExternalModuleReference(node.moduleReference)) {
        add(node.moduleReference.expression);
      }
    } else if (ts.isCallExpression(node) && node.arguments.length === 1) {
      const dynamic = node.expression.kind === ts.SyntaxKind.ImportKeyword;
      const required = ts.isIdentifier(node.expression) && node.expression.text === 'require';
      if ((dynamic || required) && !inTypePosition(node)) add(node.arguments[0]);
    }
    ts.forEachChild(node, visit);
  };

  visit(source);
  return out;
}

/** The file a specifier names on disk, or null. Extension and index resolution
 *  both count, and a `.js` specifier may name a `.ts` source. */
function resolveSpec(fromDir, spec) {
  const base = path.normalize(path.join(fromDir, spec));
  for (const suffix of SUFFIXES) if (isFile(base + suffix)) return realpath(base + suffix);
  if (base.endsWith('.js')) {
    for (const ext of ['.ts', '.tsx']) {
      const candidate = base.slice(0, -3) + ext;
      if (isFile(candidate)) return realpath(candidate);
    }
  }
  return null;
}

function repoRelative(p) {
  const rel = path.relative(root, p);
  return rel.startsWith('..') ? null : rel.split(path.sep).join('/');
}

function isSubject(rel) {
  const parts = rel.split('/');
  if (parts.includes('__tests__')) return false;
  const dirs = parts.slice(0, -1);
  if (dirs.includes('helpers') || dirs.includes('fixtures')) return false;
  return !parts[parts.length - 1].includes('test-utils');
}

function subjectsOf(filePath, text) {
  const fromDir = path.dirname(filePath);
  const out = [];
  for (const spec of subjectSpecifiers(filePath, text)) {
    const target = resolveSpec(fromDir, spec);
    if (target === null) continue;
    const rel = repoRelative(target);
    if (rel && isSubject(rel) && !out.includes(rel)) out.push(rel);
  }
  return out;
}

/** Regular files only, and every entry is read inside the try: a device, FIFO
 *  or symlink named `*.test.ts` reads forever if opened, and an entry that is
 *  gone or unreadable by the time it is examined is skipped, never fatal. */
function testFiles(dir, found) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return found; }
  for (const entry of entries.sort((a, b) => (a.name < b.name ? -1 : 1))) {
    try {
      if (entry.isDirectory()) {
        if (!SKIP_DIRS.has(entry.name)) testFiles(path.join(dir, entry.name), found);
      } else if (entry.isFile() && (entry.name.endsWith('.test.ts') || entry.name.endsWith('.test.tsx'))) {
        found.push(path.join(dir, entry.name));
      }
    } catch { /* this entry only */ }
  }
  return found;
}

function main() {
  let event;
  try { event = JSON.parse(fs.readFileSync(0, 'utf8')); } catch { allow(); }

  if (!event || event.tool_name !== 'Write') allow();
  const input = event.tool_input || {};
  const rawPath = input.file_path || '';
  const content = input.content || '';
  if (!rawPath || !content) allow();
  if (!(rawPath.endsWith('.test.ts') || rawPath.endsWith('.test.tsx'))) allow();

  const filePath = realpathish(path.resolve(root, rawPath));
  if (fs.existsSync(filePath)) allow();

  ts = loadTypeScript();
  if (!ts) allow();

  const wanted = subjectsOf(filePath, content);
  if (wanted.length === 0) allow();

  const wantedSet = new Set(wanted);
  const coveredBy = new Map();
  for (const candidate of testFiles(root, [])) {
    const resolved = realpath(candidate);
    if (resolved === filePath) continue;
    let text;
    try { text = fs.readFileSync(resolved, 'utf8'); } catch { continue; }
    for (const rel of subjectsOf(resolved, text)) {
      if (wantedSet.has(rel) && !coveredBy.has(rel)) {
        coveredBy.set(rel, repoRelative(resolved) || candidate);
      }
    }
  }

  for (const rel of wanted) {
    const coverer = coveredBy.get(rel);
    if (coverer) {
      const message =
        `ADVISORY: ${repoRelative(filePath) || rawPath} imports ${rel}, which ${coverer} already covers.\n` +
        `Add your case to ${coverer} when the assertions do not require separate isolation or integration.\n`;
      process.stderr.write(message);
      process.stdout.write(`${JSON.stringify({
        systemMessage: message.trimEnd(),
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          additionalContext: message.trimEnd(),
        },
      })}\n`);
      return;
    }
  }

  allow();
}

try {
  main();
} catch {
  allow();
}
JS
)

# node's advice is a structured field on its stdout: capture it to classify the
# call, then pass it on byte for byte (the `.` keeps $( ) from eating newlines).
OUT=$(printf '%s' "$INPUT" | node -e "$GUARD" "$ROOT" "$HOOK_DIR" "$SHARED_ROOT"; RC=$?; printf .; exit "$RC")
RC=$?
OUT=${OUT%.}
[[ $OUT =~ \"additionalContext\"[[:space:]]*:[[:space:]]*\"[^\"] ]] && HOOK_FIRE_ADVISE=1
printf '%s' "$OUT"
exit "$RC"
