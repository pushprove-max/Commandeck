#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
# Self-test for staged-index-warn.sh. Exit 0 on success; non-zero naming the
# failing case otherwise. Run by src/config/__tests__/hook-selftest-coverage.guard.test.ts.
#
# The narrowing it pins: the warning belongs at the suite, not at every edit.
# It used to run PostToolUse on Edit|Write|MultiEdit, paying two git scans per
# edit to report a condition that only matters when tests read the tree -- and
# landing nowhere near the green summary it qualifies. It now runs after the
# test command itself and ignores every other Bash call.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/staged-index-warn.sh"
PASS=0; FAIL=0
note() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
ok()   { PASS=$((PASS+1)); }
# The hook reads the payload checkout and answers only for a test run.
payload() {
  jq -cn --arg c "$1" --arg cwd "$2" \
    '{tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}'
}
run() {
  local cmd="${1:-npm run test:guards}" cwd="${2:-$REPO}"
  bash "$HOOK" 2>&1 <<<"$(payload "$cmd" "$cwd")"
}
native_out() {
  local cmd="${1:-npm run test:guards}" cwd="${2:-$REPO}"
  bash "$HOOK" 2>/dev/null <<<"$(payload "$cmd" "$cwd")"
}

TMP=$(mktemp -d)
export TMPDIR="$TMP/markers"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name t
echo one > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit -qm init

# Case 1: clean index -> silent, exit 0.
out=$(cd "$REPO" && run); rc=$?
if [ "$rc" -eq 0 ]; then ok; else note "clean index should exit 0, got $rc"; fi
if [ -z "$out" ]; then ok; else note "clean index should print nothing, got: $out"; fi

# Case 2: ordinary staging leaves index and working copy equal -> silent.
echo two > "$REPO/b.txt"
git -C "$REPO" add b.txt
out=$(cd "$REPO" && run); rc=$?
if [ "$rc" -eq 0 ]; then ok; else note "ordinary staging should exit 0, got $rc"; fi
if [ -z "$out" ]; then ok; else note "ordinary staging should stay silent, got: $out"; fi

# Case 3: indexed content diverges from the working copy -> advisory success.
echo working-only > "$REPO/b.txt"
out=$(cd "$REPO" && run); rc=$?
if [ "$rc" -eq 0 ]; then ok; else note "real divergence should exit 0, got $rc"; fi
case "$out" in *b.txt*POST-run*) ok ;; *) note "advisory should name divergence and timing, got: $out" ;; esac
rm -rf "$TMPDIR/commandeck-staged-warn"
native=$(cd "$REPO" && native_out)
if printf '%s' "$native" | jq -e '.systemMessage | contains("b.txt")' >/dev/null 2>&1; then ok
else note "native success output should expose b.txt, got: $native"; fi

# Case 4: the same pair is silent, then new working bytes at the same path
# change the advisory identity and speak again.
out=$(cd "$REPO" && run); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok
else note "repeat with unchanged pair should be silent, got rc=$rc out=$out"; fi
echo another-working-copy > "$REPO/b.txt"
out=$(cd "$REPO" && run); rc=$?
case "$out" in *b.txt*) [ "$rc" -eq 0 ] && ok || note "changed pair should exit 0" ;;
  *) note "same-path content change should advise again, got: $out" ;;
esac

# A missing working copy is also a real index/working divergence.
rm "$REPO/b.txt"
out=$(cd "$REPO" && run); rc=$?
case "$out" in *b.txt*) [ "$rc" -eq 0 ] && ok || note "missing copy should exit 0" ;;
  *) note "missing working copy should be named, got: $out" ;;
esac

# Payload cwd wins over the hook's launch checkout.
OTHER="$TMP/other"
mkdir -p "$OTHER"
git -C "$OTHER" init -q
git -C "$OTHER" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
out=$(cd "$REPO" && run "npm run test:guards" "$OTHER"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok
else note "payload checkout should override dirty launch checkout, got rc=$rc out=$out"; fi

# The existing leading-cd form selects the checkout where the suite ran.
echo indexed > "$OTHER/c.txt"
git -C "$OTHER" add c.txt
echo working > "$OTHER/c.txt"
out=$(cd "$REPO" && run "cd $OTHER && npm run test:guards" "$REPO"); rc=$?
case "$out" in *c.txt*) [ "$rc" -eq 0 ] && ok || note "leading-cd advisory should exit 0" ;;
  *) note "leading cd should select the tested checkout, got: $out" ;;
esac

# Case 4b: the SAME dirty index, but the command is not a test run -> silent.
# This is the narrowing: an ordinary Bash call pays nothing.
for CMD in "git status" "npx tsc --noEmit" "ls -la" "npm run lint" "node scripts/thing.js"; do
  out=$(cd "$REPO" && run "$CMD"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok
  else note "'$CMD' is not a test run and should be silent, got rc=$rc out=$out"; fi
done

# Case 4c: the test runs this repo uses DO reach a genuine divergence.
for CMD in "npm run test:guards" "npm test" "npx vitest run" "node --max-old-space-size=4096 --test x.ts"; do
  rm -rf "$TMPDIR/commandeck-staged-warn"
  out=$(cd "$REPO" && run "$CMD"); rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'b.txt'; then ok
  else note "'$CMD' should advise, got rc=$rc out=$out"; fi
done

# Case 5: outside a git repo -> silent, exit 0 (never wedge a non-repo run).
NONREPO="$TMP/plain"; mkdir -p "$NONREPO"
out=$(cd "$NONREPO" && run); rc=$?
if [ "$rc" -eq 0 ]; then ok; else note "outside a repo should exit 0, got $rc"; fi

# Case 6: a payload with no command at all -> silent.
out=$(cd "$REPO" && bash "$HOOK" 2>&1 <<<'{"tool_name":"Bash","tool_input":{}}'); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok; else note "empty command should be silent, got rc=$rc"; fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
