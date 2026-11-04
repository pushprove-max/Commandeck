#!/usr/bin/env bash
# wake-on-exit.sh is the generic sanctioned launcher for a long job, and the
# whole point of it is that main always hears the job end. On 2026-09-20 main
# watched a chain with `tail -n 0 -f <log> | grep -q -m1 PATTERN` as a
# background Bash call; that pipeline cannot exit, so the harness never notified
# main and the tail sat alive for four hours. Every case below is a way this
# launcher could leave main deaf the same way: a wake that never fires, fires
# twice, carries the wrong exit code, or a launcher that blocks main instead of
# returning.
set -euo pipefail
export COMMANDECK_HOST_OS=Linux  # the systemd-run stub is the service manager under test

SOURCE=$(git rev-parse --show-toplevel)
SCRATCH=$(mktemp -d /tmp/wake-on-exit-test.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
unset CLAUDE_PROJECT_DIR

# The script runs from a copy of the plugin's scripts, so its stub to-main.sh and cos-tell.sh sit beside it, and from a
# project checkout of its own: the wake is sent from the caller's git top.
FAKE=$SCRATCH/plugin
mkdir -p "$FAKE" "$SCRATCH/home" "$SCRATCH/bin" "$SCRATCH/proj"
cp -R "$SOURCE/scripts" "$FAKE/"
SCRIPT=$FAKE/scripts/wake-on-exit.sh
git init -q "$SCRATCH/proj"
# Stub to-main.sh: the wake's one way to main. It records every send so the assertions can count exactly what main
# WOULD have been told, and where it was sent from; WAKE_TEST_TOMAIN_RC is its exit (0 posted, 3 queued, 1 refused).
cat > "$FAKE/scripts/to-main.sh" <<'EOF'
#!/usr/bin/env bash
echo SEND >> "$WAKE_TEST_SENDS"
printf '%s\n' "$*" >> "$WAKE_TEST_BODY"
pwd -P >> "$WAKE_TEST_CWD"
[ "${WAKE_TEST_TOMAIN_RC:-0}" != 1 ] || echo consumer_fenced >&2
case ${2:-} in "FYI event: "*) exit "${EVENT_RC:-0}" ;; esac  # an event's send exits EVENT_RC
exit "${WAKE_TEST_TOMAIN_RC:-0}"
EOF
# Stub cos-tell.sh: the relay's one way in; RELAY_RC is its exit.
cat > "$FAKE/scripts/cos-tell.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RELAY_LOG"
exit "${RELAY_RC:-0}"
EOF
# Stub orca-ide: answer the pane-liveness check only.
cat > "$SCRATCH/bin/orca-ide" <<'EOF'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "terminal list") printf '{"result":{"terminals":[{"handle":"%s"}]}}\n' "${WAKE_TEST_LIVE:-term_fake_main}" ;;
  *) echo '{"ok":true}' ;;
esac
EOF
# Two stub launchers. systemd-run returns the moment the unit is started, so the
# background one is what the real thing does; the synchronous one lets the
# assertions read the wake the unit actually sent.
cat > "$SCRATCH/bin/launch-sync" <<'EOF'
#!/usr/bin/env bash
# systemd-run reports whether the unit STARTED, never how the job ended, so
# this returns 0 whatever the command did. The exit code reaches main in the
# wake, which is exactly what the assertions read.
echo LAUNCH >> "$WAKE_TEST_LAUNCHES"
bash "${@: -1}"
exit 0
EOF
cat > "$SCRATCH/bin/launch-bg" <<'EOF'
#!/usr/bin/env bash
echo LAUNCH >> "$WAKE_TEST_LAUNCHES"
( bash "${@: -1}" >/dev/null 2>&1 & )
EOF
chmod +x "$SCRATCH/bin/orca-ide" "$SCRATCH/bin/launch-sync" "$SCRATCH/bin/launch-bg"

: > "$SCRATCH/sends"; : > "$SCRATCH/body"; : > "$SCRATCH/launches"
run() { # launcher-stub, then wake-on-exit.sh arguments
  local L=$1; shift
  (cd "$SCRATCH/proj" && PATH="$SCRATCH/bin:$PATH" HOME=$SCRATCH/home COMMANDECK_SCRATCH=$SCRATCH \
    ORCA_TERMINAL_HANDLE=term_fake_main \
    WAKE_TEST_SENDS=$SCRATCH/sends WAKE_TEST_BODY=$SCRATCH/body WAKE_TEST_CWD=$SCRATCH/cwd \
    WAKE_TEST_LAUNCHES=$SCRATCH/launches \
    COMMANDECK_WAKE_LAUNCHER=$L bash "$SCRIPT" "$@")
}
sends() { grep -c '^SEND$' "$SCRATCH/sends" || true; }

