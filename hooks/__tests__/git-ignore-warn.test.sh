#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
# Self-test git-ignore-warn.sh against the repository's actual ignore policy.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/git-ignore-warn.sh"
ROOT=$(git rev-parse --show-toplevel)
REPO=$(mktemp -d)
OUTSIDE=$(mktemp /tmp/commandeck-git-ignore-warn-outside.XXXXXX)
trap 'rm -rf -- "$REPO"; rm -f -- "$OUTSIDE"' EXIT
PASS=0 FAIL=0

json() {
  jq -cn --arg tool "$1" --arg fp "$2" '{tool_name:$tool, tool_input:{file_path:$fp}}'
}

# ADVISORY MEANS EXIT 0. A non-zero advisory shows a Codex seat
# `Script failed` with no text, so the seat never hears the advice. Any non-zero
# rc is printed as itself and fails whichever case expects `warn` or `quiet`.
run_hook() {
  local cwd=${3:-$REPO} out rc
  out=$( (cd "$cwd" && json "$1" "$2" | "$HOOK" 2>&1 >/dev/null) ); rc=$?
  [ "$rc" -eq 0 ] || { echo "rc=$rc"; return; }
  case "$out" in *"GITIGNORED:"*) echo warn ;; *) echo quiet ;; esac
}

check() {
  if [ "$2" = "$3" ]; then
    PASS=$((PASS+1)); echo "ok   $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"
  fi
}

check_ignore() {
  git -C "$REPO" check-ignore -q -- "$2"
  check "$1" "$3" "$?"
}

# Its own ignore policy in an isolated Git repository.
git init -q "$REPO"
printf '%s\n' scripts/.taxonomy-census.json scripts/attack-corpus-fixtures/ '.env*' > "$REPO/.gitignore"
mkdir -p "$REPO/scripts/lib" "$REPO/scripts/__tests__" \
  "$REPO/scripts/attack-corpus-fixtures"
for path in scripts/new.ts scripts/new.sh scripts/new.py scripts/new.mjs \
  scripts/lib/new.ts scripts/__tests__/new.test.ts \
  scripts/.taxonomy-census.json scripts/attack-corpus-fixtures/id.bin .env.local; do
  : > "$REPO/$path"
done

for path in scripts/new.ts scripts/new.sh scripts/new.py scripts/new.mjs \
  scripts/lib/new.ts scripts/__tests__/new.test.ts; do
  check_ignore "$path is discoverable" "$path" 1
done
check_ignore "census output stays ignored" scripts/.taxonomy-census.json 0
check_ignore "sensitive fixtures stay ignored" scripts/attack-corpus-fixtures/id.bin 0
check_ignore "environment files stay ignored" .env.local 0

CENSUS="$REPO/scripts/.taxonomy-census.json"
check "Write ignored output fires" warn "$(run_hook Write "$CENSUS")"
check "Edit ignored output passes" quiet "$(run_hook Edit "$CENSUS")"
check "Write tracked file passes" quiet \
  "$(run_hook Write "$ROOT/scripts/board.sh" "$ROOT")"
check "Write outside repo passes" quiet "$(run_hook Write "$OUTSIDE")"
check "Write nonexistent path passes" quiet \
  "$(run_hook Write "$REPO/scripts/never-written.ts")"
check "Write discoverable source passes" quiet \
  "$(run_hook Write "$REPO/scripts/new.ts")"

# A `!` rule un-ignores a path, and `check-ignore -v` prints that rule too: the
# file ships, so there is nothing to warn about.
printf '%s\n' 'build/*' '!build/keep.ts' >> "$REPO/.gitignore"; mkdir -p "$REPO/build"; : > "$REPO/build/keep.ts"; : > "$REPO/build/out.js"
check "a file a negated rule brings back is quiet" quiet "$(run_hook Write "$REPO/build/keep.ts")"
check "its ignored neighbour still warns" warn "$(run_hook Write "$REPO/build/out.js")"

# The advice must reach the model, not just the terminal: on exit 0 the stdout
# JSON is the only channel a session actually reads.
JSON=$( (cd "$REPO" && json Write "$CENSUS" | "$HOOK" 2>/dev/null) )
check "the warning is native additionalContext" 0 \
  "$(jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"
            and (.hookSpecificOutput.additionalContext | contains("GITIGNORED:"))' \
     <<<"$JSON" >/dev/null 2>&1 && echo 0 || echo 1)"

# A rule that UN-ignores a file (`!name`) is the last match for it, and
# `check-ignore -v` prints that rule too. Read as "ignored", a file that will
# ship was called lost.
printf 'keepme/*\n!keepme/kept.md\n' >> "$REPO/.gitignore"
mkdir -p "$REPO/keepme"; : > "$REPO/keepme/kept.md"; : > "$REPO/keepme/lost.md"
check "a file an un-ignore rule brings back gets no warning" quiet "$(run_hook Write "$REPO/keepme/kept.md")"
check "its ignored neighbour still warns" warn "$(run_hook Write "$REPO/keepme/lost.md")"

# Setup hides a build's papers and main's to-do from git on purpose (the
# running state, scripts/install-lib.sh IL_STATE): a brief or an evidence file
# is written with Write many times a build, and none was ever meant to ship.
printf '%s\n' .claude/briefs/ todo/main-todo.md >> "$REPO/.git/info/exclude"
mkdir -p "$REPO/.claude/briefs" "$REPO/todo"; : > "$REPO/.claude/briefs/u-evidence.md"; : > "$REPO/todo/main-todo.md"; : > "$REPO/todo/other.md"
check "a build's paper setup hid from git gets no warning" quiet "$(run_hook Write "$REPO/.claude/briefs/u-evidence.md")"
check "nor does main's to-do" quiet "$(run_hook Write "$REPO/todo/main-todo.md")"
echo todo/other.md >> "$REPO/.git/info/exclude"
check "another ignored file beside it still warns" warn "$(run_hook Write "$REPO/todo/other.md")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
