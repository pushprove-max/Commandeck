#!/usr/bin/env bash
# Self-test for cos-inbox-waiter-stop.sh.
# Run directly: bash hooks/__tests__/cos-inbox-waiter-stop.test.sh
#
# Why each case matters: the Chief-of-Staff pane wakes only while its inbox
# poller (`scripts/cos-watch-inbox.sh`) runs, so a live poller for this
# pane must pass or the pane can never end a turn. Another pane's poller does
# not wake this one, and a poller started with no handle may be another
# project's (the process list is the whole machine's). A live `orchestration
# check --wait` alone must block: main's sends go to the run, that waiter never
# sees them, and it hid main's messages for hours on 2026-10-11. A command that
# only mentions the script (an editor, a `cat`) is not a poller and would leave
# the pane deaf. Every other pane runs this hook on every turn and must never
# be held, and `stop_hook_active` must pass or the block would loop forever.
# `ps` is a stub first on PATH, so the process table is the fixture.
set -u
SOURCE=$(git rev-parse --show-toplevel)
HOOK=$SOURCE/hooks/cos-inbox-waiter-stop.sh
BOX=$(mktemp -d "${TMPDIR:-/tmp}/cos-inbox-waiter-test.XXXXXX")
trap 'rm -rf "$BOX"' EXIT
PASS=0 FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi
}

MAIN=$BOX/main COS=$BOX/wt/Chief-of-Staff WT=$BOX/wt/u1
git init -q "$MAIN" && git -C "$MAIN" commit -q --allow-empty -m init
git -C "$MAIN" worktree add -q "$COS" -b cos
git -C "$MAIN" worktree add -q "$WT" -b u1
mkdir -p "$BOX/bin" "$BOX/home"
printf '#!/usr/bin/env bash\ncat "%s/ps.out" 2>/dev/null\n' "$BOX" >"$BOX/bin/ps"
chmod +x "$BOX/bin/ps"

H=term_cos-1111
procs() { printf '%s\n' "$@" >"$BOX/ps.out"; }
# run <worktree> <stop_hook_active> [handle] -> prints "<exit status> <decision>"
run() {
  local out rc
  out=$(jq -cn --argjson a "$2" '{stop_hook_active:$a}' \
    | HOME=$BOX/home PATH=$BOX/bin:$PATH CLAUDE_PROJECT_DIR=$1 ORCA_TERMINAL_HANDLE=${3-$H} \
      COMMANDECK_REVIEWER= bash "$HOOK" 2>/dev/null)
  rc=$?
  echo "$rc $(jq -r '.decision // "none"' <<<"${out:-{\}}" 2>/dev/null)"
}

P=/x/plugin/scripts/cos-watch-inbox.sh
procs ""
check "Chief-of-Staff with no poller blocks" "0 block" "$(run "$COS" false)"
OUT=$(jq -cn '{stop_hook_active:false}' | HOME=$BOX/home PATH=$BOX/bin:$PATH \
  CLAUDE_PROJECT_DIR=$COS ORCA_TERMINAL_HANDLE=$H bash "$HOOK" 2>/dev/null | jq -r .reason)
check "the block names the poller and this pane's handle" 1 "$(case $OUT in *"/cos-watch-inbox.sh $H"*) echo 1;; *) echo 0;; esac)"
check "the block says to run it in the background" 1 "$(case $OUT in *background*) echo 1;; *) echo 0;; esac)"
check "the block says why check --wait is not enough" 1 "$(case $OUT in *"check --wait"*) echo 1;; *) echo 0;; esac)"

procs "bash $P term_other-2222" "bash $P ${H}2"
check "a poller for another pane does not count" "0 block" "$(run "$COS" false)"

procs "/bin/zsh -c orca-ide orchestration check --terminal $H --json" \
  "orca-ide orchestration check --terminal $H --wait --types worker_done,question --json" \
  "node /x/orca-ide orchestration check --terminal $H --wait --timeout-ms 600000 --json"
check "a live check --wait for this pane alone blocks" "0 block" "$(run "$COS" false)"

procs "cat $P" "vim $P $H" "/bin/zsh -c tail -f /tmp/log # $P"
check "a command that only mentions the poller script blocks" "0 block" "$(run "$COS" false)"

procs "bash $P $H"
check "a live poller with this pane's handle passes" "0 none" "$(run "$COS" false)"
procs "/bin/bash $P"
check "a live poller with no handle argument, whose pane is unknown, blocks" "0 block" "$(run "$COS" false)"
procs "$P $H"
check "a poller run directly passes" "0 none" "$(run "$COS" false)"

procs ""
check "stop_hook_active passes" "0 none" "$(run "$COS" true)"
check "a non-Chief-of-Staff pane passes" "0 none" "$(run "$WT" false)"
check "the main checkout passes" "0 none" "$(run "$MAIN" false)"
check "no pane handle passes (nothing to arm)" "0 none" "$(run "$COS" false "")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
