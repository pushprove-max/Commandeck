#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
# Self-test for new-test-file-guard.sh: a new test file gets consolidation
# advice when another test file already covers a subject it imports.
#
# WHAT EACH GROUP PINS, and why it is the case that can fail:
#   - resolved paths, not basenames: `foo/date.ts` and `bar/date.ts` share a
#     basename and are different subjects. A guard that compared basenames would
#     advise on the second one, and the advice would look correct.
#   - EVERY import, not the first: a file whose first import is untested and
#     whose second is covered must still be noticed, or import order is a free
#     escape hatch.
#   - no exemption by name: a `*guard*` / `*parity*` file gets advice like any
#     other, because renaming does not change the consolidation opportunity.
#   - the allow paths: helpers, fixtures, test-utils, imports inside __tests__,
#     an existing file, a non-test path, an Edit payload, malformed JSON. Each
#     is a legitimate write that stays silent, and without them a guard that
#     advised on everything would pass every case above.
#   - what the file LOADS: a type-only import executes nothing, so it is not a
#     subject and does not cover one. A dynamic `import(` written across lines
#     does load, so it is. Both directions are pinned, with two value-import
#     controls, because a `specs()` that returned nothing would pass every
#     type-only case on its own.
#   - the grammar a text matcher has to guess at: an import-type expression, a
#     `$` in a type name, a string literal that opens a comment, a module named
#     inside a template literal, `import x = require()`, and a re-export. Each
#     was answered wrongly in one direction or the other before the TypeScript
#     parser decided them, and each direction costs something different -- a
#     wrong advice adds noise to a legitimate write, while a missed warning
#     hides a consolidation opportunity.
#   - a path that is not a regular file, and one the walk can name but not
#     examine: a device or FIFO named `*.test.ts` is never opened, so the guard
#     answers instead of reading forever, and an entry that cannot be statted is
#     skipped rather than crashing the guard.
#   - the Codex lane: codex-dispatch.sh turns an `apply_patch` `Add File` into
#     one Write payload, so the same advice must be visible there too.
#
# The repo is a throwaway with a planted module tree, so every outcome is exact
# and nothing here reads the machine's real Codex home or the real suite.
set -u

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS/new-test-file-guard.sh"
SETTINGS="$HOOKS/hooks.json"
PASS=0 FAIL=0 SKIP=0
# THE PARSER IS THE PROJECT'S. The hook asks the TypeScript the project under
# guard has installed, and the plugin installs none, so every case that expects
# an answer from the parser needs one lent to it: COMMANDECK_TEST_NODE_MODULES
# names a node_modules directory holding `typescript`. Without it those cases
# are counted as skipped, out loud, and only the stand-down cases run.
TS_MODULES=${COMMANDECK_TEST_NODE_MODULES:-}
[ -n "$TS_MODULES" ] && [ -f "$TS_MODULES/typescript/package.json" ] || TS_MODULES=""
NO_MODULES=/nonexistent/node_modules
skip() { SKIP=$((SKIP + 1)); echo "skip $1 (no TypeScript install)"; }

check() {
  if [ -z "$TS_MODULES" ] && { [ "$2" = 2 ] || [ "$2" = true ]; }; then skip "$1"; return; fi
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1)); echo "ok   $1"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $1 (expected $2, got $3)"
  fi
}

check_match() { # label, regex, text
  if [ -z "$TS_MODULES" ]; then skip "$1"; return; fi
  if printf '%s' "$3" | grep -qE "$2"; then
    PASS=$((PASS + 1)); echo "ok   $1"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $1 (no /$2/ in: $3)"
  fi
}

