#!/usr/bin/env bash
# Self-test for scripts/long-job.sh: main's long jobs run in their own
# terminal, so a restart of main never kills one. A job's liveness is the flock its runner holds for the job's
# whole life, never the pane list: Orca's list stops showing a shell pane as live 120 s after launch, and a
# 10-minute job must still refuse a second start then. One fake: orca-ide, whose `terminal create` runs the
# command in a background process group and whose `terminal list` shows every pane it made with no agent.
# Run: bash scripts/run-shell-tests.sh scripts/__tests__/long-job.test.sh
set -u
REAL=$(cd "$(dirname "$0")/../.." && pwd)
JOB=$REAL/scripts/long-job.sh
TMP=$(mktemp -d)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected $2, got $3)"; fi; }
cleanup() {
  local p
  while read -r p _; do kill -KILL -- "-$p" 2>/dev/null; done < "$TMP/panes" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/main"
git -C "$TMP/main" init -q
: > "$TMP/panes"
cat > "$TMP/bin/orca-ide" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_CALLS"
case "$1 $2" in
  "terminal create")
    while [ $# -gt 0 ]; do case $1 in --command) cmd=$2; shift ;; --title) title=$2; shift ;; esac; shift; done
    n=$(( $(wc -l < "$FAKE_PANES") + 1 ))
    # FAKE_NOSTART: Orca opens the pane but its runner never starts.
    [ -z "${FAKE_NOSTART-}" ] || { echo "999999 term_job$n $title" >> "$FAKE_PANES"; printf '{"ok":true,"result":{"terminal":{"handle":"term_job%s"}}}\n' "$n"; exit 0; }
    set -m
    # Orca starts a pane from the app, so the pane inherits none of the caller's descriptors (open_pane's lock).
    ( for fd in /dev/fd/*; do fd=${fd##*/}; [ "$fd" -gt 2 ] && eval "exec $fd>&-"; done 2>/dev/null
      exec bash -c "$cmd" ) </dev/null >/dev/null 2>&1 &
    echo "$! term_job$n $title" >> "$FAKE_PANES"
    printf '{"ok":true,"result":{"terminal":{"handle":"term_job%s"}}}\n' "$n" ;;
  "terminal list")
    # main's Claude pane, once $TMP/mainpane exists: where to-main.sh finds the pane to message.
    jq -cn --rawfile p "$FAKE_PANES" --arg main "$(cat "$FAKE_MAINPANE" 2>/dev/null)" '{ok: true, result: {terminals: ([$p | split("\n")[] | select(length > 0) | split(" ")
      | {handle: .[1], title: .[2], agentIdentity: null, connected: true}]
      + (if $main == "" then [] else [{handle: "term_main", worktreePath: $main, agentIdentity: "claude", connected: true}] end))}}' ;;
  "orchestration send")
    # $TMP/sendrefuse: Orca answers ok:false, as it does for a message it will not take.
    if [ -e "$FAKE_SENDREFUSE" ]; then echo '{"ok":false,"error":{"code":"refused"}}'; else echo '{"ok":true}'; fi ;;
  "repo list") printf '%s\n' "${FAKE_REPOS-}" ;;
esac
exit 0
SH
chmod +x "$TMP/bin/orca-ide"
export PATH="$TMP/bin:$PATH" COMMANDECK_SCRATCH=$TMP/scratch COMMANDECK_MAIN=$TMP/main COMMANDECK_HOST_OS=Darwin \
  FAKE_CALLS=$TMP/calls FAKE_PANES=$TMP/panes FAKE_MAINPANE=$TMP/mainpane FAKE_SENDREFUSE=$TMP/sendrefuse
JOBS=$COMMANDECK_SCRATCH/long-jobs
lj() { (cd "$TMP/main" && bash "$JOB" "$@") > "$TMP/out" 2>&1; echo $?; } # as main's pane runs it: from the main checkout
ljw() { (cd "$TMP/wt" && bash "$JOB" "$@") > "$TMP/out" 2>&1; echo $?; } # from a linked worktree of that checkout
creates() { grep -c -- "--title job:$1 " "$TMP/calls"; }