# 1. --help answers without the environment a run needs, in the house format:
#    main reads usage instead of source, so a flag the help omits is a
#    flag main has to go read the source for.
HELP=$(env -u ORCA_TERMINAL_HANDLE bash "$SCRIPT" --help 2>&1) || fail "--help exited non-zero"
case $HELP in "usage: wake-on-exit.sh"*) ;; *) fail "--help prints no usage line: $HELP" ;; esac
case $HELP in *$'\n'"example: "*) ;; *) fail "--help carries no example line" ;; esac
for FLAG in --print --cage --max; do
  case $HELP in *"$FLAG"*) ;; *) fail "--help does not name $FLAG" ;; esac
done

# 2. --print STARTS NOTHING. A dry run that launches is worse than no dry run:
#    it doubles the job while telling main it did not run it.
: > "$SCRATCH/launches"
OUT=$(run launch-sync --print demo -- bash -c 'exit 7') || fail "--print exited non-zero"
[ ! -s "$SCRATCH/launches" ] || fail "--print started the unit anyway"
[ "$(sends)" = 0 ] || fail "--print sent a wake"
case $OUT in *"systemd-run "*) ;; *) fail "--print did not print the launch command: $OUT" ;; esac
CMDFILE=$(printf '%s\n' "$OUT" | sed -n 's/^cmd=//p')
[ -f "$CMDFILE" ] || fail "--print wrote no command file at '$CMDFILE'"

# 3. The unit needs what it cannot inherit. A transient unit starts from a bare
#    environment: without PATH it has no orca-ide, and without the handle Orca
#    answers "could not determine the sender terminal". Either way the wake dies
#    in silence -- the loss of an earlier wake.
case $OUT in *--setenv=PATH=*) ;; *) fail "PATH is not forwarded into the unit" ;; esac
case $OUT in *--setenv=ORCA_TERMINAL_HANDLE=term_fake_main*) ;;
  *) fail "ORCA_TERMINAL_HANDLE is not forwarded into the unit" ;; esac
# The paths.sh overrides ride in too: without them a queued merge looks for the unit in the default workspaces
# folder, not the configured one the watcher admitted it from. Only those four: the launcher's own knobs stay out.
OUT=$(COMMANDECK_WORKSPACES=/srv/ws run launch-sync --print demo -- true) || fail "--print with overrides exited non-zero"
case $OUT in *--setenv=COMMANDECK_WORKSPACES=/srv/ws*) ;;
  *) fail "COMMANDECK_WORKSPACES is not forwarded into the unit: $OUT" ;; esac
case $OUT in *--setenv=COMMANDECK_SCRATCH=*) ;; *) fail "COMMANDECK_SCRATCH is not forwarded into the unit" ;; esac
case $OUT in *--setenv=COMMANDECK_WAKE_LAUNCHER=*) fail "a non-path COMMANDECK_ knob was forwarded into the unit" ;; esac

# 4. The cage: the chain's 28G box by default, and --cage overrides it.
case $OUT in *"MemoryMax=28G"*) ;; *) fail "the default cage is not MemoryMax=28G: $OUT" ;; esac
CAGED=$(run launch-sync --print --cage 2G demo -- true) || fail "--cage exited non-zero"
case $CAGED in *"MemoryMax=2G"*) ;; *) fail "--cage did not set MemoryMax: $CAGED" ;; esac

# 5. THE INVARIANT: one job, EXACTLY ONE wake, carrying the real exit code. A
#    second wake costs main a turn on a job it already handled; a wrong code
#    sends it looking for a failure that did not happen, or misses one that did.
: > "$SCRATCH/sends"; : > "$SCRATCH/body"
OUT=$(run launch-sync failing -- bash -c 'echo the-last-line; exit 7') \
  || fail "the launcher exited non-zero for a command that failed"
[ "$(sends)" = 1 ] || { echo "FAIL the wake goes through to-main (expected exactly one wake, got $(sends))" >&2; exit 1; }
BODY=$(cat "$SCRATCH/body")
case $BODY in "question failing: FAILED exit 7"*) ;; *) fail "the wake is not a question with the label and verdict on line 1: $BODY" ;; esac
[ "$(cat "$SCRATCH/cwd")" = "$(cd "$SCRATCH/proj" && pwd -P)" ] || fail "to-main.sh was not run from the caller's git top: $(cat "$SCRATCH/cwd")"
case $BODY in *"exit 7"*) ;; *) fail "the wake does not carry the real exit code: $BODY" ;; esac
case $BODY in *failing*) ;; *) fail "the wake does not carry the label: $BODY" ;; esac
case $BODY in *the-last-line*) ;; *) fail "the wake carries none of the log's last lines: $BODY" ;; esac
# the one post leaves one wake-log row, for the run's inbox, named by the job's label.
[ "$(jq -r '"\(.result) \(.reason) \(.to)"' "$SCRATCH/wake-log.jsonl")" = "posted failing main" ] \
  || fail "an exit post writes one wake-log row: $(cat "$SCRATCH/wake-log.jsonl")"

