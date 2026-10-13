#!/usr/bin/env bash
# Self-test for suite-rerun-guard.sh. Run directly.
#
# The narrowing it pins, three parts:
#   - only a run that FINISHED blocks the next one. The record used to be
#     written before the command ran, so a call another hook refused, or one the
#     operator interrupted, left "you already ran this" behind for a run that
#     never started -- and the tree stayed stranded for 30 minutes.
#   - the key is the EFFECTIVE directory. `cd infra && npm run test:unit` runs a
#     different suite over a different tree than the same words at the root, and
#     both were keyed to the root.
#   - the `cd` prefix is still stripped from the command TEXT, so the same run
#     spelled with and without it is one key when the directory is the same.
set -u
export COMMANDECK_HOOK_TIER=strict

HOOK="$(cd "$(dirname "$0")/.." && pwd)/suite-rerun-guard.sh"
PASS=0 FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export COMMANDECK_SUITE_RUNS_DIR="$TMP/state"

REPO="$TMP/repo"
mkdir -p "$REPO/infra"
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
echo 'export const a = 1;' > "$REPO/a.ts"
git -C "$REPO" add a.ts
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m a

run_hook() { echo "$1" | "$HOOK" >/dev/null 2>&1; echo $?; }
# The PostToolUse half: what marks the attempt as a run that actually happened.
complete() { echo "$1" | "$HOOK" --record-complete >/dev/null 2>&1; }
# One finished run: the PreToolUse pass, then the completion record.
ran() { run_hook "$1" >/dev/null; complete "$1"; }
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
json() { jq -cn --arg cmd "$1" --arg cwd "${2:-$REPO}" '{tool_input:{command:$cmd},cwd:$cwd}'; }

# --- same run, same tree ----------------------------------------------------
FIRST=$(json 'npm run test:unit 2>&1 | tail -40')
check "first run passes" 0 "$(run_hook "$FIRST")"
complete "$FIRST"
check "same run, same tree, different pipe blocks" 2 \
  "$(run_hook "$(json 'npm run test:unit 2>&1 | grep -E "fail" | head -20')")"
check "same run behind a cd prefix is the same key" 2 \
  "$(run_hook "$(json "cd $REPO && npm run test:unit > /tmp/x.log")")"
check "RERUN=1 lets a flake check through" 0 \
  "$(run_hook "$(json 'RERUN=1 npm run test:unit 2>&1 | tail -5')")"
check "a different suite is a different run" 0 \
  "$(run_hook "$(json 'npm run test:guards 2>&1 | tail -40')")"
TSC=$(json 'npx tsc --noEmit -p tsconfig.json 2>&1 | head -20')
check "tsc is guarded too: first passes" 0 "$(run_hook "$TSC")"
complete "$TSC"
check "tsc rerun on the same tree blocks" 2 \
  "$(run_hook "$(json 'npx tsc --noEmit -p tsconfig.json 2>&1 | tail -3; echo done')")"
# the configured typecheck scripts are tsc runs by another name.
TYPECHECK=$(json 'npm run typecheck:backend 2>&1 | tail -20')
check "npm run typecheck is guarded too: first passes" 0 "$(run_hook "$TYPECHECK")"
complete "$TYPECHECK"
check "npm run typecheck rerun on the same tree blocks" 2 \
  "$(run_hook "$(json 'npm run typecheck:backend 2>&1 | head -5')")"

echo 'export const a = 2;' > "$REPO/a.ts"
check "an edit to a tracked file unlocks the rerun" 0 \
  "$(run_hook "$(json 'npm run test:unit 2>&1 | tail -40')")"
echo 'x' > "$REPO/new-untracked.ts"
UNTRACKED=$(json 'npm run test:unit 2>&1 | tail -40')
check "a new untracked file unlocks it too" 0 "$(run_hook "$UNTRACKED")"
complete "$UNTRACKED"
check "and the tree is fixed again after that" 2 \
  "$(run_hook "$(json 'npm run test:unit')")"