check "start runs the job in its own terminal" "0 1" "$(lj start ok -- printf '%s\n' hello world) $(creates ok)"
check "wait on a finished job: 0, its rc and the log's tail" "0 1 1" \
  "$(lj wait ok 20) $(grep -c 'rc=0' "$TMP/out") $(grep -cx 'world' "$TMP/out")"
check "a job exiting 7: wait still exits 0 and prints rc=7" "0 0 1" \
  "$(lj start seven -- bash -c 'exit 7') $(lj wait seven 20) $(grep -c 'rc=7' "$TMP/out")"
lj start killed -- sleep 600 >/dev/null
pg=$(awk '$3 == "job:killed" { print $1 }' "$TMP/panes")
kill -KILL -- "-$pg"
check "wait on a job killed with KILL, no rc written: 1, died" "1 1" "$(lj wait killed 20) $(grep -c '^long-job: killed died: ' "$TMP/out")"
lj start slow -- sleep 600 >/dev/null
check "wait 1 on a running job: 3" 3 "$(lj wait slow 1)"
# The judge's case: Orca's pane list no longer counts the pane as live 120 s after launch.
lj start cov -- sleep 600 >/dev/null
awk -F'\t' -v OFS='\t' -v t="$(( $(date +%s) - 121 ))" '$2 == "job:cov" { $4 = t } 1' "$COMMANDECK_SCRATCH/pane-titles.tsv" > "$TMP/titles"
cp "$TMP/titles" "$COMMANDECK_SCRATCH/pane-titles.tsv"
# A second start of a job running past the 120 s window is refused, names the job, and opens no pane.
check "a second start fails" "1 1 1" \
  "$(lj start cov -- sleep 600) $(grep -c 'cov is running' "$TMP/out") $(creates cov)"
( lj start dup -- sleep 600 > "$TMP/dup1" ) & ( lj start dup -- sleep 600 > "$TMP/dup2" ) & wait
check "two starts of one name at once open one pane: one starts, one is refused" "0 1 1" \
  "$(cat "$TMP/dup1" "$TMP/dup2" | sort | paste -sd' ' -) $(creates dup)"
long=$(printf 'x%.0s' $(seq 1100))
lj start long -- printf '%s\n' "$long" LONG-END >/dev/null
check "a command over 1,000 bytes runs whole" "0 1" "$(lj wait long 20) $(grep -cx 'LONG-END' "$TMP/out")"
check "a start over an unread result is refused and prints that result" "1 1" "$(lj start ok -- true) $(grep -c 'rc=0' "$TMP/out")"
lj list >/dev/null
check "list shows each state: running, done with its rc, died" "1 1 1" \
  "$(grep -c '^slow: running' "$TMP/out") $(grep -c '^seven: done rc=7' "$TMP/out") $(grep -c '^killed: died' "$TMP/out")"
check "a job name that is not a plain word is refused" 2 "$(lj start ../x -- true)"
# x.start.lock is the start lock of x, so a job named x.start would share it and vanish from list.
check "a job name ending .start is refused, so list never hides a job" 2 "$(lj start cov.start -- true)"
# long-job.sh records the exit code of exactly what it runs, so a command run beside the suite would stand in for
# its result: `npm test & echo launched` records 0 at once, `npm test; echo x` records echo's 0. A compound command,
# at any depth of nested shell text, is refused before a pane opens; a redirect is not a separator.
for c in 'exit 7; true' 'exit 7 && true' 'exit 7 || true' 'exit 7 | cat' 'exit 7 & true' 'exit 7'$'\n''true' \
  "bash -c 'exit 7 & echo launched'" 'echo "a; b"'; do
  check "a compound command is refused and opens no pane: $c" "2 0 1" \
    "$(lj start cmp -- bash -c "$c") $(creates cmp) $(grep -c 'one command' "$TMP/out")"
done
check "a command with 2>&1, >&2 and &> is one command and runs" "0 0 1" \
  "$(lj start redir -- bash -c 'exit 7 2>&1 >&2 &>/dev/null') $(lj wait redir 20) $(grep -c 'rc=7' "$TMP/out")"
