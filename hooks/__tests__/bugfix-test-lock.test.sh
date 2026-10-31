#!/usr/bin/env bash
# bugfix-test-lock.test.sh -- while a failing test is listed in .claude/bugfix-lock, the file tools may not touch
# it: the failing test is the spec for the fix, so the code changes and the test stays as written.
# The hook needs GNU realpath, so each run goes through hooks/lib/run-hook.sh, as Claude Code starts it.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOOK=$ROOT/hooks/bugfix-test-lock.sh LAUNCH=$ROOT/hooks/lib/run-hook.sh
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
P=$T/p
mkdir -p "$P/.claude" "$P/src"
git -C "$P" init -q -b main
: > "$P/src/a.test.ts"; : > "$P/src/a.ts"
lock() { printf '%s\n' "$@" > "$P/.claude/bugfix-lock"; }
edit() { jq -cn --arg f "$1" '{hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: {file_path: $f, old_string: "a", new_string: "b"}}'; }
multi() { jq -cn --arg f "$1" '{hook_event_name: "PreToolUse", tool_name: "MultiEdit", tool_input: {edits: [{file_path: $f, old_string: "a", new_string: "b"}]}}'; }
# run <payload> -- the hook's status; its stderr is left in $T/err
run() { CLAUDE_PROJECT_DIR=$P sh "$LAUNCH" "$HOOK" <<<"$1" 2>"$T/err" >/dev/null; echo $?; }

# Catches: a failing test reshaped to agree with its bug, so the fix is never proved against the test as written.
lock "# the coupon bug" src/a.test.ts
rc=$(run "$(edit src/a.test.ts)")
msg="$(grep -o 'BLOCKED:' "$T/err" | head -1)$(grep -qi 'fix the code' "$T/err" && grep -q '`git diff' "$T/err"; echo $?)"
# the refusal says to fix the code, with a command to run; the same test by its absolute path is refused too
check "a listed test is refused" "2|BLOCKED:0|2" "$rc|$msg|$(run "$(edit "$P/src/a.test.ts")")"

# Catches: a MultiEdit, whose path may sit on each edit, walking past a hook that reads only the top-level path.
check "a MultiEdit is refused" 2 "$(run "$(multi "$P/src/a.test.ts")")"

# Catches: the lock refusing an edit to the code, which is the work it asks for.
rc=$(run "$(edit src/a.ts)")
check "an unlisted file passes" "0|" "$rc|$(cat "$T/err")"

# Catches: a glob line honoured as a match, so one line locks files nobody named.
lock "src/*.test.ts"
rc=$(run "$(edit src/a.test.ts)")
check "a glob line matches nothing" "0|1" "$rc|$(grep -c 'ignoring' "$T/err")"

# Catches: the lock committed by the pass's `git add -A`, which would lock the file in every later checkout.
cp "$ROOT/.gitignore" "$P/.gitignore"
lock src/a.test.ts
git -C "$P" add -A
check "the lock stays out of a commit" "|1" \
  "$(git -C "$P" diff --cached --name-only | grep -x '.claude/bugfix-lock')|$(bash -c '. "$1/scripts/install-lib.sh" >/dev/null 2>&1; printf "%s\n" "${IL_STATE[@]}"' _ "$ROOT" | grep -cx '.claude/bugfix-lock')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
