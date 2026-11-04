#!/usr/bin/env bash
# Self-test for cos-inbox-waiter-stop.sh and cos-inbox-arm-stop.sh.
# Run directly: bash hooks/__tests__/cos-inbox-waiter-stop.test.sh
#
# Why each case matters: the Chief-of-Staff pane wakes only while its inbox
# poller (`scripts/cos-watch-inbox.sh`) runs. The arm hook (asyncRewake, never
# blocks) starts one for this pane when none runs, and its exit 2 with the
# poller's text wakes the pane, so no turn is spent re-arming it (issue 575).
# A live poller for this pane means no second one. Another pane's poller does
# not wake this one, and a poller started with no handle may be another
# project's (the process list is the whole machine's). A live `orchestration
# check --wait` alone is no poller: main's sends go to the run, that waiter never
# sees them, and it hid main's messages for hours on 2026-10-11. A command that
# only mentions the script (an editor, a `cat`) is not a poller and would leave
# the pane deaf. The stop ending a wake turn (stop_hook_active) starts the next
# poller only when the wake left its mark, or the chain would arm with no wake.
# Every other pane runs both hooks on every turn and must never be held or armed,
# and `stop_hook_active` must pass the waiter or its block would loop forever.
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

# The arm hook runs from a copy of the plugin whose poller is a stub, so the real inbox is never read.
PLG=$BOX/plugin; mkdir -p "$PLG/hooks" "$PLG/scripts"
cp -R "$SOURCE/hooks/lib" "$PLG/hooks/lib"; cp "$SOURCE/hooks/cos-inbox-arm-stop.sh" "$PLG/hooks/"
cat >"$PLG/scripts/cos-watch-inbox.sh" <<EOF
#!/usr/bin/env bash
echo "\$\$ \$*" >>"$BOX/started"
[ ! -e "$BOX/poller.msg" ] || { cat "$BOX/poller.msg"; exit 0; }
[ ! -e "$BOX/poller.hang" ] || exec sleep 30
exit 0
EOF
# arm <worktree> <stop_hook_active JSON> [handle] -> "<exit status> <stderr>"; poller starts are logged to $BOX/started.
arm() {
  local err rc
  err=$(printf '{"stop_hook_active":%s}' "$2" \
    | HOME=$BOX/home PATH=$BOX/bin:$PATH CLAUDE_PROJECT_DIR=$1 ORCA_TERMINAL_HANDLE=${3-$H} \
      COMMANDECK_REVIEWER= bash "$PLG/hooks/cos-inbox-arm-stop.sh" 2>&1 >/dev/null)
  rc=$?
  echo "$rc $err" | tr '\n' ' ' | sed 's/ *$//'
}
started() { [ -e "$BOX/started" ] && wc -l <"$BOX/started" | tr -d ' ' || echo 0; }
fresh() { rm -f "$BOX/started" "$BOX/poller.msg" "$BOX/poller.hang" "$KEY.inbox-woke"; }

P=/x/plugin/scripts/cos-watch-inbox.sh
procs ""
check "Chief-of-Staff with no poller and every other watcher up is not blocked" "0 none" "$(run "$COS" false)"
fresh
check "a stop with no inbox poller starts one for this pane and does not block" "0 1 $H" \
  "$(arm "$COS" false | cut -d' ' -f1) $(started) $(cut -d' ' -f2- "$BOX/started")"

fresh; echo "main: build done" >"$BOX/poller.msg"
OUT=$(arm "$COS" false)
check "the poller's message comes back on stderr with exit 2" "2 1" \
  "${OUT%% *} $(case $OUT in *"main: build done"*) echo 1;; *) echo 0;; esac)"
check "and the wake leaves the mark" "yes" "$([ -e "$KEY.inbox-woke" ] && echo yes || echo no)"

fresh
check "a poller that ends with no message wakes nobody" "0 1" "$(arm "$COS" false | cut -d' ' -f1) $(started)"
check "and leaves no mark" "no" "$([ -e "$KEY.inbox-woke" ] && echo yes || echo no)"

fresh; procs "bash $P $H"
check "a stop with this pane's poller already running starts no second one" "0 0" "$(arm "$COS" false | cut -d' ' -f1) $(started)"
procs "$P $H"; fresh
arm "$COS" false >/dev/null
check "a poller run directly counts" "0" "$(started)"

fresh; procs "bash $P term_other-2222" "bash $P ${H}2"
arm "$COS" false >/dev/null
check "a poller for another pane does not count" 1 "$(started)"
fresh; procs "cat $P" "vim $P $H" "/bin/zsh -c tail -f /tmp/log # $P" "/bin/bash $P" \
  "orca-ide orchestration check --terminal $H --wait --types worker_done,question --json"
arm "$COS" false >/dev/null
check "a command that only mentions the script, or a poller with no handle, does not count" 1 "$(started)"

fresh; procs ""; : >"$KEY.inbox-woke"
check "the stop after a wake starts the next poller" "0 1" "$(arm "$COS" true | cut -d' ' -f1) $(started)"
check "and clears the mark" "no" "$([ -e "$KEY.inbox-woke" ] && echo yes || echo no)"
check "a second stop of the same chain, with no wake before it, starts none" "0 1" "$(arm "$COS" true | cut -d' ' -f1) $(started)"
fresh
for A in '"true"' 1 '"yes"' null; do
  arm "$COS" "$A" >/dev/null