rm -rf "$JOBS"
check "list with no jobs prints nothing" "0 0" "$(lj list) $(wc -c < "$TMP/out" | tr -d ' ')"

# a merge run as a job starts a chain that wakes main's pane, but the job pane's own handle is not main's,
# so start records the caller's handle in the job's command as LONG_JOB_HANDLE (and none when it has none).
ORCA_TERMINAL_HANDLE=main-h lj start hnd -- true >/dev/null
check "start records the caller's handle in the job's command as LONG_JOB_HANDLE" 1 "$(grep -c -- '--command .*LONG_JOB_HANDLE=main-h ' "$TMP/calls")"
ORCA_TERMINAL_HANDLE= lj start nohnd -- true >/dev/null
check "start with no caller handle records an empty LONG_JOB_HANDLE" 1 "$(grep -- '--title job:nohnd ' "$TMP/calls" | grep -c "LONG_JOB_HANDLE='' ")"

# start opens its pane in main's checkout, so from a worktree it would run main's code and test main's tree,
# a silent wrong answer. It is refused before anything is made; wait and list are read-only and work anywhere.
git -C "$TMP/main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "$TMP/main" worktree add -q "$TMP/wt" -b wt
# Pane opens only: an earlier job finishing now sends main its done message, which logs other calls.
CALLS_BEFORE=$(grep -c '^terminal create' "$TMP/calls")
check "start from a linked worktree is refused, naming run_in_background" "2 1" \
  "$(ljw start fromwt -- true) $(grep -c 'run_in_background' "$TMP/out")"
check "and it opened no pane and made no file for the job" "0 0" \
  "$(( $(grep -c '^terminal create' "$TMP/calls") - CALLS_BEFORE )) $(ls "$JOBS" 2>/dev/null | grep -c '^fromwt\.')"
check "start from outside any repository is refused too" 2 "$(cd /tmp && bash "$JOB" start fromtmp -- true >/dev/null 2>&1; echo $?)"
check "a job started in main can be waited on and listed from a worktree" "0 0 0 1" \
  "$(echo "$(lj start fin -- true) $(ljw wait fin 20) $(ljw list) $(grep -c '^fin: done rc=0' "$TMP/out")")"

# a wait with no max stays under the 5-minute prompt cache (240 s), or 540 s on the 1-hour cache, as wait-test-run.sh.
check "--help names the 240 s default on the 5-minute cache" 1 \
  "$(CLAUDE_CODE_PROMPT_CACHE_TTL=5m bash "$JOB" --help | grep -c 'default 240')"
check "--help names the 540 s default on the 1-hour cache" 1 \
  "$(CLAUDE_CODE_PROMPT_CACHE_TTL=1h bash "$JOB" --help | grep -c 'default 540')"
# The wait itself, with no max: an exported sleep function advances the script's own clock 60 s per poll.
lj start nomax -- sleep 600 >/dev/null
fastclock() { (sleep() { SECONDS=$((SECONDS + 60)); }; export -f sleep; CLAUDE_CODE_PROMPT_CACHE_TTL=$1 lj wait nomax); }
check "wait with no max gives up at 240 s on the 5-minute cache" "3 1" "$(fastclock 5m) $(grep -c 'after 240s' "$TMP/out")"
check "wait with no max gives up at 540 s on the 1-hour cache" "3 1" "$(fastclock 1h) $(grep -c 'after 540s' "$TMP/out")"

# the close of a pane whose runner never started goes through pp_pane_close, so pane-closes.log names it.
# A no-op sleep ahead on PATH ends the 30 s wait at once.
mkdir -p "$TMP/fastsleep"; printf '#!/bin/sh\nexit 0\n' > "$TMP/fastsleep/sleep"; chmod +x "$TMP/fastsleep/sleep"
check "a runner that never starts closes its pane through pp_pane_close (pane-closes.log line)" "1 1 1" \
  "$(PATH="$TMP/fastsleep:$PATH" FAKE_NOSTART=1 lj start nostart -- true) $(grep -c 'terminal close --terminal term_job' "$TMP/calls") $(grep -c 'long-job: runner did not start' "$COMMANDECK_SCRATCH/pane-closes.log")"