TMP=$(mktemp -d /tmp/new-test-file-guard-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# The fixture is a LINKED WORKTREE, because that is where the guard applies: it
# stands down in the main checkout, which is the documented escape valve for a
# subject that genuinely needs a second file. A plain `git init` fixture would
# be a main checkout and every refusal case below would pass for the wrong
# reason.
BASE="$TMP/base"
mkdir -p "$BASE"
git init -q -b main "$BASE"
git -C "$BASE" config user.email t@t.t
git -C "$BASE" config user.name t
git -C "$BASE" commit -q --allow-empty -m init
REPO="$TMP/repo"
git -C "$BASE" worktree add -q -b unit "$REPO"
mkdir -p "$REPO/.claude/hooks"
REPO=$(cd "$REPO" && pwd -P)
# The guard parses with TypeScript, so the throwaway repo needs it resolvable
# from its own root -- otherwise the guard finds no parser, allows everything,
# and every refusal case below fails for a reason that is not the guard.
ln -sfn "${TS_MODULES:-$NO_MODULES}" "$REPO/node_modules"

mkdir -p "$REPO/src/services/__tests__" "$REPO/src/widgets/__tests__" \
         "$REPO/src/lib/__tests__" "$REPO/src/helpers" "$REPO/src/fixtures" \
         "$REPO/src/config/__tests__" "$REPO/foo/__tests__" "$REPO/bar/__tests__"

# --- the module tree under test ----------------------------------------------
echo 'export const createTransfer = () => 1;'  > "$REPO/src/services/transfer-service.ts"
echo 'export const scoreRisk = () => 2;'       > "$REPO/src/services/untested.ts"
echo 'export const shim = () => 3;'            > "$REPO/src/services/test-utils-shim.ts"
echo 'export const build = () => 4;'           > "$REPO/src/helpers/build.ts"
echo 'export const rows = [];'                 > "$REPO/src/fixtures/rows.ts"
echo 'export const Panel = () => null;'        > "$REPO/src/widgets/panel.tsx"
echo 'export const api = () => 5;'             > "$REPO/src/lib/index.ts"
echo 'export const fmt = () => "foo";'         > "$REPO/foo/date.ts"
echo 'export const fmt = () => "bar";'         > "$REPO/bar/date.ts"
echo 'export const setup = () => 6;'           > "$REPO/src/services/__tests__/shared-setup.ts"
echo 'export interface Only { a: string }'     > "$REPO/src/services/typed-only-subject.ts"
echo 'export const dyn = () => 7;'             > "$REPO/src/services/dyn-subject.ts"

# --- the test files that already cover them ----------------------------------
printf "import { createTransfer } from '../transfer-service';\n" \
  > "$REPO/src/services/__tests__/transfer-service.test.ts"
printf "import { Panel } from '../panel';\n" \
  > "$REPO/src/widgets/__tests__/panel.test.tsx"
printf "import { api } from '..';\n" \
  > "$REPO/src/lib/__tests__/lib.test.ts"
printf "import { fmt } from '../date';\n" \
  > "$REPO/bar/__tests__/date.test.ts"
# The allow cases below are only meaningful because these subjects ARE imported
# by an existing test file: without the helper/fixture/__tests__ exclusions the
# guard would find a coverer and refuse.
printf "import { build } from '../../helpers/build';\nimport { rows } from '../../fixtures/rows';\nimport { shim } from '../test-utils-shim';\nimport { setup } from './shared-setup';\n" \
  > "$REPO/src/services/__tests__/existing-helpers.test.ts"
# The only mention of typed-only-subject anywhere is a type import, which loads
# nothing; the only mention of dyn-subject is a dynamic import written across
# lines, which loads.
printf "import type { Only } from '../typed-only-subject';\n" \
  > "$REPO/src/services/__tests__/typed-only.test.ts"
printf "const m = await import(\n  '../dyn-subject'\n);\n" \
  > "$REPO/src/services/__tests__/dyn.test.ts"
cat > "$REPO/src/config/config.js" <<'JS'
module.exports = { mode: process.env.MODE || 'baseline' };
JS
cat > "$REPO/src/config/renderer.js" <<'JS'
module.exports = config => `mode=${config.mode}`;
JS
cat > "$REPO/src/config/__tests__/config.test.ts" <<'TS'
const assert = require('node:assert/strict');
const config = require('../config.js');
assert.strictEqual(config.mode, 'baseline');
TS

write() { # file_path, content -> payload
  jq -cn --arg fp "$1" --arg c "$2" '{tool_name:"Write", tool_input:{file_path:$fp, content:$c}}'
}

# `timeout` so a guard that reads forever FAILS its case (exit 124) instead of
# hanging this script and every runner above it.
run() { # payload -> 0 silent success, 2 visible advisory success, other failure
  local out err rc
  out=$(mktemp "$TMP/native-XXXXXX")
  err=$(mktemp "$TMP/advisory-XXXXXX")
  CLAUDE_PROJECT_DIR="$REPO" timeout 20 bash "$HOOK" >"$out" 2>"$err" <<<"$1"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo 99
  elif [ -s "$out" ]; then
    jq -e '.systemMessage | test("already covers")' "$out" >/dev/null 2>&1 \
      && grep -q 'already covers' "$err" && echo 2 || echo 98
  elif [ -s "$err" ]; then
    echo 97
  else
    echo 0
  fi
  rm -f "$out" "$err"
}

run_err() { # payload -> stderr
  CLAUDE_PROJECT_DIR="$REPO" timeout 20 bash "$HOOK" 2>&1 >/dev/null <<<"$1"
}

NEW="$REPO/src/services/__tests__/second-transfer.test.ts"
DUP=$(write "$NEW" "import { createTransfer } from '../transfer-service';
")

# --- historical main-checkout stand-down -------------------------------------
# A plain `git init` tree is the main checkout, where the hook remains silent.
MAIN="$TMP/mainco"
mkdir -p "$MAIN/src/services/__tests__"
git init -q -b main "$MAIN"
MAIN=$(cd "$MAIN" && pwd -P)
ln -sfn "${TS_MODULES:-$NO_MODULES}" "$MAIN/node_modules"
echo 'export const createTransfer = () => 1;' > "$MAIN/src/services/transfer-service.ts"
printf "import { createTransfer } from '../transfer-service';\n" \
  > "$MAIN/src/services/__tests__/transfer-service.test.ts"
MAIN_DUP=$(write "$MAIN/src/services/__tests__/second-transfer.test.ts" \
  "import { createTransfer } from '../transfer-service';
")
check "the same duplicate is allowed from the main checkout" 0 \
  "$(CLAUDE_PROJECT_DIR="$MAIN" timeout 20 bash "$HOOK" >/dev/null 2>&1 <<<"$MAIN_DUP"; echo $?)"
check "standing down in the main checkout is SILENT" "" \
  "$(CLAUDE_PROJECT_DIR="$MAIN" timeout 20 bash "$HOOK" 2>&1 <<<"$MAIN_DUP")"

# ...but a tree that is NO CHECKOUT AT ALL is not a main checkout. Both git
# questions answer nothing there, and two empty strings compare equal -- which
# turned every fixture outside a repo into an escape valve.
NOGIT="$TMP/nogit"
mkdir -p "$NOGIT/src/services/__tests__"
NOGIT=$(cd "$NOGIT" && pwd -P)
ln -sfn "${TS_MODULES:-$NO_MODULES}" "$NOGIT/node_modules"
echo 'export const createTransfer = () => 1;' > "$NOGIT/src/services/transfer-service.ts"
printf "import { createTransfer } from '../transfer-service';\n" \
  > "$NOGIT/src/services/__tests__/transfer-service.test.ts"
check "a duplicate outside any checkout is allowed with advice" 0 \
  "$(CLAUDE_PROJECT_DIR="$NOGIT" timeout 20 bash "$HOOK" >/dev/null 2>&1 <<<"$(write \
     "$NOGIT/src/services/__tests__/second-transfer.test.ts" \
     "import { createTransfer } from '../transfer-service';
")"; echo $?)"
NOGIT_OUT=$(CLAUDE_PROJECT_DIR="$NOGIT" timeout 20 bash "$HOOK" 2>/dev/null <<<"$(write \
  "$NOGIT/src/services/__tests__/second-transfer.test.ts" \
  "import { createTransfer } from '../transfer-service';")")
check "outside-checkout advice is native-visible" true \
  "$(printf '%s' "$NOGIT_OUT" | jq -r '.systemMessage | contains("transfer-service.test.ts")')"

# --- a worktree with no packages of its own ----------------------------------
# The parser lives in node_modules and a unit worktree installs none, so this
# case is the real worker one: the WORKTREE's copy of the hook, with packages
# only in the shared checkout. Every other case here runs the main checkout's
# copy and hands the fixture a node_modules symlink, which is why the suite was
# green for weeks while the guard answered nothing in an actual worktree -- and
# it stands down in the main checkout, so it was refusing and advising NOWHERE.
WT_HOOK="$REPO/hooks/new-test-file-guard.sh"
mkdir -p "$REPO/hooks"; cp -R "$HOOKS/lib" "$REPO/hooks/"
cp "$HOOK" "$WT_HOOK"
rm -f "$REPO/node_modules"
ln -sfn "${TS_MODULES:-$NO_MODULES}" "$BASE/node_modules"
check_match "a worktree with no packages advises from the shared checkout" \
  "transfer-service\.test\.ts" \
  "$(cd "$REPO" && CLAUDE_PROJECT_DIR="$REPO" timeout 20 bash "$WT_HOOK" 2>&1 >/dev/null <<<"$DUP")"
rm -rf "$BASE/node_modules" "$REPO/hooks"
ln -sfn "${TS_MODULES:-$NO_MODULES}" "$REPO/node_modules"

# --- the shell filter answers before node starts ------------------------------
# Everything node would have answered with allow() is decided in shell first, so
# an ordinary write never pays for a TypeScript load and a suite walk.
check "a .spec.ts write is allowed"                0 \
  "$(run "$(write "$REPO/src/services/__tests__/second-transfer.spec.ts" \
    "import { createTransfer } from '../transfer-service';")")"
check "a .test.js write is allowed"                0 \
  "$(run "$(write "$REPO/src/services/__tests__/second-transfer.test.js" \
    "require('../transfer-service');")")"
check "a MultiEdit payload naming a test file is allowed" 0 \
  "$(run "$(jq -cn --arg fp "$NEW" '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[{old_string:"a", new_string:"b"}]}}')")"
check "a relative in-scope path still resolves"    2 \
  "$(run "$(write "src/services/__tests__/second-transfer.test.ts" \
    "import { createTransfer } from '../transfer-service';")")"

# --- advised: another test file already covers the subject -------------------
check "a second test file for a covered subject gets visible advice" 2 "$(run "$DUP")"
check_match "the advice names the subject" 'src/services/transfer-service\.ts' "$(run_err "$DUP")"
check_match "the advice names the covering test file" \
  'src/services/__tests__/transfer-service\.test\.ts' "$(run_err "$DUP")"
check_match "the advice suggests adding the case there" 'Add your case to' "$(run_err "$DUP")"

# Different assertions can legitimately require another module graph or an
# integration boundary. Both writes succeed while still surfacing the shared
# configuration subject and its covering test as consolidation advice.
ISOLATION=$(write "$REPO/src/config/__tests__/config-isolated.test.ts" \
  "process.env.MODE = 'isolated';
const assert = require('node:assert/strict');
const config = require('../config.js');
assert.strictEqual(config.mode, 'isolated');")
check "module-load environment isolation is allowed with visible advice" 2 "$(run "$ISOLATION")"
INTEGRATION=$(write "$REPO/src/config/__tests__/config-renderer.test.ts" \
  "const assert = require('node:assert/strict');
const config = require('../config.js');
const render = require('../renderer.js');
assert.strictEqual(render(config), 'mode=baseline');")
check "configuration-to-renderer integration is allowed with visible advice" 2 "$(run "$INTEGRATION")"

# EVERY import, not the first. An untested module on line 1 must not buy a pass
# for the covered module on line 2 -- the author chooses the order.
check "an untested import FIRST does not excuse a covered import second" 2 \
  "$(run "$(write "$REPO/src/services/__tests__/ordered.test.ts" "import { scoreRisk } from '../untested';
import { createTransfer } from '../transfer-service';
")")"

check "a .tsx duplicate gets advice" 2 \
  "$(run "$(write "$REPO/src/widgets/__tests__/second-panel.test.tsx" "import { Panel } from '../panel';
")")"
check "an index import resolves to the same advised subject" 2 \
  "$(run "$(write "$REPO/src/lib/__tests__/second-lib.test.ts" "import { api } from '../../lib';
")")"
check "a .js specifier resolving to a .ts source gets advice" 2 \
  "$(run "$(write "$NEW" "import { createTransfer } from '../transfer-service.js';
")")"

# NO EXEMPTION BY NAME. A carve-out for guard/parity/conformance/coverage names
# would be walked through by renaming the file.
for name in second-transfer.guard second-transfer.parity second-transfer.conformance second-transfer.coverage; do
  check "a *${name##*.}* name gets advice like any other" 2 \
    "$(run "$(write "$REPO/src/services/__tests__/$name.test.ts" "import { createTransfer } from '../transfer-service';
")")"
done

# --- resolved paths, never basenames -----------------------------------------
check "a same-basename subject in another directory is allowed" 0 \
  "$(run "$(write "$REPO/foo/__tests__/date.test.ts" "import { fmt } from '../date';
")")"
check "a same-basename subject in another directory is SILENT" "" \
  "$(run_err "$(write "$REPO/foo/__tests__/date.test.ts" "import { fmt } from '../date';
")")"
# The control: the SAME subject, so a guard that had simply stopped finding
# anything would fail here rather than pass the case above.
check "a second file for the tested same-basename subject gets advice" 2 \
  "$(run "$(write "$REPO/bar/__tests__/date-extra.test.ts" "import { fmt } from '../date';
")")"

# --- allowed: nothing covers it, or it is not a subject ----------------------
check "a subject with no test at all is allowed" 0 \
  "$(run "$(write "$REPO/src/services/__tests__/untested.test.ts" "import { scoreRisk } from '../untested';
")")"
check "helpers, fixtures and test-utils are not subjects" 0 \
  "$(run "$(write "$REPO/src/services/__tests__/new-helpers.test.ts" "import { build } from '../../helpers/build';
import { rows } from '../../fixtures/rows';
import { shim } from '../test-utils-shim';
")")"
check "an import inside __tests__ is not a subject" 0 \
  "$(run "$(write "$REPO/src/services/__tests__/new-setup.test.ts" "import { setup } from './shared-setup';
")")"
check "a commented-out import is not a subject" 0 \
  "$(run "$(write "$NEW" "// import { createTransfer } from '../transfer-service';
")")"
check "a package import is not a subject" 0 \
  "$(run "$(write "$NEW" "import { test } from 'node:test';
")")"
check "an unresolvable relative import is not a subject" 0 \
  "$(run "$(write "$NEW" "import { gone } from '../not-on-disk';
")")"

# --- a subject is what the file LOADS ----------------------------------------
# A type import executes nothing, so a module that only ever appears in type
# positions has no test yet and its first real one must not be refused -- there
# is no override for a wrong refusal. A dynamic `import(` does load, however it
# is wrapped across lines. D and J are the value-import controls: without them a
# specs() that returned nothing at all would pass every case above them.
check "A type-only import is not a subject" 0 \
  "$(run "$(write "$NEW" "import type { T } from '../transfer-service';
")")"
check "B inline all-type import is not a subject" 0 \
  "$(run "$(write "$NEW" "import { type T } from '../transfer-service';
")")"
check "C multi-line type-only import is not a subject" 0 \
  "$(run "$(write "$NEW" "import type {
  T,
} from '../transfer-service';
")")"
check "D mixed inline import IS a subject" 2 \
  "$(run "$(write "$NEW" "import { type T, createTransfer } from '../transfer-service';
")")"
check "E a type-only coverer does not cover" 0 \
  "$(run "$(write "$NEW" "import { only } from '../typed-only-subject';
")")"
check "F multi-line dynamic import is a subject" 2 \
  "$(run "$(write "$NEW" "const m = await import(
  '../transfer-service'
);
")")"
check "G multi-line dynamic import in a coverer covers" 2 \
  "$(run "$(write "$NEW" "import { x } from '../dyn-subject';
")")"
check "H block comment across lines is not a subject" 0 \
  "$(run "$(write "$NEW" "/*
import { createTransfer } from '../transfer-service';
*/
")")"
check "I \`typeof import\` position is not a subject" 0 \
  "$(run "$(write "$NEW" "declare const m: typeof import('../transfer-service');
")")"
check "J value import beside a type import still counts" 2 \
  "$(run "$(write "$NEW" "import type { T } from '../transfer-service';
import { createTransfer } from '../transfer-service';
")")"

# L-S. The forms a text matcher decides by guessing at TypeScript's grammar, and
# gets wrong in both directions: L, M and P are legitimate writes it refuses, and
# O and S are duplicates it lets through. The parser answers each by the node
# kind, so a `$` in a type name, a string that looks like a comment opener and a
# module named inside a template literal are no longer special cases.
check "L an import-type expression is not a subject" 0 \
  "$(run "$(write "$NEW" "type R = import('../transfer-service').Transfer;
")")"
check "M a \$ in an all-type inline import is not a subject" 0 \
  "$(run "$(write "$NEW" "import { type \$A, type B as C } from '../transfer-service';
")")"
check "N a type import-equals before a value import still counts" 2 \
  "$(run "$(write "$NEW" "import type A = require('../transfer-service');
import { createTransfer } from '../transfer-service';
")")"
check "O a '/*' string literal does not hide the import after it" 2 \
  "$(run "$(write "$NEW" "const o = '/*';
import { createTransfer } from '../transfer-service';
const c = '*/';
")")"
check "P an import inside a template literal is not a subject" 0 \
  "$(run "$(write "$NEW" "const s = \`import { x } from '../transfer-service'\`;
")")"
check "Q an import-equals require IS a subject" 2 \
  "$(run "$(write "$NEW" "import A = require('../transfer-service');
")")"
check "R a re-export IS a subject" 2 \
  "$(run "$(write "$NEW" "export { createTransfer } from '../transfer-service';
")")"
check "S an \`export type\` re-export is not a subject" 0 \
  "$(run "$(write "$NEW" "export type { Transfer } from '../transfer-service';
")")"
# the per-specifier form is elided the same way as `export type { }`.
check "S2 an all-inline-type re-export is not a subject" 0 \
  "$(run "$(write "$NEW" "export { type Transfer } from '../transfer-service';
")")"
check "S3 a re-export with one value specifier IS a subject" 2 \
  "$(run "$(write "$NEW" "export { type Transfer, createTransfer } from '../transfer-service';
")")"

# T. The parser is error-tolerant, so a half-written file still yields a tree and
# the imports above the mistake are still read. A parser that threw here would
# fail open and admit the duplicate.
check "T a syntax error later in the file does not lose the import" 2 \
  "$(run "$(write "$NEW" "import { createTransfer } from '../transfer-service';
const = ;
")")"

# U. A coverer the walk can NAME but cannot examine. A mid-walk delete is the
# same defect and cannot be timed reliably, so the directory keeps read
# permission (the name is still listed) and loses execute (the stat on the child
# fails). Examining each entry inside the try makes that one entry skipped; an
# unguarded stat crashes the guard, which is exit 1 -- neither a refusal nor an
# allow, and a hook exit of 1 is what the harness shows the author as an error.
printf "import { createTransfer } from '../transfer-service';\n" \
  > "$REPO/src/config/__tests__/unstatable.test.ts"
chmod 0444 "$REPO/src/config/__tests__"
check "U an entry the walk cannot stat is skipped, not fatal" 2 "$(run "$DUP")"
chmod 0755 "$REPO/src/config/__tests__"
rm -f "$REPO/src/config/__tests__/unstatable.test.ts"

# K. A path named like a test file that is not a regular file. Opening it reads
# until the process is killed, which takes the whole turn down with it -- so it
# is never opened, and the guard still answers about the real coverers.
ln -s /dev/zero "$REPO/src/config/__tests__/zero.test.ts"
check "K a non-regular test path does not wedge" 2 "$(run "$DUP")"
rm -f "$REPO/src/config/__tests__/zero.test.ts"

# --- allowed: not a new test file at all -------------------------------------
check "an EXISTING test file is allowed" 0 \
  "$(run "$(write "$REPO/src/services/__tests__/transfer-service.test.ts" "import { createTransfer } from '../transfer-service';
")")"
check "a non-test file is allowed" 0 \
  "$(run "$(write "$REPO/src/services/new-service.ts" "import { createTransfer } from './transfer-service';
")")"
check "an Edit payload is allowed" 0 \
  "$(run "$(jq -cn --arg fp "$NEW" --arg n "import { createTransfer } from '../transfer-service';" \
      '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"a", new_string:$n}}')")"
check "a Write with no content is allowed" 0 \
  "$(run "$(jq -cn --arg fp "$NEW" '{tool_name:"Write", tool_input:{file_path:$fp}}')")"
check "a Bash payload is allowed" 0 \
  "$(run "$(jq -cn '{tool_name:"Bash", tool_input:{command:"ls"}}')")"
check "malformed JSON passes rather than wedging" 0 "$(run 'not json')"

# --- producer/consumer: registered where its fields exist ---------------------
# Unregistered, the hook is indistinguishable from one that always allows.
# It only ever advises on a NEW file, so it sits on a Write-only matcher: an Edit
# or a MultiEdit cannot create one, and launching it for those was the cost.
check "registered on a matcher a Write reaches" 0 \
  "$(jq -e '.hooks.PreToolUse[] | .matcher as $m | select("Write" | test("^(" + $m + ")$"))
            | .hooks[] | select(.command | endswith("new-test-file-guard.sh\""))' "$SETTINGS" >/dev/null && echo 0 || echo 1)"
check "NOT registered on a matcher an Edit reaches" 0 \
  "$(jq -e '.hooks.PreToolUse[] | .matcher as $m | select("Edit" | test("^(" + $m + ")$"))
            | .hooks[] | select(.command | endswith("new-test-file-guard.sh\""))' "$SETTINGS" >/dev/null && echo 1 || echo 0)"
# --- the Codex lane ----------------------------------------------------------
# codex-dispatch.sh turns an `apply_patch` `Add File` into one Write payload per
# file, so the guard must surface the same advice there. The project is set up
# for the plugin, and a plugin folder of its own holds the real dispatcher and
# this one hook, with its own trusted Codex home.
mkdir -p "$REPO/.claude"; echo '{"version": 1}' > "$REPO/.claude/commandeck.json"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || git -C "$REPO" init -q
CP=$TMP/codex-plugin; mkdir -p "$CP/hooks/lib"
cp "$HOOKS/codex-dispatch.sh" "$HOOK" "$CP/hooks/"; cp "$HOOKS"/lib/*.sh "$CP/hooks/lib/"
jq -n --arg h "${HOOK##*/}" '{hooks: {PreToolUse: [{matcher: "Edit|Write|MultiEdit",
  hooks: [{type: "command", command: ("${CLAUDE_PLUGIN_ROOT}/hooks/" + $h)}]}]}}' > "$CP/hooks/hooks.json"