# 6. Main must be able to find the evidence without opening a pane.
LOG=$(printf '%s\n' "$OUT" | sed -n 's/.*log=\([^ ]*\).*/\1/p')
case $OUT in *unit=wake-failing-*) ;; *) fail "no unit name printed: $OUT" ;; esac
[ -s "$LOG" ] || fail "the printed log path '$LOG' holds nothing"
grep -q the-last-line "$LOG" || fail "the command's output did not reach $LOG"
# The send log carries the exit status first, for a person reading it.
grep -qx 'exit=7' "${LOG%.log}.send.log" || fail "the wake log does not carry exit=7 "

# 7. A job that passes still wakes main exactly once. A launcher that only
#    reports failures leaves main waiting out every success.
: > "$SCRATCH/sends"; : > "$SCRATCH/body"
run launch-sync passing -- true >/dev/null || fail "the launcher exited non-zero for a command that passed"
[ "$(sends)" = 1 ] || fail "a passing job sent $(sends) wakes, not 1"
case $(cat "$SCRATCH/body") in *"exit 0"*) ;; *) fail "a passing job did not report exit 0" ;; esac

# 8. IT NEVER BLOCKS MAIN. This is the whole difference from the hand-rolled
#    `tail -f | grep` that hung for four hours: the launcher returns while the
#    job is still running.
: > "$SCRATCH/sends"
START=$SECONDS
run launch-bg slow -- sleep 30 >/dev/null || fail "the launcher exited non-zero"
[ $((SECONDS - START)) -lt 5 ] || fail "the launcher waited $((SECONDS - START))s for a 30s command"

# 9. No wake PATH means no launch. Each of these would produce a job whose
#    result nobody ever hears about, which is the failure this script exists to
#    prevent -- so it has to refuse before starting anything.
: > "$SCRATCH/launches"
if PATH="$SCRATCH/bin:$PATH" HOME=$SCRATCH/home COMMANDECK_SCRATCH=$SCRATCH \
     WAKE_TEST_LAUNCHES=$SCRATCH/launches COMMANDECK_WAKE_LAUNCHER=launch-sync \
     env -u ORCA_TERMINAL_HANDLE bash "$SCRIPT" demo -- true >/dev/null 2>&1; then
  fail "launched with no ORCA_TERMINAL_HANDLE set"
fi
if PATH="$SCRATCH/bin:$PATH" HOME=$SCRATCH/home COMMANDECK_SCRATCH=$SCRATCH \
     ORCA_TERMINAL_HANDLE=term_fake_main WAKE_TEST_LIVE=term_someone_else \
     WAKE_TEST_SENDS=$SCRATCH/sends WAKE_TEST_BODY=$SCRATCH/body \
     WAKE_TEST_LAUNCHES=$SCRATCH/launches COMMANDECK_WAKE_LAUNCHER=launch-sync \
     bash "$SCRIPT" demo -- true >/dev/null 2>&1; then
  fail "launched from a handle Orca does not list, so the wake would be rejected"
fi
[ ! -s "$SCRATCH/launches" ] || fail "a refused launch started the unit anyway"
# A launch needs no run file: the wake goes through to-main.sh, so a bare HOME (no Orca run bound) still sends one wake.
: > "$SCRATCH/sends"
mkdir -p "$SCRATCH/empty-home"
(cd "$SCRATCH/proj" && PATH="$SCRATCH/bin:$PATH" HOME=$SCRATCH/empty-home COMMANDECK_SCRATCH=$SCRATCH \
   ORCA_TERMINAL_HANDLE=term_fake_main WAKE_TEST_SENDS=$SCRATCH/sends WAKE_TEST_BODY=$SCRATCH/body WAKE_TEST_CWD=$SCRATCH/cwd \
   WAKE_TEST_LAUNCHES=$SCRATCH/launches COMMANDECK_WAKE_LAUNCHER=launch-sync bash "$SCRIPT" norun -- true >/dev/null 2>&1) \
  || fail "a launch with no run file was refused"
[ "$(sends)" = 1 ] || fail "a launch with no run file sent $(sends) wakes, not 1"

# 10. A launcher that REFUSES must be loud. A job that never started is the
#     same silence one step earlier, and a quiet exit here looks like a launch.
if ERR=$(run false demo -- true 2>&1); then
  fail "the launcher refused and wake-on-exit.sh still reported a launch"
fi
case $ERR in *"NOTHING will wake main"*) ;; *) fail "a refused launcher says nothing useful: $ERR" ;; esac

# 11. The argv contract. `--` is what keeps the caller's own flags out of this
#     script's parser, so a missing one must stop rather than guess.
for BAD in "demo true" "-- true" "demo --"; do
  # shellcheck disable=SC2086
  if run launch-sync $BAD >/dev/null 2>&1; then fail "'$BAD' was accepted as a command line"; fi