# a job record is archived only a day after main READ its result (wait printed it, or start's refusal did).
# An unread result of any age stays where wait, list find it, and start still refuses over it.
mkdir -p "$JOBS"
job() { : > "$JOBS/$1.lock"; echo "$1-log" > "$JOBS/$1.log"; echo "$2" > "$JOBS/$1.rc"; }
old() { touch -d '2 days ago' "$@"; }
job suite 7; old "$JOBS/suite.rc"; job gone 7; old "$JOBS/gone.rc"
check "prune keeps an unread result whatever its age" "0 1 0" \
  "$(lj prune) $(ls "$JOBS" | grep -c '^suite\.rc$') $(ls "$JOBS/archive" 2>/dev/null | wc -l | tr -d ' ')"
lj list >/dev/null
check "list shows the unread result as it did" 1 "$(grep -c '^suite: done rc=7$' "$TMP/out")"
check "wait on the old unread result still returns it" "0 1" "$(lj wait suite 5) $(grep -c 'rc=7' "$TMP/out")"
check "start still refuses over an unread result after its prune, and archives nothing" "1 1 0" \
  "$(lj start gone -- true) $(grep -c 'rc=7' "$TMP/out") $(ls "$JOBS/archive" 2>/dev/null | wc -l | tr -d ' ')"
check "wait marked the result read" "1 1" "$(ls "$JOBS" | grep -c '^suite\.read$') $(ls "$JOBS" | grep -c '^gone\.read$')"
lj list >/dev/null
check "list shows a read result" 1 "$(grep -c '^suite: done rc=7, read$' "$TMP/out")"
job busy 0; old "$JOBS/busy.rc"; rm -f "$JOBS/busy.rc"; : > "$JOBS/busy.read"; old "$JOBS/busy.read"
flock "$JOBS/busy.lock" sleep 60 & BUSY=$!
job rerun 0; : > "$JOBS/rerun.read"; old "$JOBS/rerun.read"
# The inline marker holds the done message back: with no main pane to-main.sh would queue it and stamp the rerun read.
: > "$JOBS/rerun.inline"
bash "$JOB" _run rerun -- true >/dev/null 2>&1
job failed 1; : > "$JOBS/failed.read"; old "$JOBS/failed.read"
old "$JOBS/suite.read"
lj prune >/dev/null
check "prune archives a read result a day after its read and keeps a running job" "0 1 1" \
  "$(ls "$JOBS" | grep '^suite\.' | grep -vc '\.start\.lock$') $(find "$JOBS/archive" -path '*/suite-*/suite.rc' | wc -l | tr -d ' ') $(ls "$JOBS" | grep -c '^busy\.lock$')"
