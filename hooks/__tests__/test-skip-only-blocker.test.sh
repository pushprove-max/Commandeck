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
check "a Playwright spec under e2e blocks"        2 "$(run "$(edit "$ROOT/web/e2e/flow/a.spec.ts" "$SKIP")")"
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

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
