#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
# Self-test for test-skip-only-blocker.sh.
#
# It pins that every test file is screened, whatever directory it sits in, and
# that `// skip-ok: <reason>` on the same line is the one pass.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/test-skip-only-blocker.sh"
ROOT=$(git rev-parse --show-toplevel)
PASS=0 FAIL=0

check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
edit() { jq -cn --arg fp "$1" --arg s "$2" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"", new_string:$s}}'; }
run()  { bash "$HOOK" >/dev/null 2>&1 <<<"$1"; echo $?; }

SKIP="$(printf 'test%s.%sskip(%s' '' '' "'x', () => {});")"
ONLY="$(printf 'it%s.%sonly(%s' '' '' "'x', () => {});")"

# --- blocked: a skip or a focus in a test file --------------------------------
check "a .spec file blocks"                       2 "$(run "$(edit "$ROOT/web/e2e/login.spec.ts" "$ONLY")")"
check "a test outside a __tests__ dir blocks"     2 "$(run "$(edit "$ROOT/src/services/thing.test.ts" "$SKIP")")"
check "a .test.js file blocks"                    2 "$(run "$(edit "$ROOT/src/services/__tests__/a.test.js" "$SKIP")")"
check "a test under scripts blocks"               2 "$(run "$(edit "$ROOT/scripts/__tests__/a.test.mjs" "$SKIP")")"
check "a walkthrough __tests__ file blocks"       2 "$(run "$(edit "$ROOT/web/e2e/walkthrough/__tests__/a.test.ts" "$SKIP")")"
check "the block names the offending form"        0 \
  "$(bash "$HOOK" 2>&1 >/dev/null <<<"$(edit "$ROOT/web/e2e/login.spec.ts" "$ONLY")" | grep -q 'only' && echo 0 || echo 1)"

# --- no directory is exempt ---------------------------------------------------
check "src/**/__tests__/*.test.ts blocks"         2 "$(run "$(edit "$ROOT/src/services/__tests__/a.test.ts" "$SKIP")")"
check "web/src/**/__tests__/*.test.tsx blocks"    2 "$(run "$(edit "$ROOT/web/src/components/__tests__/a.test.tsx" "$SKIP")")"

# --- the approved-skip marker -------------------------------------------------
check "// skip-ok: on the same line passes"       0 \
  "$(run "$(edit "$ROOT/web/e2e/login.spec.ts" "$SKIP // skip-ok: needs a physical card reader")")"
check "an approved skip is SILENT"                "" \
  "$(bash "$HOOK" 2>&1 <<<"$(edit "$ROOT/web/e2e/login.spec.ts" "$SKIP // skip-ok: needs a physical card reader")")"
check "the marker is per line, not per payload"   2 \
  "$(run "$(edit "$ROOT/web/e2e/login.spec.ts" "$SKIP // skip-ok: hardware
$SKIP")")"
check "the block explains the marker"             0 \
  "$(bash "$HOOK" 2>&1 >/dev/null <<<"$(edit "$ROOT/web/e2e/login.spec.ts" "$SKIP")" | grep -qF 'skip-ok:' && echo 0 || echo 1)"

# --- unchanged exemptions and ordinary work -----------------------------------
check "an ordinary test passes"                   0 "$(run "$(edit "$ROOT/web/e2e/login.spec.ts" "it('x', () => {});")")"
check "the word fit in a message passes"          0 \
  "$(run "$(edit "$ROOT/web/e2e/login.spec.ts" "assert.ok(v, 'the card does not fit the frame');")")"
check "the word fit before a paren in a message passes" 0 \
  "$(run "$(edit "$ROOT/web/e2e/login.spec.ts" "assert.ok(v, 'does not fit (see the spec)');")")"
check "a real fit( call still blocks"             2 \
  "$(run "$(edit "$ROOT/web/e2e/login.spec.ts" "fit('x', () => {});")")"
check "a hook self-test quoting the form is exempt" 0 \
  "$(run "$(edit "$ROOT/hooks/__tests__/x.test.sh" "$ONLY")")"
# A project's own folder named hooks (React's) holds real tests.
check "an application test under src/hooks blocks" 2 "$(run "$(edit "$ROOT/src/hooks/useThing.test.ts" "$ONLY")")"
check "and one in its __tests__ folder blocks"     2 "$(run "$(edit "$ROOT/src/hooks/__tests__/useThing.test.ts" "$ONLY")")"
check "by a relative path too"                     2 "$(run "$(edit "hooks/__tests__/useThing.test.ts" "$ONLY")")"
check "a non-test file passes"                    0 "$(run "$(edit "$ROOT/src/services/a.ts" "$ONLY")")"
check "a Bash payload passes"                     0 "$(run "$(jq -cn '{tool_name:"Bash",tool_input:{command:"ls"}}')")"
check "malformed JSON passes rather than wedging" 0 "$(run 'not json')"

# --- runner aliases (issue 439): `const itCompat = it` then `itCompat.only(` focused a suite past the literal names
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
write() { jq -cn --arg fp "$1" --arg s "$2" '{tool_name:"Write", tool_input:{file_path:$fp, content:$s}}'; }
AL="$(printf 'const itCompat = it;\nitCompat.%sonly(%s' '' "'x', () => {});")"
check "an aliased runner's .only in the same payload blocks (issue 439)" 2 "$(run "$(write "$D/a.test.ts" "$AL")")"
printf 'const itCompat = it;\n// end\n' > "$D/disk.test.ts"
check "an Edit whose alias is declared in the file on disk blocks (issue 439)" 2 \
  "$(run "$(jq -cn --arg fp "$D/disk.test.ts" --arg s "$(printf 'itCompat.%sonly(1);' '')" \
    '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"// end", new_string:$s}}')")"