check "a rerun's result is unread again, so prune keeps it" "1 0" "$(ls "$JOBS" | grep -c '^rerun\.rc$') $(ls "$JOBS" | grep -c '^rerun\.read$')"
check "a failed job's log is in the archive after it was read" 1 "$(cat "$JOBS"/archive/failed-*/failed.log 2>/dev/null | grep -c '^failed-log$')"
# A prune archives a whole record into a new directory of its own or leaves the live record untouched, whatever step
# fails: the archive dir, a path already where an archive file would go (rounds 2 and 3), or a copy. A rerun after it
# never rewrites what was archived, so an archived rc is never paired with a newer run's log; and the start lock is
# never unlinked, because a starter waiting on the old inode and one opening a new file would both pass the result check.
mkdir -p "$TMP/failcp"
printf '#!/bin/sh\n[ -z "${FAIL_CP-}" ] || case "$1" in *"$FAIL_CP") exit 1 ;; esac\nexec /bin/cp "$@"\n' > "$TMP/failcp/cp"
chmod +x "$TMP/failcp/cp"
mv "$JOBS/archive" "$JOBS/archive.keep"
: > "$JOBS/stuck.start.lock"
for c in dir:kept taken-rc:archived taken-log:archived taken-read:archived cp-rc:kept cp-log:kept cp-read:kept; do
  step=${c%:*}; want=${c#*:}
  job stuck 5; : > "$JOBS/stuck.read"; old "$JOBS/stuck.read"; m=$(stat -c %Y "$JOBS/stuck.read")
  case $step in
    dir) : > "$JOBS/archive" ;;
    taken-*) mkdir -p "$JOBS/archive/stuck-$m.${step#taken-}/stuck.${step#taken-}" ;;
  esac
  FAIL_CP=$([ "${step%-*}" != cp ] || echo "stuck.${step#cp-}") PATH="$TMP/failcp:$PATH" lj prune >/dev/null
  live=$(ls "$JOBS" | grep -cE '^stuck\.(lock|rc|log|read)$')
  if [ "$live" = 4 ] && [ "$(lj wait stuck 5)" = 0 ] && grep -q 'rc=5' "$TMP/out"; then got=kept
  elif [ "$live" = 0 ] && [ "$(cat "$JOBS"/archive/stuck-*/stuck.rc "$JOBS"/archive/stuck-*/stuck.log 2>/dev/null | paste -sd' ' -)" = "5 stuck-log" ]; then got=archived
  else got="split($(ls "$JOBS" | grep '^stuck\.' | paste -sd, -))"; fi
  rm -f "$JOBS/stuck.rc"; bash "$JOB" _run stuck -- echo new-run >/dev/null 2>&1
  check "a prune at the $step step is whole ($want), a rerun leaves the archive as it was, the start lock stays" "$want 0 1" \
    "$got $(find "$JOBS/archive" -type f -exec cat {} + 2>/dev/null | grep -cvxE '5|stuck-log') $(ls "$JOBS" | grep -c '^stuck\.start\.lock$')"
  rm -rf "$JOBS/archive"; rm -f "$JOBS"/stuck.{rc,log,read,lock,pid}
done
mv "$JOBS/archive.keep" "$JOBS/archive"
kill "$BUSY" 2>/dev/null

# the pane that launched a job is not the job. Killing the shell that ran `start` leaves the job running, and
# wait still returns its rc and output; a job that died with its launcher would leave a restarted main nothing to find.
rm -rf "$JOBS"; mkdir -p "$JOBS"
printf 'while [ ! -e "%s/go" ]; do sleep 0.1; done\necho SURVIVED\n' "$TMP" > "$TMP/surv.sh"  # start refuses a ; inside a word
( cd "$TMP/main" && bash "$JOB" start surv -- bash "$TMP/surv.sh" >/dev/null 2>&1; exec sleep 30 ) 2>/dev/null &
LAUNCHER=$!
for _ in $(seq 100); do [ -s "$JOBS/surv.pid" ] && break; sleep 0.1; done
kill -KILL "$LAUNCHER" 2>/dev/null; touch "$TMP/go"
check "a job whose launching shell is killed still finishes and wait returns its rc and output" "0 1 1" \
  "$(lj wait surv 20) $(grep -c 'rc=0' "$TMP/out") $(grep -cx 'SURVIVED' "$TMP/out")"

# a finished job messages main itself, with a `question` (orca-wait.sh hides `status`), so main need not sit in a
# wait. The runner is run here as the pane runs it, so the send is over when it returns. A seat job is reported by
# seat.sh collect, so it sends none. The result is marked read only when Orca took the message: a refused one stays
# unread for wait and list.
echo "$TMP/main" > "$FAKE_MAINPANE"; : > "$TMP/calls"
for j in ok2 ok3; do (cd "$TMP/main" && bash "$JOB" _run "$j" -- bash -c 'echo hello' >/dev/null 2>&1) & done; wait
check "a finished job messages main once with its rc and marks its result read" "1 1 1 1" \
  "$(grep -c -- "--type question --subject long-job ok2 done rc=0 " "$TMP/calls") $(grep -c -- "--type question --subject long-job ok3 done rc=0 " "$TMP/calls") $([ -e "$JOBS/ok2.read" ] && echo 1) $([ -e "$JOBS/ok3.read" ] && echo 1)"