done

# 12. TWO LAUNCHES INSIDE ONE SECOND MUST NOT COLLIDE. The unit, the log and
#     the command file are all named from the stamp, so a second-resolution
#     stamp makes the second launch refuse -- and worse, it rewrites the first
#     unit's command file before that unit has read it, so the first job runs
#     the second job's command. The clock is frozen here to make the race
#     certain rather than rare.
mkdir -p "$SCRATCH/frozen-bin" "$SCRATCH/units"
cat > "$SCRATCH/frozen-bin/date" <<'EOF'
#!/usr/bin/env bash
# It stands in for GNU date, so it answers the Mac preflight in paths.sh as one.
[ "${1:-}" = --version ] && { echo 'date (GNU coreutils) frozen test stub'; exit 0; }
printf '1700000000\n'
EOF
# systemd refuses a unit name that is already loaded; the stub refuses the same
# way, so a colliding name fails the launch exactly as it would in the run.
cat > "$SCRATCH/bin/launch-unique" <<'EOF'
#!/usr/bin/env bash
echo LAUNCH >> "$WAKE_TEST_LAUNCHES"
UNIT=
for ARG in "$@"; do case "$ARG" in --unit=*) UNIT=${ARG#--unit=} ;; esac; done
mkdir "$WAKE_TEST_UNITS/$UNIT" 2>/dev/null || { echo "unit $UNIT already loaded" >&2; exit 1; }
EOF
chmod +x "$SCRATCH/frozen-bin/date" "$SCRATCH/bin/launch-unique"
run_frozen() { # the same run, with the clock stuck on one second
  local L=$1; shift
  (cd "$SCRATCH/proj" && PATH="$SCRATCH/frozen-bin:$SCRATCH/bin:$PATH" HOME=$SCRATCH/home COMMANDECK_SCRATCH=$SCRATCH \
    ORCA_TERMINAL_HANDLE=term_fake_main \
    WAKE_TEST_SENDS=$SCRATCH/sends WAKE_TEST_BODY=$SCRATCH/body WAKE_TEST_CWD=$SCRATCH/cwd \
    WAKE_TEST_LAUNCHES=$SCRATCH/launches WAKE_TEST_UNITS=$SCRATCH/units \
    COMMANDECK_WAKE_LAUNCHER=$L bash "$SCRIPT" "$@")
}
unit_of() { local O=${1#*unit=}; printf '%s\n' "${O%% *}"; }
FIRST=$(run_frozen launch-unique repeated -- true) || fail "the first frozen-clock launch failed"
SECOND=$(run_frozen launch-unique repeated -- true) \
  || fail "a second launch with the same label inside one second was refused"
[ "$(unit_of "$FIRST")" != "$(unit_of "$SECOND")" ] \
  || fail "both launches took the unit name $(unit_of "$FIRST"), so the second overwrites the first"

# 13. The wake needs the main pane's handle, and a launch without one says which variable (the auto-merge watcher
#     has none of its own and passes the handle it resolved).
ERR=$(PATH="$SCRATCH/bin:$PATH" HOME=$SCRATCH/home COMMANDECK_SCRATCH=$SCRATCH COMMANDECK_WAKE_LAUNCHER=launch-sync \
  env -u ORCA_TERMINAL_HANDLE bash "$SCRIPT" merge-u -- true 2>&1) && fail "launched with no ORCA_TERMINAL_HANDLE"
case $ERR in *ORCA_TERMINAL_HANDLE*) ;; *) fail "the refusal does not name the variable: $ERR" ;; esac

# 14. CI watch: `--ci <sha>` is the same launcher under the label ci-<sha12>; the body, --ci-run, watches every
#     run of the commit and reruns a failed non-deploy run ONCE. A deploy workflow is only ever watched (both deploy
#     workflows start by dispatch alone, so no rerun may chain into one).
SHA=0123456789abcdef0123456789abcdef01234567
OUT=$(run launch-sync --print --ci "$SHA") || fail "--ci --print exited non-zero"
case $OUT in *"wake-ci-0123456789ab-"*"--ci-run $SHA"*|*"wake-ci-0123456789ab-"*) ;; *) fail "--ci did not launch under the label ci-<sha12>: $OUT" ;; esac
CMDFILE=$(printf '%s\n' "$OUT" | sed -n 's/^cmd=//p')
grep -q -- "--ci-run $SHA" "$CMDFILE" || fail "--ci does not run the --ci-run body on the sha: $(cat "$CMDFILE")"
if run launch-sync --ci 'not-a-sha;rm' >/dev/null 2>&1; then fail "--ci accepted something that is not a commit sha"; fi
GH=$SCRATCH/gh; mkdir -p "$GH"
cat > "$SCRATCH/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Runs listed in $GH/runs; per run id: path-<id> (workflow file), watch-<id> (one exit code per line, consumed),
# jobs-<id> (failed job names). Every rerun is logged.
case "$1 $2" in
  "run list") echo x >> "$GH/lists"; echo "$*" >> "$GH/listargs"; [ ! -e "$GH/list-fails" ] || exit 1; cat "$GH/runs"; [ ! -e "$GH/runs-next" ] || mv "$GH/runs-next" "$GH/runs" ;;
  "api "*) cat "$GH/path-${2##*/}" ;;
  "run watch") f=$GH/watch-$3; rc=$(head -1 "$f"); sed -i.bak 1d "$f"; exit "${rc:-0}" ;;
  "run view") cat "$GH/jobs-$3" ;;
  "run rerun") echo "$3 $4" >> "$GH/reruns" ;;