CODEX_HOME_DIR="$TMP/codex-home"
mkdir -p "$CODEX_HOME_DIR"
printf '[projects."%s"]\ntrust_level = "trusted"\n' "$REPO" > "$CODEX_HOME_DIR/config.toml"

patch_payload() { # add-file path, body -> payload
  jq -cn --arg cwd "$REPO" --arg p "*** Begin Patch
*** Add File: $1
+$2
*** End Patch
" '{session_id:"selftest", cwd:$cwd, hook_event_name:"PreToolUse", tool_name:"apply_patch", tool_input:{command:$p}}'
}

dispatch() { # payload -> exit code
  env "CODEX_HOME=$CODEX_HOME_DIR" "XDG_CACHE_HOME=$TMP/cache" \
    bash "$CP/hooks/codex-dispatch.sh" >/dev/null 2>&1 <<<"$1"; echo $?
}
dispatch_err() { # payload -> stderr
  env "CODEX_HOME=$CODEX_HOME_DIR" "XDG_CACHE_HOME=$TMP/cache" \
    bash "$CP/hooks/codex-dispatch.sh" 2>&1 >/dev/null <<<"$1"
}

CODEX_DUP=$(patch_payload "src/services/__tests__/codex-second.test.ts" \
  "import { createTransfer } from '../transfer-service';")
check "a Codex Add File duplicate is allowed" 0 "$(dispatch "$CODEX_DUP")"
check_match "the Codex advisory names the covering test file" \
  'src/services/__tests__/transfer-service\.test\.ts' "$(dispatch_err "$CODEX_DUP")"
check "a Codex Add File for an untested subject is allowed" 0 \
  "$(dispatch "$(patch_payload "src/services/__tests__/codex-untested.test.ts" \
      "import { scoreRisk } from '../untested';")")"
# It must run for Codex: the marker would take the whole Codex lane out.
check "carries no \`# codex: skip\` marker" 0 \
  "$(head -40 "$HOOK" | grep -q '^# codex: skip' && echo 1 || echo 0)"

echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