check "and the message carries the log path and the job's output" "1 1" \
  "$(grep -c -- "--to term_main .*$JOBS/ok2.log" "$TMP/calls") $(grep -A2 -- 'long-job ok2 done' "$TMP/calls" | grep -c '^hello')"
: > "$TMP/calls"
(cd "$TMP/main" && bash "$JOB" _run seat-u-builder -- true >/dev/null 2>&1)
check "a seat job sends no done message" "0 1" "$(grep -c -- 'orchestration send' "$TMP/calls") $([ -f "$JOBS/seat-u-builder.rc" ] && echo 1)"
: > "$TMP/sendrefuse"
(cd "$TMP/main" && bash "$JOB" _run refused -- true >/dev/null 2>&1)
# A refused wake leaves the result unread for wait.
check "a refused message stays unread" "1 0 1" \
  "$(grep -c 'the done message to main was refused' "$JOBS/refused.log") $([ -e "$JOBS/refused.read" ] && echo 1 || echo 0) $(lj wait refused 5 | grep -c . >/dev/null; grep -c 'rc=0' "$TMP/out")"
rm -f "$TMP/sendrefuse"
# Bug caught: a message queued for a main that is not running (to-main.sh exit 3) left the result unread, so wait printed it twice.
mv "$TMP/mainpane" "$TMP/mainpane.off"
(cd "$TMP/main" && bash "$JOB" _run queued -- true >/dev/null 2>&1)
check "a queued message is read once" "1" "$([ -e "$JOBS/queued.read" ] && echo 1 || echo 0)"
mv "$TMP/mainpane.off" "$TMP/mainpane"

# run: start, then wait inline for the result. A .inline marker stops _run's done message while the waiter is
# still waiting; the waiter removes the marker and then checks .rc once more, so an edge result is printed twice at
# worst, never lost. The job is the same as start's, so a refusal is start's refusal.
sends() { grep -c -- 'orchestration send' "$TMP/calls"; }
S0=$(sends)
lj start ctl -- true >/dev/null
for _ in $(seq 50); do [ "$(sends)" -gt "$S0" ] && break; sleep 0.2; done
check "run: control, a started job sends main its done message" 1 "$(( $(sends) - S0 ))"
S0=$(sends)
check "run: quick job returns inline, no done message" "0 1 0 0" \
  "$(lj run quick -- true) $(grep -c 'done rc=0' "$TMP/out") $(sleep 3; echo $(( $(sends) - S0 ))) $(ls "$JOBS"/quick.inline 2>/dev/null | wc -l | tr -d ' ')"
check "run: a job that fails exits 0 and prints its rc, as wait does" "0 1" "$(lj run failing -- bash -c 'exit 7') $(grep -c 'rc=7' "$TMP/out")"
# rm is slowed for the marker only, so the job ends after the waiter stopped waiting and before the marker is gone:
# the done message is suppressed by the marker and only the waiter's second look at .rc can print the result.
rm() { local i; case "$*" in *edge.inline*) for i in $(seq 100); do [ -f "$JOBS/edge.rc" ] && break; command sleep 0.1; done; command sleep 1 ;; esac; command rm "$@"; }
export -f rm
check "run: edge of the limit is printed, never lost" "0 1" \
  "$(lj run edge --max 1 -- bash -c 'sleep 2') $(grep -c 'done rc=0' "$TMP/out")"
unset -f rm
check "run: a job still running at the limit exits 3 and names wait" "3 1 1" \
  "$(lj run lingering --max 1 -- sleep 600) $(grep -c 'still running' "$TMP/out") $(grep -c 'long-job.sh wait lingering' "$TMP/out")"
check "run: refused from a linked worktree like start, and leaves no marker" "2 1 0" \
  "$(ljw run fromwt2 -- true) $(grep -c 'run_in_background' "$TMP/out") $(ls "$JOBS"/fromwt2.* 2>/dev/null | wc -l | tr -d ' ')"
check "run: a compound command is refused like start" "2 1" "$(lj run cmp2 -- bash -c 'exit 7; true') $(grep -c 'one command' "$TMP/out")"
check "run: a bad --max is a usage error" 2 "$(lj run badmax --max x -- true)"