# Untracked input identity includes the path, not just concatenated bytes.
mv "$REPO/new-untracked.ts" "$REPO/renamed-untracked.ts"
check "renaming identical untracked bytes changes tested inputs" 0 "$(run_hook "$UNTRACKED")"
complete "$UNTRACKED"
check "the unchanged renamed input is blocked again"      2 "$(run_hook "$UNTRACKED")"

# Index state is independently meaningful even when the working bytes and
# HEAD diff stay unchanged.
INDEXED=$(json 'npm run test:guards')
check "a changed tracked input starts a guards run"        0 "$(run_hook "$INDEXED")"
complete "$INDEXED"
check "the unchanged tracked input is blocked again"      2 "$(run_hook "$INDEXED")"
git -C "$REPO" add a.ts
check "staging the same working bytes changes tested inputs" 0 "$(run_hook "$INDEXED")"
complete "$INDEXED"
check "the unchanged staged index is blocked again"       2 "$(run_hook "$INDEXED")"

# Completion retains the PRE-run fingerprint. A fixture changed while the
# command is in flight must unlock the next run rather than certify new bytes.
echo 'before-run' > "$REPO/pre-run.ts"
SNAPSHOT=$(json 'npm run test:unit')
check "a run starts against its pre-run snapshot"          0 "$(run_hook "$SNAPSHOT")"
echo 'during-run' > "$REPO/during-run.ts"
complete "$SNAPSHOT"
check "a change made during the run unlocks the next run"  0 "$(run_hook "$SNAPSHOT")"

# --- a run that never finished is not a run -----------------------------------
echo 'export const a = 3;' > "$REPO/a.ts"
ATTEMPT=$(json 'npm run test:unit')
check "an attempt on a fresh tree passes"                0 "$(run_hook "$ATTEMPT")"
check "the SAME attempt, never completed, passes again"  0 "$(run_hook "$ATTEMPT")"
complete "$ATTEMPT"
check "once it completes, the rerun blocks"              2 "$(run_hook "$ATTEMPT")"

echo 'export const a = 4;' > "$REPO/a.ts"
INTERRUPTED=$(jq -cn --arg cmd 'npm run test:unit' --arg cwd "$REPO" \
  '{tool_input:{command:$cmd},cwd:$cwd,tool_response:{interrupted:true}}')
check "an interrupted run passes on the way in"          0 "$(run_hook "$ATTEMPT")"
echo "$INTERRUPTED" | "$HOOK" --record-complete >/dev/null 2>&1
check "an interrupted run does not block the retry"      0 "$(run_hook "$ATTEMPT")"

# --- the key is the effective directory ---------------------------------------
# Same words, different place: the infra suite is not the root suite.
echo 'export const a = 5;' > "$REPO/a.ts"
git -C "$REPO/infra" init -q
git -C "$REPO/infra" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
ROOT_RUN=$(json 'npm run test:guards')
ran "$ROOT_RUN"
check "the same words in infra/ are a different run"     0 \
  "$(run_hook "$(json "cd infra && npm run test:guards")")"
check "and the root run is still blocked"                2 "$(run_hook "$ROOT_RUN")"

# --- a stale record (over 30 minutes) does not block --------------------------
for f in "$COMMANDECK_SUITE_RUNS_DIR"/*; do
  read -r _ tree < "$f"; printf '%s %s\n' "$(( $(date +%s) - 2000 ))" "$tree" > "$f"
done
check "a record older than 30 min passes" 0 \
  "$(run_hook "$(json 'npm run test:unit')")"

# --- prose is not a run -------------------------------------------------------
# A quoted message body that names a suite is prose, not a run.
PROSE=$(json 'orca-ide orchestration send --body "ran npm test then npm run test:unit"')
check "a quoted body naming npm test passes" 0 "$(run_hook "$PROSE")"
complete "$PROSE"
check "and is not keyed as a rerun once complete" 0 "$(run_hook "$PROSE")"
# --- not a suite -------------------------------------------------------------
check "an ordinary command passes" 0 \
  "$(run_hook "$(json 'git status --short')")"
check "a grep that mentions a suite name passes" 0 \
  "$(run_hook "$(json 'grep -n "test:unit" package.json')")"
check "test:changed is its own key, first run passes" 0 \
  "$(run_hook "$(json 'timeout 900 npm run test:changed 2>&1 | tail -10')")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