check "an imported alias (it as nodeIt) .skip blocks (issue 439)" 2 \
  "$(run "$(write "$D/b.test.ts" "$(printf "import { it as nodeIt } from 'node:test';\nnodeIt.%sskip('x', () => {});" '')")")"
check "a .skip on a name that is no runner alias passes (issue 439)" 0 \
  "$(run "$(write "$D/c.test.ts" "$(printf 'const stream = getStream();\nstream.%sskip(2);' '')")")"
printf 'const stream = it;\n' > "$D/rebind.test.ts"
check "a Write that rebinds a former alias to ordinary code passes (issue 439)" 0 \
  "$(run "$(write "$D/rebind.test.ts" "$(printf 'const stream = getStream(); stream.%sskip(2);' '')")")"
# A declaration quoted in a fixture string or a comment binds nothing: it made `stream.skip(2)` a refused runner call.
check "an alias declared only inside a string or a comment passes (issue 439)" 0 \
  "$(run "$(write "$D/d.test.ts" "$(printf 'const fixture = "const stream = it;";\n// const a = it;\n/* const b = test; */ const c = `import { it as d }`;\nconst stream = getStream();\nstream.%sskip(2); a.%sonly(1); b.%sskip(1); d.%sskip(1);' '' '' '' '')")")"
# D2a: aliases bind only at a statement start of the raw text (no lexer). Every case of the plan's What can go wrong
# rows "Alias in a string or comment" and "Literal hides or fakes an alias", in the row's order; each lexer design
# before this one let one of them hide a real alias or bind a fake one. `@@` is a line break; <expected> <content>.
# Typed and multi-line renames are a documented known gap (simple renames only), not cases here.
TABLE_BAD=""
while IFS='|' read -r want content; do
  [ -n "$want" ] || continue
  got=$(run "$(write "$D/t.test.ts" "${content//@@/$'\n'}")")
  [ "$got" = "$want" ] || TABLE_BAD="$TABLE_BAD [$content: $got]"
done <<'EOF'
0|const fixture = "const stream = it;"; const stream = getStream(); stream.skip(2);
0|// const stream = it;@@const stream = getStream(); stream.skip(2);
0|/* const stream = it; */ const stream = getStream(); stream.skip(2);
0|const fixture = `const stream = it;`; const stream = getStream(); stream.skip(2);
0|const fixture = "const s = it;"; s.skip(2);
0|const fixture = /const s = it;/; s.skip(2);
0|// const a = it;@@a.skip(2);
0|/* const b = test; */ b.skip(2);
0|const t = `import { it as d }`; d.skip(2);
0|const t = `${`const s = it;`}`; s.skip(2);
2|const q = /"/; const c = it; c.only(1);
2|export default /`/;@@const compat = it;@@compat.only(1);@@const text = `x`;
2|const u = "http://x"; const c = it; c.only(1);
2|const v = a / b / 2; const c = it; c.only(1);
2|if (x) /"/.test(y); const c = it; c.only(1);
2|const r = /[/"]/; const c = it; c.only(1);
2|const t = `${"`"}`; const c = it; c.only(1);
2|const r = /\/\//; const c = it; c.only(1);
2|const u = "abc@@; const c = it; c.only(1);
2|const t = `abc@@; const c = it; c.only(1);
2|describe("x", () => { const c = it; c.only(1) })
2|/* note */ const c = it; c.only(1);
2|export const c = test.extend({}); c.only(1);
0|const msg = "it works"; // treat it as stream@@const stream = getStream(); stream.skip(2);
2|const s = "// skip-ok: x"; it.skip(1);
0|it.skip(1); // skip-ok: x
0|const f = test as Foo; Foo.skip(1);
EOF
check "every alias case found so far binds as the statement-start list says (issue 439)" "" "$TABLE_BAD"
# The guard keeps no state: a refused aliased Edit is refused again from the payload alone once its file is gone.
printf '// end\n' > "$D/retry.test.ts"
RETRY="$(jq -cn --arg fp "$D/retry.test.ts" --arg s "$(printf 'const c = it;\nc.%sonly(1);' '')" \
  '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"// end", new_string:$s}}')"
R1=$(run "$RETRY"); rm -f "$D/retry.test.ts"; R2=$(run "$RETRY")
check "an aliased Edit refused with its file on disk is refused again once the file is gone (issue 439)" "2 2" "$R1 $R2"

# Issue 441: the marker's reason is free text, so "doesn't" refused an approved skip; a quote open BEFORE the marker
# still puts the marker in a string, which licenses nothing. <expected>|<line>; <bt> is a backtick.
MARK_BAD=""
while IFS='|' read -r want content; do
  got=$(run "$(write "$D/m.test.ts" "${content//<bt>/\`}")")
  [ "$got" = "$want" ] || MARK_BAD="$MARK_BAD [$content: $got]"
done <<'EOF'
0|it.skip(1); // skip-ok: doesn't support Windows
0|it.skip("don't"); // skip-ok: x
2|const s = "// skip-ok: it's"; it.skip(1);
2|const s = '// skip-ok: x'; it.skip(1);
2|const s = <bt>// skip-ok: x<bt>; it.skip(1);
0|const s = "// skip-ok: x"; it.skip(1); // skip-ok: y
EOF
check "a skip-ok reason holding an apostrophe or quote passes, and a marker inside a string still blocks (issue 441)" "" "$MARK_BAD"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
