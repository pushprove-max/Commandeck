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

# --- a longer command is not a repeat of its first words ----------------------
# A full verification refused as "already ran" would be reported as passed
# without ever running.
SMALL=$(json 'LOG=/tmp/v.log; npm run test:unit 2>&1 | tee $LOG')
ran "$SMALL"
check "a later suite after the same first words is a new run" 0 \
  "$(run_hook "$(json 'LOG=/tmp/v.log; npm run test:unit 2>&1 | tee $LOG; npm run typecheck:backend')")"
check "and the smaller run itself still blocks" 2 "$(run_hook "$SMALL")"

# --- the key keeps every argument and drops only redirections -----------------
# A quoted test-name filter picks which tests run, so it is part of the run; a
# value refused as "already ran" is a test never run, and a redirection kept in
# the key lets the same run through again.
ran "$(json 'npx vitest run src/x.test.tsx -t "a|b"')"
check "a quoted filter holding a pipe is kept whole" 0 \
  "$(run_hook "$(json 'npx vitest run src/x.test.tsx -t "a|c"')")"
ran "$(json 'npx vitest run src/x.test.tsx -t 1 2>/dev/null')"
check "a digit filter before an fd redirection is kept" 0 \
  "$(run_hook "$(json 'npx vitest run src/x.test.tsx -t 2 2>/dev/null')")"
ran "$(json 'npx vitest run src/x.test.tsx -t "a b"')"
check "one quoted filter is not two bare words" 0 \
  "$(run_hook "$(json 'npx vitest run src/x.test.tsx -t a b')")"
check "single and double quotes are the same filter" 2 \
  "$(run_hook "$(json "npx vitest run src/x.test.tsx -t 'a b'")")"
# A filter is a regex: its spacing is part of what it selects.
ran "$(json 'npx vitest run src/s.test.tsx -t "a  b"')"
check "a quoted filter that differs only in spacing is a new run" 0 \
  "$(run_hook "$(json 'npx vitest run src/s.test.tsx -t "a b"')")"
check "the same spaced filter again is the same run" 2 \
  "$(run_hook "$(json 'npx vitest run src/s.test.tsx -t "a  b"')")"
ran "$(json 'npx vitest run src/r.test.tsx -t 1')"
for redir in '2>&1 | tail -5' '>/tmp/o.log' '> /tmp/o.log' '2>/dev/null' \
  '2>> /tmp/o.log' '&>/tmp/o.log' '|& tail -5' '>| /tmp/o.log' '>&2'; do
  check "the same run with $redir blocks" 2 \
    "$(run_hook "$(json "npx vitest run src/r.test.tsx -t 1 $redir")")"
done

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

# --- the build's own papers are not the tree; a chained run counts -------
# One build ran the same suite 8 times: each evidence line it wrote made a new
# tree, and a run with commands chained on was keyed apart from the bare one.
mkdir -p "$REPO/.claude/briefs"; echo 'built' > "$REPO/.claude/briefs/u-evidence.md"
ran "$(json 'npm run test:e2e && echo suite-done')"
check "a chained run is recorded: the bare run after it blocks" 2 "$(run_hook "$(json 'npm run test:e2e 2>&1 | tail -5')")"
echo 'built, and the next item' >> "$REPO/.claude/briefs/u-evidence.md"
check "an edit to the evidence file keeps the record" 2 "$(run_hook "$(json 'npm run test:e2e')")"
echo 'export const a = 2;' > "$REPO/a.ts"
check "a code edit still lets the run through" 0 "$(run_hook "$(json 'npm run test:e2e')")"

# --- the key says what ran: each suite's own directory, what it waited on, every quoted word -----
# A key that loses one of them refuses a run that never happened as "already ran".
mkdir -p "$REPO/api" "$REPO/web"
ran "$(json 'npm run test:types && cd api && npm run test:types')"
check "a second suite in another directory is a new run" 0 "$(run_hook "$(json 'npm run test:types && cd web && npm run test:types')")"
ran "$(json 'false && npm run test:lint; true')"
check "a suite that waited on another command is not the bare run" 0 "$(run_hook "$(json 'npm run test:lint')")"
ran "$(json 'npm run test:alpha || npm run test:beta')"
check "a suite after || is not the one after &&" 0 "$(run_hook "$(json 'npm run test:alpha && npm run test:beta')")"
ran "$(json 'cd . || npm run test:gamma')"
check "a suite that runs only when a cd fails is not the bare run" 0 "$(run_hook "$(json 'npm run test:gamma')")"
ran "$(json 'false && npm run test:eta; true')"
check "a cd that ends a skipped branch keeps it apart from the suite after it" 0 "$(run_hook "$(json 'false && cd .; npm run test:eta')")"
ran "$(json 'true || npm run test:theta')"
check "a cd after || that lets the suite run is not the skipped run" 0 "$(run_hook "$(json 'true || cd . && npm run test:theta')")"
ran "$(json 'cd /nonexistent-dir && npm run test:iota')"
check "a leading cd into a folder that is not there ran nothing" 0 "$(run_hook "$(json 'npm run test:iota')")"
ran "$(json 'cd . extra && npm run test:kappa')"
check "a leading cd with two arguments fails in bash and ran nothing" 0 "$(run_hook "$(json 'npm run test:kappa')")"
ran "$(json 'cd "a b" . && npm run test:mu')"
check "a leading cd with a quoted second word fails in bash and ran nothing" 0 "$(run_hook "$(json 'npm run test:mu')")"
ran "$(json 'cd . < /nonexistent-input && npm run test:nu')"
check "a leading cd with a redirection that fails ran nothing" 0 "$(run_hook "$(json 'npm run test:nu')")"
ran "$(json 'npm run test:xi')"
check "a second suite inside a quoted shell body is a new run" 0 "$(run_hook "$(json 'npm run test:xi && bash -c "npm run typecheck"')")"
ran "$(json 'cd - && npm run test:lambda')"
check "a leading cd to an option, not a folder, keeps its place in the key" 0 "$(run_hook "$(json 'npm run test:lambda')")"
ran "$(json 'npm run test:delta | tail -3 || echo failed')"
check "what follows the last suite still makes no new run" 2 "$(run_hook "$(json 'npm run test:delta')")"
ran "$(json 'npx vitest run -t ">"')"
check "a quoted > filter is a filter, not a redirection" 0 "$(run_hook "$(json 'npx vitest run -t "<"')")"
ran "$(json 'npx vitest run -t ";"')"
check "a quoted ; filter is a filter, not a separator" 0 "$(run_hook "$(json 'npx vitest run -t "|"')")"
check "and the same quoted filter again blocks" 2 "$(run_hook "$(json 'npx vitest run -t ";" 2>&1 | tail -3')")"
check "an escaped > is the quoted > filter, which ran" 2 "$(run_hook "$(json 'npx vitest run -t \>')")"
ran "$(json 'npx vitest run -t \&')"
check "an escaped & is a filter, not a separator" 0 "$(run_hook "$(json 'npx vitest run -t \|')")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
