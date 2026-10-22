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
# The decisions, alerts and limit watchers are required too: the decisions
# watcher was never started in a real session and an open owner decision sat
# unseen. Each one records its pid per project (cos-lib.sh cos_wait), so another
# project's watcher of the same name does not count, nor a dead pid reused.
# Every block names its watchers by the stable link setup and update keep
# current, the path the session instructions name: two paths can drift apart.
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
# ps -p <pid> answers from pids.out ("<pid> <command>"); any other ps prints ps.out.
cat >"$BOX/bin/ps" <<EOF
#!/usr/bin/env bash
case " \$* " in *" -p "*) p=\${@: -1}; sed -n "s/^\$p //p" "$BOX/pids.out" ;; *) cat "$BOX/ps.out" 2>/dev/null ;; esac
EOF
chmod +x "$BOX/bin/ps"
key() { HOME=$BOX/home bash -c '. "$1/hooks/lib/project.sh"; pp_cos_key "$2"; printf %s "$COS_KEY"' _ "$SOURCE" "$1"; }
mkdir -p "$BOX/home/.commandeck/chief-of-staff"
# 0.8 kept the relay's state under the directory name alone; the first look carries it over.
echo "saved" > "$BOX/home/.commandeck/chief-of-staff/main.md"; echo "d1" > "$BOX/home/.commandeck/chief-of-staff/main.decisions-seen"
KEY=$(key "$MAIN")
check "the relay's saved state and seen marks carry over to the project's own key" "saved d1 gone" \
  "$(cat "$KEY.md" "$KEY.decisions-seen" | paste -sd' ' -) $(ls "${KEY%/*}"/main.md "${KEY%/*}"/main.decisions-seen >/dev/null 2>&1 && echo kept || echo gone)"
# up <watcher>... -- those watchers run for this project; the others are down.
up() {
  : >"$BOX/pids.out"; rm -f "$KEY".*.pid; local w n=100
  for w in "$@"; do n=$((n + 1)); echo "$n" >"$KEY.$(job "$w").pid"; echo "$n bash /x/plugin/scripts/$(job "$w").sh" >>"$BOX/pids.out"; done
}
# Issue 290: the relay's 50-minute timer check (cos-check.sh) is the fifth job, recorded the same way.
job() { [ "$1" = check ] && echo cos-check || echo "cos-watch-$1"; }
up decisions alerts limit check

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

procs "bash $P $H"
for w in decisions alerts limit check; do
  up $(printf '%s\n' decisions alerts limit check | grep -vx "$w")
  check "the $w watcher down alone blocks" "0 block" "$(run "$COS" false)"
  OUT=$(jq -cn '{stop_hook_active:false}' | HOME=$BOX/home PATH=$BOX/bin:$PATH CLAUDE_PROJECT_DIR=$COS ORCA_TERMINAL_HANDLE=$H bash "$HOOK" 2>/dev/null | jq -r .reason)
  check "and the block names its start command" 1 "$(case $OUT in *"/scripts/$(job "$w").sh"*) echo 1;; *) echo 0;; esac)"
done
up decisions alerts limit check; sed -i.bak 's/^101 .*/101 vim \/x\/plugin\/scripts\/other.sh/' "$BOX/pids.out"
check "a recorded pid now running something else blocks" "0 block" "$(run "$COS" false)"
up decisions alerts limit check; sed -i.bak 's/^101 .*/101 tail -f \/x\/plugin\/scripts\/cos-watch-decisions.sh/' "$BOX/pids.out"
check "a recorded pid only reading the watcher's file blocks" "0 block" "$(run "$COS" false)"
up decisions alerts limit check; mv "$KEY.cos-watch-alerts.pid" "${KEY%/*}/other.cos-watch-alerts.pid"
check "another project's alerts watcher does not count" "0 block" "$(run "$COS" false)"
# A project in another folder with the same directory name keeps its own records.
OTHER=$BOX/b/main; git init -q "$OTHER"; up decisions alerts limit check
for f in "$KEY".*.pid; do mv "$f" "$(key "$OTHER").${f#"$KEY".}"; done
check "the same-named project's watchers do not count for this one" "0 block" "$(run "$COS" false)"
up decisions alerts limit check
ln -s "$SOURCE" "$BOX/home/.commandeck/plugin"; procs ""
OUT=$(jq -cn '{stop_hook_active:false}' | HOME=$BOX/home PATH=$BOX/bin:$PATH CLAUDE_PROJECT_DIR=$COS ORCA_TERMINAL_HANDLE=$H bash "$HOOK" 2>/dev/null | jq -r .reason)
check "with setup's stable link in place the block names the poller through it" 1 "$(case $OUT in *"bash $BOX/home/.commandeck/plugin/scripts/cos-watch-inbox.sh $H"*) echo 1;; *) echo 0;; esac)"
rm "$BOX/home/.commandeck/plugin"

procs ""
check "stop_hook_active passes" "0 none" "$(run "$COS" true)"
check "a non-Chief-of-Staff pane passes" "0 none" "$(run "$WT" false)"
check "the main checkout passes" "0 none" "$(run "$MAIN" false)"
check "no pane handle passes (nothing to arm)" "0 none" "$(run "$COS" false "")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