done
check "a stop_hook_active that is not JSON true reads as not active" 4 "$(started)"
fresh; : >"$KEY.inbox-woke"; printf 'junk{' | HOME=$BOX/home PATH=$BOX/bin:$PATH CLAUDE_PROJECT_DIR=$COS ORCA_TERMINAL_HANDLE=$H \
  bash "$PLG/hooks/cos-inbox-arm-stop.sh" >/dev/null 2>&1
check "junk input reads as not active" 1 "$(started)"

# The hook ends the poller it started when the harness stops it.
fresh; : >"$BOX/poller.hang"
printf '{"stop_hook_active":false}' | HOME=$BOX/home PATH=$BOX/bin:$PATH CLAUDE_PROJECT_DIR=$COS ORCA_TERMINAL_HANDLE=$H \
  bash "$PLG/hooks/cos-inbox-arm-stop.sh" >/dev/null 2>&1 &
HPID=$!
for _ in $(seq 50); do [ "$(started)" = 1 ] && break; sleep 0.1; done
PPID_=$(cut -d" " -f1 "$BOX/started")
kill -TERM "$HPID" 2>/dev/null; wait "$HPID" 2>/dev/null; sleep 0.3
check "stopping the hook ends the poller it started" "gone" "$(kill -0 "${PPID_:-0}" 2>/dev/null && echo alive || echo gone)"
fresh

for who in "AGENT_KIND=codex" "COMMANDECK_REVIEWER=1"; do
  printf '{"stop_hook_active":false}' | env "$who" HOME=$BOX/home PATH=$BOX/bin:$PATH CLAUDE_PROJECT_DIR=$COS ORCA_TERMINAL_HANDLE=$H \
    bash "$PLG/hooks/cos-inbox-arm-stop.sh" >/dev/null 2>&1
done
arm "$WT" false >/dev/null; arm "$MAIN" false >/dev/null; arm "$COS" false "" >/dev/null
check "a non-relay pane, a reviewer, Codex and a pane with no handle start none" 0 "$(started)"
fresh

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
up alerts limit check
ln -s "$SOURCE" "$BOX/home/.commandeck/plugin"; procs ""
OUT=$(jq -cn '{stop_hook_active:false}' | HOME=$BOX/home PATH=$BOX/bin:$PATH CLAUDE_PROJECT_DIR=$COS ORCA_TERMINAL_HANDLE=$H bash "$HOOK" 2>/dev/null | jq -r .reason)
check "with the inbox poller missing and the decisions watcher down, the stop blocks naming only the decisions watcher" "1 0" \
  "$(case $OUT in *"bash $BOX/home/.commandeck/plugin/scripts/cos-watch-decisions.sh"*) echo 1;; *) echo 0;; esac) $(case $OUT in *cos-watch-inbox*|*alerts*|*limit*) echo 1;; *) echo 0;; esac)"
rm "$BOX/home/.commandeck/plugin"

procs ""
check "stop_hook_active passes" "0 none" "$(run "$COS" true)"
check "a non-Chief-of-Staff pane passes" "0 none" "$(run "$WT" false)"
check "the main checkout passes" "0 none" "$(run "$MAIN" false)"
check "no pane handle passes (nothing to arm)" "0 none" "$(run "$COS" false "")"

# Issue 644: the owner reads this pane, so a reply of only verdicts, still-running lines or counts is held once.
# say <message> -> hook output JSON, watchers all up so only the reply check decides.
up decisions alerts limit check
say() { jq -cn --arg m "$1" '{stop_hook_active:false,last_assistant_message:$m}' \
  | HOME=$BOX/home PATH=$BOX/bin:$PATH CLAUDE_PROJECT_DIR=$COS ORCA_TERMINAL_HANDLE=$H COMMANDECK_REVIEWER= bash "$HOOK" 2>/dev/null; }
dec() { local o; o=$(say "$1"); if [ -n "$o" ]; then jq -r .decision <<<"$o"; else echo none; fi; }
check "verdict update held naming why" "block 1 1" \
  "$(dec "VERDICT: GO") $(say "VERDICT: GO" | jq -r .reason | grep -c verdict) $(say "VERDICT: GO" | jq -r .reason | grep -c 'owner reads this pane')"
check "still-running held" "block" "$(dec "unit-7: still running
unit-8: waiting on review")"
check "progress count held" "block" "$(dec "3 of 5 done
4/5")"
# Catches an ask-word match anywhere in a line: `reply` mid-line is no ask.
check "incidental ask word held" "block" "$(dec "wake-waste: GO, the reply path is fixed")"
# The second case catches a quote mark read as a regex word edge: a quoted ask line is an ask, and its verdict must
# not hold it. The third: a held reply names the words it matched.
check "question passes" "none none 1" "$(dec "VERDICT: GO. Merge now?") $(dec "> Confirm the scope
VERDICT: GO") $(say "u1: GO
3 of 5" | jq -r .reason | grep -c 'matched: GO 3 of 5)')"
check "bold question passes" "none" "$(dec "**Approve the merge**
VERDICT: GO")"
check "action line with count passes" "none" "$(dec "Approve 3 of 5 merges")"
check "limit percent passes" "none" "$(dec "7-day limit: 82%")"
check "empty or absent reply passes" "none none" "$(dec "") $(run "$COS" false | cut -d' ' -f2)"
check "verdict with news passes" "none" "$(dec "VERDICT: GO
The deploy moved to the new host and the old one is off.")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