# a job in another Orca repo's checkout. FAKE_REPOS is what `orca-ide repo list --json` answers. A refused start
# opens no pane: a pane would run its command in whatever path it was handed.
rows() { local p; for p in "$@"; do printf '{"displayName":"%s","path":"%s"},' "${p%%=*}" "${p#*=}"; done | sed 's/,$//'; }
listing() { printf '{"ok":true,"result":{"repos":[%s]}}' "$(rows "$@")"; }
git -C "$TMP" init -q other && mkdir -p "$TMP/other/sub" "$TMP/gone-parent"
OTHER=$(cd "$TMP/other" && pwd -P)
check "repo_flag_opens_pane_in_repo: the pane opens on the listed checkout, and the job's result still lands in JOBS" "0 1 0 1" \
  "$(FAKE_REPOS=$(listing "Other=$OTHER") lj start inrepo --repo Other -- printf '%s\n' IN-REPO) $(grep -c -- "terminal create --worktree path:$OTHER --title job:inrepo " "$TMP/calls") $(lj wait inrepo 20) $(grep -cx IN-REPO "$TMP/out")"
check "bad_repo_name_refused: a name that walks out of the list, or an empty one that would fall back to main's checkout, is refused, no pane" "2 2 0" \
  "$(FAKE_REPOS=$(listing "../x=$OTHER") lj start badrepo --repo ../x -- true) $(FAKE_REPOS=$(listing "Other=$OTHER") lj start badrepo --repo '' -- true) $(creates badrepo)"
check "unknown_repo_refused: a repo Orca does not list gets no pane" "2 1 0" \
  "$(FAKE_REPOS=$(listing "Other=$OTHER") lj start unkrepo --repo nope -- true) $(grep -c 'nope' "$TMP/out") $(creates unkrepo)"
check "duplicate_repo_name_refused: two rows of one name could be either checkout, so neither runs" "2 0" \
  "$(FAKE_REPOS=$(listing "Other=$OTHER" "Other=$TMP/main") lj start duprepo --repo Other -- true) $(creates duprepo)"
check "repo_path_not_a_checkout_refused: a listed subfolder or a vanished path is no repo's top, so no pane" "2 2 0" \
  "$(FAKE_REPOS=$(listing "Other=$OTHER/sub") lj start stalerepo --repo Other -- true) $(FAKE_REPOS=$(listing "Other=$TMP/gone-parent/gone") lj start stalerepo --repo Other -- true) $(creates stalerepo)"
check "repo_list_failure_refused: an Orca that answers not ok, or nothing, opens no pane" "2 2 0" \
  "$(FAKE_REPOS='{"ok":false,"error":{"code":"down"}}' lj start failrepo --repo Other -- true) $(FAKE_REPOS= lj start failrepo --repo Other -- true) $(creates failrepo)"
check "repo_flag_refused_from_worktree: a worker may not run a command in another repo's main checkout" "2 1 0" \
  "$(FAKE_REPOS=$(listing "Other=$OTHER") ljw start wtrepo --repo Other -- true) $(grep -c 'run_in_background' "$TMP/out") $(creates wtrepo)"

# Issue 617: the evidence's load stamp is read by sourcing host-services.sh, and an owner's shell may be zsh, which sets
# no BASH_SOURCE and cannot load paths.sh: from another folder that printed a "no such file" line and missed the PATH repair.
if Z=$(command -v zsh); then
  ZERR=$(cd "$TMP" && "$Z" -fc ". ${REAL@Q}/scripts/host-services.sh; print -r -- \$HS_DIR; hs_stamp" 2>&1 >"$TMP/zsh.out")
  check "sourcing host-services.sh from zsh in another folder prints nothing on stderr" "" "$ZERR"
  check "sourcing host-services.sh from zsh sets HS_DIR to the scripts folder" "$REAL/scripts" "$(head -n 1 "$TMP/zsh.out")"
  check "and the load reading works from zsh" 1 "$(grep -c '"load1"' "$TMP/zsh.out")"
else echo "SKIP the three issue 617 cases: no zsh on this host"; fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
