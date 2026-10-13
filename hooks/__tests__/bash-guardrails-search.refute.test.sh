#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
# Refutation tests for repo-wide search classification: every path a search
# names must be bounded, and a search with no path must read piped input.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh"
REPO_ROOT="$(git rev-parse --show-toplevel)"
PASS=0 FAIL=0
# A log directory with no checkout in it. The real /tmp/demo-logs can hold git
# clones, and a folder holding one is rightly refused as a repo walk.
LOGS=$(mktemp -d); trap 'rm -rf "$LOGS"' EXIT

run_hook() { echo "$1" | "$HOOK" >/dev/null 2>&1; echo $?; }
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
json() { jq -cn --arg cmd "$1" '{tool_input:{command:$cmd}}'; }
# A refused search must hand back a concrete search that passes: replay the
# refusal's `Try:` line through the same hook.
check_try() { # label, command
  local OUT TRY
  OUT=$(json "$2" | "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
  check "$1" 2 "${OUT##*rc=}"
  TRY=$(printf '%s\n' "$OUT" | sed -n 's/^Try: //p' | head -1)
  check "$1: the refusal names a Try: command" 1 "$([ -n "$TRY" ] && echo 1 || echo 0)"
  check "$1: its Try: command passes" 0 "$(run_hook "$(json "$TRY")")"
}

check "a single-quoted scoped path passes" 0 \
  "$(run_hook "$(json "rg -n 'foo' 'src/services'")")"
check "a quoted alternation is not a segment boundary" 0 \
  "$(run_hook "$(json "rg -n 'a|b' src/services")")"
check "rg reading piped input passes" 0 \
  "$(run_hook "$(json "printf 'foo\\n' | rg foo")")"
check "an || alternative is not a stdin feed" 2 \
  "$(run_hook "$(json "printf x || rg pattern")")"
check "a pipe into grep -r searches the cwd and blocks" 2 \
  "$(run_hook "$(json "printf x | grep -r pattern")")"
check "file listing with a scoped path passes" 0 \
  "$(run_hook "$(json 'rg --files src/services')")"
check "an attached long pattern option with a scoped path passes" 0 \
  "$(run_hook "$(json 'rg --regexp=foo src/services')")"
check "an attached short pattern option with a scoped path passes" 0 \
  "$(run_hook "$(json 'rg -efoo src/services')")"
check "an escaped quote keeps the scoped path separate" 0 \
  "$(run_hook "$(json 'rg -F "foo\"bar" src/services')")"
check "a top-level directory name alone passes" 0 \
  "$(run_hook "$(json 'rg foo .claude')")"
check_try "a filename-shaped pattern with no path blocks" \
  'rg package.json'
check_try "a variable-prefixed path blocks" \
  'rg -n foo "$ROOT/src/services"'
check_try "the current checkout root blocks" \
  "rg foo \"$REPO_ROOT\""
check_try "dot-slash alone blocks" \
  'rg foo ./'
check "an escaped quote before an alternation keeps one quoted span; the scoped path passes" 0 \
  "$(run_hook "$(json 'grep -rnoE "test-isolation[^ \"]*|test-concurrency[^ \"]*" package.json scripts/ci')")"
check_try "the same escaped alternation with no path still blocks" \
  'grep -rnoE "test-isolation[^ \"]*|test-concurrency[^ \"]*"'
# An exact-file operand reads one file, so it is bounded however it is spelled.
# A root-level file has no slash and no top-level directory to match, which is
# why the directory rule alone refused `.gitignore`.
check "an exact root-level dotfile operand passes" 0 \
  "$(run_hook "$(json 'rg foo .gitignore')")"
check "an exact root-level file operand passes" 0 \
  "$(run_hook "$(json 'rg -n foo package.json')")"
# A missing file bounds the search to nothing; only a root-like path widens it.
check "an operand naming no existing file passes" 0 \
  "$(run_hook "$(json 'rg foo nosuchfile.txt')")"

# --- bounded absolute paths, and the roots that stay refused -----------------
# An absolute path is bounded unless it is a checkout root, a parent of one, or
# a spelling that normalizes to one. Refusing every absolute path blocked the
# logged searches of /tmp/demo-logs logs (S1-S3) for no benefit.
check "an absolute path into the checkout passes" 0 \
  "$(run_hook "$(json "rg foo $REPO_ROOT/src/services")")"
check_try "the checkout root with a trailing slash blocks" \
  "rg foo $REPO_ROOT/"
check_try "the checkout root spelled with /. blocks" \
  "rg foo $REPO_ROOT/."
check_try "a subdirectory climbing back to the root blocks" \
  "rg foo $REPO_ROOT/src/.."
check_try "a relative path normalizing to the root blocks" \
  'rg foo src/..'
check_try "the filesystem root blocks" \
  'rg foo /'
check_try "a parent of the checkout blocks" \
  "rg foo $(dirname "$REPO_ROOT")"
# Two levels up holds no checkout directly, so only the ancestor test sees it.
check_try "a grandparent of the checkout blocks" \
  "rg foo $(dirname "$(dirname "$REPO_ROOT")")"
# The homes directory: /home on Linux, /Users on macOS.
check_try "a bare wildcard directory blocks" \
  "rg foo '$(dirname "$HOME")/*'"
check_try "a slash in the pattern is not a path" \
  "rg 'src/services'"
check_try "a scoped path does not excuse a root operand beside it" \
  'rg foo . src'
check_try "a glob option value is not a path" \
  "rg foo -g '*.ts'"
check_try "a piped rg that names the root still searches the root" \
  'cat x.log | rg foo .'
check "a quoted pattern with a space is one pattern" 0 \
  "$(run_hook "$(json "rg -n 'foo bar' src/services")")"
check "a glob option beside a scoped path passes" 0 \
  "$(run_hook "$(json "rg foo -g '*.ts' src")")"
check "a literal alias to a log directory passes" 0 \
  "$(run_hook "$(json "L=$LOGS; rg foo \"\$L\"")")"
check_try "a literal alias to dot blocks" \
  'L=.; rg foo "$L"'
check_try "a for-list over the root blocks" \
  'for f in .; do rg foo "$f"; done'
check_try "a multi-word for-list is not resolved and blocks" \
  'for f in /tmp/a .; do rg foo "$f"; done'

# The logged calls. S3 names a log its own first line creates, so the file is
# not on disk when the hook runs.
S1=$(cat <<'EOF'
for f in /tmp/demo-logs/u1201-chain-scope-fix-r1-{focused,shell,changed,typecheck,guards,static}.log; do printf '%s\n' "$f"; rg -n "^(ℹ (tests|pass|fail)|pass [0-9]+, fail|test-changed:|> demo-project|Error:|FAIL|PASS|[[:space:]]*[0-9]+ passing|[[:space:]]*[0-9]+ failing)" "$f" | tail -n 12; done
rg -n '"typecheck-root"|"\.claude/"|"keep"' scripts/ci/lane-inputs.json
sed -n '1,70p' scripts/ci/lane-inputs.json
EOF
)
S2=$(cat <<'EOF'
rg -n "EROFS: read-only file system|Test Files[[:space:]]+[0-9]+ passed|Tests[[:space:]]+[0-9]+ passed|ℹ tests [0-9]+|ℹ pass [0-9]+|ℹ fail [0-9]+|ℹ skipped [0-9]+|error TS[0-9]+|STEP |FINAL_STATUSES" /tmp/demo-logs -g 'u1206-*.log'; printf 'web-changed-tail: '; tail -n 8 /tmp/demo-logs/u1206-web-changed-runner.log | tr '\n' ';'; printf '\ndiff-check-bytes: '; wc -c < /tmp/demo-logs/u1206-diff-check.log
EOF
)
S3=$(cat <<'EOF'
npm --prefix infra test -- --runInBand --runTestsByPath test/verification-idle-sweep.test.ts > /tmp/demo-logs/u1210-mutation-count.log 2>&1
status=$?
rg -n 'Expected|Received|functions|permissions|Test Suites:|Tests:|Snapshots:|Time:' /tmp/demo-logs/u1210-mutation-count.log | tail -n 20
printf 'status=%s\n' "$status"
exit 0
EOF
)
check "S1: a for-list log binding passes" 0 "$(run_hook "$(json "$S1")")"
check "S2: an absolute log directory with a filename glob passes" 0 "$(run_hook "$(json "${S2//\/tmp\/demo-logs/$LOGS}")")"
check "S3: a log this call creates passes" 0 "$(run_hook "$(json "$S3")")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