esac
EOF
chmod +x "$SCRATCH/bin/gh"
ci() { # shas of the runs -> output; $GH holds the stub's state
  : > "$GH/reruns"
  PATH="$SCRATCH/bin:$PATH" GH=$GH WAKE_CI_POLL_S=0 WAKE_CI_WAIT_S=1 bash "$SCRIPT" --ci-run "$SHA" ${EVENT:+--event "$EVENT"} 2>&1
}
ciset() { printf '%s\n' "${@:3}" > "$GH/watch-$1"; echo ".github/workflows/$2" > "$GH/path-$1"; echo "unit-tests" > "$GH/jobs-$1"; }
rm -f "$GH"/*
echo 101 > "$GH/runs"; ciset 101 ci.yml 1 0
OUT=$(ci) || fail "red then green: the watch exited non-zero: $OUT"
[ "$(wc -l < "$GH/reruns" | tr -d ' ')" = 1 ] || fail "red then green: expected exactly one rerun: $(cat "$GH/reruns")"
case $OUT in *"failed unit-tests, rerun green"*) ;; *) fail "red then green: the line does not say so: $OUT" ;; esac
ciset 101 ci.yml 1 1
OUT=$(ci) && fail "red twice: the watch exited zero"
[ "$(wc -l < "$GH/reruns" | tr -d ' ')" = 1 ] || fail "red twice: reran more than once: $(cat "$GH/reruns")"
case $OUT in *"rerun red"*) ;; *) fail "red twice: the line does not say rerun red: $OUT" ;; esac
printf '102\n' > "$GH/runs"; ciset 102 deploy-prod.yml 1
OUT=$(ci) && fail "a red deploy run exited zero"
[ ! -s "$GH/reruns" ] || fail "a deploy workflow was rerun: $(cat "$GH/reruns")"
case $OUT in *"deploy-prod.yml: failed unit-tests; watched, never rerun"*) ;; *) fail "the deploy line is wrong: $OUT" ;; esac
rm -f "$GH/path-102"; echo 1 > "$GH/watch-102"
OUT=$(ci) && fail "a run whose workflow path is unknown exited zero"
[ ! -s "$GH/reruns" ] || fail "a run whose workflow path could not be read was rerun: $(cat "$GH/reruns")"
printf '101\n' > "$GH/runs"; ciset 101 ci.yml 0
OUT=$(ci) || fail "a green run exited non-zero: $OUT"
case $OUT in *"ci.yml: green"*) ;; *) fail "a green run is not reported: $OUT" ;; esac
# Main's rule (2026-10-20): no run ever starting is "no CI started", not FAILED.
: > "$GH/runs"
OUT=$(ci) || fail "no run ever appeared for the commit and the watch read FAILED: $OUT"
case $OUT in *"no CI started for $SHA"*) ;; *) fail "no run: the watch does not say no CI started: $OUT" ;; esac
# A run that starts after the first listing is watched too: green on 101 must not hide a red 102.
printf '101\n' > "$GH/runs"; printf '101\n102\n' > "$GH/runs-next"; ciset 101 ci.yml 0; ciset 102 deploy-dev.yml 1
OUT=$(ci) && fail "a run that appeared after the first listing failed and the watch exited zero: $OUT"
case $OUT in *"deploy-dev.yml: failed"*) ;; *) fail "the late run is not reported: $OUT" ;; esac
# A commit whose workflows all start by hand (this repo's two deploys) reads "no CI started" at once; with a
# push-triggered workflow at the commit the watch first waits WAKE_CI_WAIT_S for a run, then reads the same.
R=$SCRATCH/ci-repo; mkdir -p "$R/.github/workflows"; git init -q "$R"
printf 'on:\n  # never add push triggers\n  workflow_dispatch:\n' > "$R/.github/workflows/deploy-dev.yml"
git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -q -m hand; HAND=$(git -C "$R" rev-parse HEAD)
printf 'on:\n  push:\n    branches: [main]\n' > "$R/.github/workflows/ci.yml"
git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -q -m push; PUSH=$(git -C "$R" rev-parse HEAD)
printf 'on: [push, workflow_dispatch]\n' > "$R/.github/workflows/ci.yml"
git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -q -m inline; INLINE=$(git -C "$R" rev-parse HEAD)
: > "$GH/runs"
OUT=$(cd "$R" && SHA=$HAND ci) || fail "no run is due for a commit whose workflows start by hand, and the watch failed: $OUT"
case $OUT in *"no CI started"*"starts on a push"*) ;; *) fail "the watch does not say no run was due: $OUT" ;; esac
for C in PUSH INLINE; do
  : > "$GH/lists"
  OUT=$(cd "$R" && SHA=${!C} ci) || fail "$C: no run started and the watch read FAILED: $OUT"
  case $OUT in *"no CI started"*) ;; *) fail "$C: the watch does not say no CI started: $OUT" ;; esac
  case $OUT in *"starts on a push"*) fail "$C: a push-triggered commit read as having no push trigger: $OUT" ;; esac
  [ "$(wc -l < "$GH/lists" | tr -d ' ')" -gt 1 ] || fail "$C: a run was due and the watch listed once, never waiting for it"
done
# A gh error is FAILED, never "no CI started": a failed listing may be hiding a red run.
touch "$GH/list-fails"
OUT=$(cd "$R" && SHA=$HAND ci) && fail "the run list failed and the watch read no CI started as OK: $OUT"
case $OUT in *"FAILED: the runs of"*"could not be listed"*) ;; *) fail "the watch does not say the listing failed: $OUT" ;; esac
rm -f "$GH/list-fails"
# a run started by hand (workflow_dispatch) is not a push run, so with no push workflow at the commit the watch read
# "no CI started" at once and never saw the deploy main had dispatched. --event <name> waits for a run of that event and
# lists only that event; without it nothing changes, so every plain --ci here does not wait for deploys nobody started.
: > "$GH/runs"; : > "$GH/lists"; : > "$GH/listargs"
OUT=$(cd "$R" && SHA=$HAND ci) || fail "a --ci watch with no --event failed at a commit whose workflows start by hand: $OUT"
[ "$(wc -l < "$GH/lists" | tr -d ' ')" = 1 ] && ! grep -q -- '--event' "$GH/listargs" \
  || fail "a --ci watch with no --event waited for a run or passed --event: $(cat "$GH/listargs")"
: > "$GH/runs"; : > "$GH/lists"; : > "$GH/listargs"; printf '103\n' > "$GH/runs-next"; ciset 103 deploy-dev.yml 0
OUT=$(cd "$R" && SHA=$HAND EVENT=workflow_dispatch ci) || fail "--event workflow_dispatch: the dispatched run was green and the watch failed: $OUT"
[ "$(wc -l < "$GH/lists" | tr -d ' ')" -gt 1 ] && grep -q -- '--event workflow_dispatch' "$GH/listargs" \
  || fail "--event workflow_dispatch listed once and read no CI started without waiting for the dispatched run"
case $OUT in *"deploy-dev.yml: green"*) ;; *) fail "--event workflow_dispatch did not watch the dispatched run: $OUT" ;; esac
[ "$(grep -vc -- '--event workflow_dispatch' "$GH/listargs" || true)" = 0 ] || fail "a gh run list of an --event watch left out --event: $(cat "$GH/listargs")"
OUT=$(run launch-sync --print --ci "$SHA" --event workflow_dispatch) || fail "--ci --event --print exited non-zero"
grep -q -- "--ci-run $SHA --event workflow_dispatch" "$(printf '%s\n' "$OUT" | sed -n 's/^cmd=//p')" || fail "--ci <sha> --event does not hand the event to the watch body"
if run launch-sync --ci "$SHA" --event 'x;rm' >/dev/null 2>&1; then fail "--event accepted something that is not an event name"; fi

# 15. A loop that re-runs a job must not wake main for the same result again. The same label and exit within the
#     hour is sent once (the host's rule, copied as is; nothing else re-sends the held-back wake).
: > "$SCRATCH/sends"
run launch-sync dedupe -- bash -c 'exit 3' >/dev/null || fail "dedupe: the first launch failed"
run launch-sync dedupe -- bash -c 'exit 3' >/dev/null || fail "dedupe: the second launch failed"
[ "$(sends)" = 1 ] || fail "the same label and exit within the hour sent $(sends) wakes, not 1"
DUP=$(ls -t "$SCRATCH"/scratchpad/wake-dedupe-*.send.log | head -1)
grep -q '^deduped: same result sent at [0-9]' "$DUP" || fail "the dropped wake left no trace in its send log: $(cat "$DUP")"
grep -qx 'exit=3' "$DUP" || fail "the deduped send log lost its exit line"
run launch-sync dedupe -- bash -c 'exit 4' >/dev/null || fail "dedupe: the other-exit launch failed"
[ "$(sends)" = 2 ] || fail "another exit status did not send (sends=$(sends))"
echo $(( $(date +%s) - 3700 )) > "$SCRATCH/scratchpad/wake-last-dedupe-3"
run launch-sync dedupe -- bash -c 'exit 3' >/dev/null || fail "dedupe: the stale-stamp launch failed"
[ "$(sends)" = 3 ] || fail "a stamp over an hour old did not send (sends=$(sends))"
# A send that fails writes no stamp, so the next identical result still tries.
WAKE_TEST_TOMAIN_RC=1 run launch-sync flaky -- bash -c 'exit 5' >/dev/null || fail "dedupe: the failing-send launch failed"
[ ! -e "$SCRATCH/scratchpad/wake-last-flaky-5" ] || fail "a send that failed left a stamp, so the retry would be dropped"
run launch-sync flaky -- bash -c 'exit 5' >/dev/null || fail "dedupe: the retry launch failed"
[ "$(sends)" = 5 ] || fail "the retry after a failed send did not send (sends=$(sends))"
# A refused to-main.sh send (exit 1) is no delivery, so it logs refused and leaves no stamp.
rm -f "$SCRATCH/wake-log.jsonl"
WAKE_TEST_TOMAIN_RC=1 run launch-sync fenced -- bash -c 'exit 6' >/dev/null || fail "dedupe: the refused-send launch failed"
[ "$(jq -r '"\(.result) \(.error | contains("consumer_fenced"))"' "$SCRATCH/wake-log.jsonl")" = 'refused true' ] \
  || fail "an ok:false receipt with exit 0 was logged as delivered: $(cat "$SCRATCH/wake-log.jsonl")"
[ ! -e "$SCRATCH/scratchpad/wake-last-fenced-6" ] || fail "a refused receipt left a stamp, so the retry would be dropped"
# A queued wake is stamped once: to-main.sh exit 3 (no main pane) holds the message for main's next session, so a repeat of the
# same result within the hour must not queue it twice.
: > "$SCRATCH/sends"; rm -f "$SCRATCH/wake-log.jsonl"
WAKE_TEST_TOMAIN_RC=3 run launch-sync held -- bash -c 'exit 8' >/dev/null || fail "queued: the first launch failed"
WAKE_TEST_TOMAIN_RC=3 run launch-sync held -- bash -c 'exit 8' >/dev/null || fail "queued: the second launch failed"
[ "$(sends)" = 1 ] || fail "a queued wake sent $(sends) times, not once"
[ "$(tail -1 "$SCRATCH/wake-log.jsonl" | jq -r '"\(.result) \(.reason) \(.to)"')" = "queued held main" ] \
  || fail "a queued wake is not logged as queued: $(cat "$SCRATCH/wake-log.jsonl")"
[ -e "$SCRATCH/scratchpad/wake-last-held-8" ] || fail "a queued wake left no stamp"
grep -q '^deduped:' "$(ls -t "$SCRATCH"/scratchpad/wake-held-*.send.log | head -1)" || fail "the second queued wake was not deduped"

# 16. A waiter has a lifetime: a looping command once outlived its purpose for days. --max (default 4 h) runs
#     it under timeout, and the one wake then reads FAILED exit 124 with the cap named in its body.
OUT=$(run launch-sync --print capped -- true) || fail "--print for the default cap exited non-zero"
grep -q 'timeout --kill-after=30 14400 ' "$(printf '%s\n' "$OUT" | sed -n 's/^cmd=//p')" || fail "the default lifetime is not 14400 s: $OUT"
OUT=$(run launch-sync --print --max 60 capped -- true) || fail "--print --max exited non-zero"
grep -q 'timeout --kill-after=30 60 ' "$(printf '%s\n' "$OUT" | sed -n 's/^cmd=//p')" || fail "--max 60 did not set the lifetime: $OUT"
run launch-sync --print --max soon capped -- true >/dev/null 2>&1 && fail "--max accepted a non-number"
: > "$SCRATCH/sends"; : > "$SCRATCH/body"
run launch-sync --max 1 overlong -- sleep 5 >/dev/null || fail "the launcher exited non-zero for a command past --max"
[ "$(sends)" = 1 ] && grep -q 'overlong: FAILED exit 124' "$SCRATCH/body" && grep -q 'lifetime cap' "$SCRATCH/body" \
  || fail "a command past --max did not give one FAILED exit 124 wake naming the cap: $(cat "$SCRATCH/body")"

# A command that ignores TERM takes timeout's KILL (exit 137) 30 s after the cap; a stub timeout stands in for that
# wait. The cap is named only when the KILL came at or after --max, never for a SIGKILL from something else.
mkdir -p "$SCRATCH/fakeT"
printf '#!/bin/sh\nsleep "$FAKE_TIMEOUT_AFTER"; exit 137\n' > "$SCRATCH/fakeT/timeout"; chmod +x "$SCRATCH/fakeT/timeout"
: > "$SCRATCH/sends"; : > "$SCRATCH/body"
FAKE_TIMEOUT_AFTER=2 PATH="$SCRATCH/fakeT:$PATH" run launch-sync --max 1 stubborn -- true >/dev/null || fail "the launcher exited non-zero for a forced kill"
grep -q 'stubborn: FAILED exit 137' "$SCRATCH/body" && grep -q 'lifetime cap' "$SCRATCH/body" \
  || fail "a command that needed the KILL after --max did not name the cap: $(cat "$SCRATCH/body")"
: > "$SCRATCH/sends"; : > "$SCRATCH/body"
FAKE_TIMEOUT_AFTER=0 PATH="$SCRATCH/fakeT:$PATH" run launch-sync --max 60 killed -- true >/dev/null || fail "the launcher exited non-zero for an early kill"
grep -q 'killed: FAILED exit 137' "$SCRATCH/body" && ! grep -q 'lifetime cap' "$SCRATCH/body" \
  || fail "a KILL well before --max was blamed on the cap: $(cat "$SCRATCH/body")"

# no_push_ci_names_dispatch_flag. Bug caught: main watching a hand-started deploy read "no CI started" and
# stopped, because the line never said the watch needs --event workflow_dispatch.
: > "$GH/runs"
OUT=$(cd "$R" && SHA=$HAND ci) || fail "no_push_ci_names_dispatch_flag: the watch failed: $OUT"
case $OUT in *"--ci ${HAND:0:12} --event workflow_dispatch"*) ;; *) fail "no_push_ci_names_dispatch_flag: the no-push line does not name the dispatch flag: $OUT" ;; esac

# push_wake_sends_event. Bug caught: a rejected or accepted push ended in a wake to main only, so its event was
# lost; the event must come from the job's own exit status and must never change the job's exit code. Issue 643:
# the event goes to main (a status on ok, a question on fail), never to the relay.
echo run_t > "$SCRATCH/current-run"  # events are sent only for a recorded run
export RELAY_LOG=$SCRATCH/relay-log
: > "$RELAY_LOG"; : > "$SCRATCH/sends"; : > "$SCRATCH/body"
run launch-sync push-abc123def456 -- bash -c 'exit 1' >/dev/null || fail "push_wake_sends_event: the launcher exited non-zero"
grep -q -- '^question FYI event: proj push fail abc123def456 exit 1' "$SCRATCH/body" && [ "$(grep -c 'FYI event:' "$SCRATCH/body")" = 1 ] \
  || fail "push_wake_sends_event: a refused push did not send main exactly one fail event: $(cat "$SCRATCH/body")"
: > "$SCRATCH/body"
run launch-sync push-abc123def457 -- true >/dev/null || fail "push_wake_sends_event: the launcher exited non-zero"
grep -q -- '^status FYI event: proj push ok abc123def457 exit 0' "$SCRATCH/body" \
  || fail "push_wake_sends_event: an accepted push did not send main an ok event: $(cat "$SCRATCH/body")"
: > "$SCRATCH/body"; : > "$SCRATCH/sends"
EVENT_RC=1 run launch-sync push-abc123def458 -- true >/dev/null || fail "push_wake_sends_event: a failing event send changed the launcher's exit"
[ "$(sends)" = 2 ] || fail "push_wake_sends_event: a failing event send changed the send count (wake and event) to $(sends)"
[ ! -s "$RELAY_LOG" ] || fail "push_wake_sends_event: an event reached the relay: $(cat "$RELAY_LOG")"
: > "$SCRATCH/body"
run launch-sync plainjob -- true >/dev/null || fail "push_wake_sends_event: the launcher exited non-zero"
[ "$(grep -c 'FYI event:' "$SCRATCH/body")" = 0 ] || fail "push_wake_sends_event: a job that is not a push, CI or deploy sent an event: $(cat "$SCRATCH/body")"

# ok_ci_status_push_question. Bug caught (issue 642): every OK job woke main at once. An OK CI watch is a status,
# which waits for main's batch; a push that exits 0 stays a question: the owner keeps push results waking main.
: > "$SCRATCH/body"
run launch-sync ci-abc123def459 -- true >/dev/null || fail "ok_ci_status_push_question: the launcher exited non-zero"
grep -q '^status ci-abc123def459: OK exit 0' "$SCRATCH/body" || fail "ok_ci_status_push_question: an OK ci job is not a status: $(cat "$SCRATCH/body")"
: > "$SCRATCH/body"
run launch-sync push-abc123def460 -- true >/dev/null || fail "ok_ci_status_push_question: the launcher exited non-zero"
grep -q '^question push-abc123def460: OK exit 0' "$SCRATCH/body" || fail "ok_ci_status_push_question: an OK push is not a question: $(cat "$SCRATCH/body")"

echo "ok: wake-on-exit.sh -- 23 cases"
