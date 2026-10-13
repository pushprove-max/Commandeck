#!/usr/bin/env bash
# Self-test for agent-awareness.sh. Run directly.
#
# The hook is a UserPromptSubmit banner, so its cost is paid on EVERY prompt of
# every session on the box. Three claims:
#   - only the coordinator reads it. A worker in a linked worktree dispatches
#     nothing, so it should not pay the scans or read the text.
#   - only when it changed. The same paragraph every turn is a paragraph nobody
#     reads; a state that moved prints again.
#   - every Orca RPC is bounded. A stalled runtime must not stall the prompt,
#     and the terminal-list call was the one with no cap.
#
# Orca IS running on this box, so its RPCs and its cgroup are stubbed: a live
# runtime would make the output move under the changed-state cases. The RPC
# bound is asserted against the hook text, which is where the cap lives.
set -u
export COMMANDECK_HOST_OS=Linux  # the systemctl stubs are the service manager under test

HOOK="$(cd "$(dirname "$0")/.." && pwd)/agent-awareness.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASS=0 FAIL=0

check()    { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
contains() { case "$3" in *"$2"*) PASS=$((PASS+1)); echo "ok   $1";; *) FAIL=$((FAIL+1)); echo "FAIL $1 (missing [$2] in [$3])";; esac; }
absent()   { case "$3" in *"$2"*) FAIL=$((FAIL+1)); echo "FAIL $1 (found [$2])";; *) PASS=$((PASS+1)); echo "ok   $1";; esac; }

BASE="$WORK/base"
mkdir -p "$BASE"
git init -q -b main "$BASE"
git -C "$BASE" config user.email t@t.t
git -C "$BASE" config user.name t
git -C "$BASE" commit -q --allow-empty -m base
# A pushed baseline, so the commits after it read as unpushed.
git -C "$BASE" update-ref refs/remotes/origin/main HEAD
git -C "$BASE" commit -q --allow-empty -m 'a commit main did not make'

# An Orca that answers nothing, and a cage well under budget.
STUB="$WORK/bin"; mkdir -p "$STUB"
printf '#!/bin/bash\nexit 0\n' > "$STUB/orca-ide"
# The Mac's BSD pgrep prints pids only, and with -a it matches its own
# ancestors, a fresh pid on every prompt. The hook must not rely on it.
printf '#!/bin/bash\necho "$PPID"\n' > "$STUB/pgrep"
chmod +x "$STUB/orca-ide" "$STUB/pgrep"
CAGE="$WORK/app-orca-1.scope"; mkdir -p "$CAGE"
cage_at() {  # $1 = GB of anon memory
  printf 'anon %d\nfile 1073741824\n' "$(( $1 * 1073741824 ))" > "$CAGE/memory.stat"
  printf '%d\n' $(( 36 * 1073741824 )) > "$CAGE/memory.max"
}
cage_at 4

# Since 2026-09-11 each dispatched pane runs in its own systemd scope, which
# sits OUTSIDE Orca's cgroup, so the cage number alone no longer sees the
# workers at all. These stand in for those boxes.
BOXES="$WORK/boxes"; mkdir -p "$BOXES"
box_at() {  # $1 = how many boxes, $2 = GB each
  rm -rf "$BOXES"; mkdir -p "$BOXES"
  for i in $(seq 1 "${1:-0}"); do
    mkdir -p "$BOXES/run-$i.scope"
    printf '%d\n' $(( $2 * 1073741824 )) > "$BOXES/run-$i.scope/memory.current"
    printf '%d\n' $(( 8 * 1073741824 ))  > "$BOXES/run-$i.scope/memory.max"
  done
}
box_at 0 0

SCRATCH="$WORK/scratch"; mkdir -p "$SCRATCH"

# main-watch.sh --status asks systemctl; it is up unless a case sets MW_DOWN=1.
SVC="$WORK/svc"; mkdir -p "$SVC"
printf '#!/bin/bash\ncase " $* " in *" is-active "*) exit "${MW_DOWN:-0}" ;; esac\nexit 0\n' > "$SVC/systemctl"
chmod +x "$SVC/systemctl"

run() {  # $1 = project dir, $2 = stub dir (defaults to the silent Orca)
  # COMMANDECK_SCRATCH must be stubbed: the hook reads seat records and kept-pane
  # markers out of it, so without this the test reads the real machine's panes.
  # HOME and COMMANDECK_MAIN too: the decision log is read from the primary
  # checkout, and nothing here may read the real one.
  CLAUDE_PROJECT_DIR="$1" COMMANDECK_AWARENESS_DIR="$WORK/state" \
    COMMANDECK_SCRATCH="$SCRATCH" HOME="$WORK/home" COMMANDECK_MAIN="$LIVE_MAIN" \
    COMMANDECK_ORCA_SCOPE_GLOB="$WORK/app-orca-*.scope" \
    COMMANDECK_PANE_SCOPE_GLOB="$BOXES/run-*.scope" PATH="${2:-$STUB}:$SVC:$PATH" \
    bash "$HOOK" 2>/dev/null
}

# A fake primary checkout and a fake HOME.
LIVE_MAIN="$WORK/live main"; mkdir -p "$LIVE_MAIN" "$WORK/home"

# --- the coordinator sees the state -----------------------------------------
OUT=$(run "$BASE")
contains "unpushed commits are surfaced" "UNPUSHED commit(s) on main" "$OUT"
contains "and the subject is shown" "a commit main did not make" "$OUT"

# --- ...once per state -------------------------------------------------------
check "the same state does not print twice" "" "$(run "$BASE")"
git -C "$BASE" commit -q --allow-empty -m 'a second one'
OUT=$(run "$BASE")
contains "a state that moved prints again" "UNPUSHED commit(s)" "$OUT"
check "and then goes quiet again" "" "$(run "$BASE")"
# Going quiet is suppression, not amnesia: pushing is a state change, so the
# banner comes back to say the commits are gone -- and only then goes quiet.
git -C "$BASE" update-ref refs/remotes/origin/main HEAD
OUT=$(run "$BASE")
absent "a push drops the commits from the banner" "UNPUSHED" "$OUT"
check "and with nothing left to report it is silent" "" "$(run "$BASE")"

# --- a worker in a linked worktree is not the audience ------------------------
WT="$WORK/wt"
git -C "$BASE" worktree add -q -b unit "$WT"
git -C "$WT" commit -q --allow-empty -m 'worker work'
OUT=$(run "$WT")
check "a linked worktree prints nothing" "" "$OUT"
absent "not even its own unpushed commits" "UNPUSHED" "$OUT"
# ...and the coordinator still would have reported that same tree.
check "the exemption is topology, not an empty tree" 1 \
  "$(git -C "$WT" rev-list --count origin/main..HEAD)"

# --- the over-budget warning is exempt from the once-per-state rule -----------
# It is the one line that must not be skimmed past, so it prints while it is
# true even though nothing else moved.
cage_at 30
OUT=$(run "$BASE")
contains "an over-budget cage warns" "OVER 28 GB in use" "$OUT"
# Resource safety sets no pane count: memory is the only limit.
absent "the cage line names no pane cap" "or 4 panes" "$OUT"
contains "and warns again on the very next prompt" "OVER 28 GB in use" "$(run "$BASE")"
cage_at 4
check "back under budget, it goes quiet" "" "$(run "$BASE")"

# --- the boxed panes count toward that budget ---------------------------------
# A pane's scope lands under app.slice, outside Orca's cgroup. Reading the cage
# alone would have said 4 GB while three workers held 27, which is the exact
# blind spot that let one runaway take the box down on 2026-09-11.
box_at 3 9
OUT=$(run "$BASE")
contains "boxed panes are added to the cage figure" "3 boxed pane(s) hold 27 GB outside the cage, 31 GB together" "$OUT"
contains "and they can trip the warning on their own" "OVER 28 GB in use" "$OUT"
# Box figures drift like the cage figures, so they are normalised out of the
# once-per-state hash too: below the budget they are noise, and above it the
# warning prints every turn regardless.
box_at 1 2
check "a box shrinking under budget is not itself news" "" "$(run "$BASE")"
git -C "$BASE" commit -q --allow-empty -m 'something real moved'
contains "but the figure is there when something real moves" \
  "1 boxed pane(s) hold 2 GB outside the cage, 6 GB together" "$(run "$BASE")"
box_at 0 0
check "with no boxes it settles again" "" "$(run "$BASE")"

# --- a drifting cage number is not a state change ------------------------------
# The cage's GB figures move a little on every prompt. Hashing them made the
# whole block reprint EVERY turn, so the once-per-state rule above never fired
# in real use: 1.3K tokens a turn for a paragraph that had not changed.
cage_at 5
check "a cage number that drifted under budget stays quiet" "" "$(run "$BASE")"
cage_at 9
check "and again at another figure" "" "$(run "$BASE")"
cage_at 30
contains "but crossing the budget still speaks up" "OVER 28 GB" "$(run "$BASE")"
cage_at 4
check "and settles again" "" "$(run "$BASE")"

# --- only tasks a live pane is working on are listed ---------------------------
# After a crash the ledger keeps every dispatched task whose pane is gone and
# every task created and never dispatched. On 2026-09-11 that was 29 rows, all
# but four dead, printed in full on every prompt. A dead row supports exactly
# one action, closing it, so a count carries it.
BUSY="$WORK/bin-busy"; mkdir -p "$BUSY"
cat > "$BUSY/orca-ide" <<'STUBEOF'
#!/bin/bash
for a in "$@"; do case "$a" in
  list)   echo '{"result":{"terminals":[{"handle":"term_live","agentIdentity":"codex"}]}}'; exit 0 ;;
  task-list) cat <<'JSON'
{"result":{"tasks":[
 {"id":"task_live","status":"dispatched","spec":"the one real job"},
 {"id":"task_dead1","status":"dispatched","spec":"pane died in the crash"},
 {"id":"task_dead2","status":"ready","spec":"never dispatched"},
 {"id":"task_dead3","status":"ready","spec":"never dispatched either"}]}}
JSON
    exit 0 ;;
esac; done
exit 0
STUBEOF
chmod +x "$BUSY/orca-ide"
# A task row names its CREATOR, never its assignee. The seat record is the only
# pairing of task to pane, so it is what decides live from dead.
printf 'handle=term_live\ntask=task_live\n' > "$SCRATCH/seat-live.txt"
OUT=$(run "$BASE" "$BUSY")
contains "the live pane's task is shown in full" "task_live dispatched: the one real job" "$OUT"
absent  "a dispatched task whose pane died is not"  "task_dead1" "$OUT"
absent  "nor a task that was never dispatched"      "task_dead2" "$OUT"
contains "the dead ones are one counted line"       "3 open task(s) with no live pane" "$OUT"
contains "and the pane count comes from the same list" "1 agent pane(s)" "$OUT"

# --- with no COMMANDECK_SCRATCH the hook reads the shared derived scratch -------
# A hook with its own formula reads an empty directory and reports every live
# task as dead. The path is spelled out here, not taken from paths.sh, so a
# changed formula fails this case instead of following it: the scratch is the
# session project's, never the folder the plugin's hook file sits in.
MAIN_DIR=$(dirname "$(git -C "$BASE" rev-parse --path-format=absolute --git-common-dir)")
DERIVED="$WORK/home2/.commandeck/scratch/$(printf '%s' "$MAIN_DIR" | tr -c 'A-Za-z0-9' '-')"
mkdir -p "$DERIVED"; cp "$SCRATCH/seat-live.txt" "$DERIVED/"
OUT=$(CLAUDE_PROJECT_DIR="$BASE" COMMANDECK_AWARENESS_DIR="$WORK/state-derived" HOME="$WORK/home2" \
  COMMANDECK_ORCA_SCOPE_GLOB="$WORK/app-orca-*.scope" COMMANDECK_PANE_SCOPE_GLOB="$BOXES/run-*.scope" \
  PATH="$BUSY:$SVC:$PATH" env -u COMMANDECK_SCRATCH -u COMMANDECK_MAIN bash "$HOOK" 2>/dev/null)
contains "with no override the seat record is read from the derived scratch" "task_live dispatched: the one real job" "$OUT"

# --- an ordinary prompt never peeks at the inbox or asks for a drain ---------
# Main drains the inbox once, on Orca's wake. A peek on every prompt
# told main to drain between wakes: a second fetch of what the wake delivers
#. The stub records every call, so a peek is caught even when silent.
INBOX="$WORK/bin-inbox"; mkdir -p "$INBOX"
cat > "$INBOX/orca-ide" <<STUBEOF
#!/bin/bash
echo "\$*" >> "$WORK/inbox-calls"
case "\$*" in *"orchestration check"*)
  echo '{"result":{"messages":[{"created_at":"2026-09-18T02:05:00Z","subject":"turn complete"}]}}' ;; esac
exit 0
STUBEOF
chmod +x "$INBOX/orca-ide"
: > "$WORK/inbox-calls"
OUT=$(run "$BASE" "$INBOX")
check    "an ordinary prompt issues no inbox check or peek" "" "$(grep 'orchestration check' "$WORK/inbox-calls")"
absent   "and surfaces no unread count"           "unread" "$OUT"
absent   "and requests no drain"                  "orca-wait.sh" "$OUT"
check    "nor does the hook carry one"            "" "$(grep -nE 'orchestration check|drain it now' "$HOOK")"
absent   "never the retired background wait"      "run_in_background" "$OUT"
check    "and no Monitor advice in the hook"      "" "$(grep -n 'Monitor' "$HOOK")"

# --- every Orca RPC is capped -------------------------------------------------
UNBOUNDED=$(grep -nE '(^|[^ ])[^-]orca-ide ' "$HOOK" | grep -v 'command -v' | grep -v 'timeout [0-9]')
check "no orca-ide call runs uncapped" "" "$UNBOUNDED"

# --- Codex helpers are not workers; only orphaned ones are reported ----------
# The Codex plugin runs app-server-broker.mjs (serve --cwd <worktree>) plus a
# `codex app-server` child per worktree. Nine pairs were listed every prompt as
# "headless workers" on 2026-09-18 although none was one. A broker whose
# worktree still exists is silent; one whose worktree is gone is one line with
# every pid to kill. codex exec / claude -p stay reported as before.
PROCS="$WORK/procs"; PS_STUB="$WORK/psbin"; mkdir -p "$PS_STUB" "$WORK/wt-live"
cp "$STUB/orca-ide" "$STUB/pgrep" "$PS_STUB/"
printf '#!/bin/bash\ncase "$*" in *ppid=,args=*) cat "%s" ;; *args=*) cut -d" " -f1,3- "%s" ;; *) cut -d" " -f1,2 "%s" ;; esac\n' "$PROCS" "$PROCS" "$PROCS" > "$PS_STUB/ps"
chmod +x "$PS_STUB/ps"
B=/x/node/app-server-broker.mjs
cat > "$PROCS" <<EOF
4101 1 node $B serve --endpoint unix:/tmp/a.sock --cwd $WORK/wt-live --pid-file /tmp/a.pid
4102 4101 codex app-server
4201 1 node $B serve --endpoint unix:/tmp/b.sock --cwd $WORK/wt-gone --pid-file /tmp/b.pid
4202 4201 codex app-server
4300 1 /Applications/Orca.app/Contents/MacOS/Orca
4301 4300 codex exec --json do the thing
4400 1 claude --dangerously-skip-permissions
4401 4400 claude -p summarise this
4500 1 /Applications/OtherApp.app/Contents/MacOS/OtherApp
4501 4500 claude -p --model sonnet render a reel
4502 4501 claude -p nested under the app's own headless claude
4601 1 codex exec orphaned to launchd
4510 4500 claude --model sonnet -p render
4511 4510 claude -p nested under a reordered headless parent
4701 4300 claude --model sonnet -p reordered under Orca
4702 4300 /x/bin/codex -m gpt-5 --search exec reordered under Orca
4703 4300 node /x/lib/codex e via node
4704 4300 codex please exec the tests
4706 1 codex -m gpt-5 run exec for me
4705 4706 codex exec under an interactive codex prompt
4801 4300 /bin/zsh -c echo claude --model x -p mentioned in a shell
EOF
OUT=$(run "$WORK/base" "$PS_STUB")
absent   "a live worktree's helper is not a worker"      "4102" "$OUT"
absent   "nor is its broker"                             "4101" "$OUT"
contains "an orphaned helper pair is one line with both pids" "2 orphaned Codex helper process(es)" "$OUT"
contains "naming both pids to kill"                      "kill 4201 4202" "$OUT"
contains "codex exec under Orca is still a worker"       "4301 codex exec" "$OUT"
contains "claude -p under a claude session is still a worker" "4401 claude -p" "$OUT"
# Another GUI app's headless claude is not ours (2026-10-01), nor is
# one nested under that app's own headless claude: a headless ancestor proves
# nothing, only Orca or an interactive claude/codex does.
absent   "another app's claude -p is not ours"           "4501" "$OUT"
absent   "nor its nested headless claude"                "4502" "$OUT"
absent   "nor a process with no Orca/claude/codex ancestry" "4601" "$OUT"
# Headless is a flag anywhere in argv, not right after the binary: a reordered
# `claude --model x -p` parent is still headless, so it anchors nothing.
absent   "a reordered headless parent is not an interactive anchor" "4511" "$OUT"
absent   "nor is that reordered foreign parent listed"   "4510" "$OUT"
contains "a reordered claude -p under Orca is a worker"  "4701 claude --model sonnet -p" "$OUT"
contains "and so is a codex exec after global flags"     "4702 /x/bin/codex -m gpt-5" "$OUT"
contains "and a codex exec (alias e) run by node"        "4703 node /x/lib/codex e" "$OUT"
# Codex's subcommand is its first positional, not any word: `exec` in an
# interactive prompt is neither headless nor stops that codex anchoring.
absent   "an interactive codex prompt saying exec is not a worker" "4704 codex please" "$OUT"
contains "and it still anchors its own codex exec"       "4705 codex exec" "$OUT"
# The binary is the program, not a word: a shell whose command text mentions
# `claude ... -p` is not a worker.
absent   "a shell mentioning claude -p is not a worker"  "4801" "$OUT"
contains "and the worker count leaves the helpers out"   "6 headless worker process(es)" "$OUT"

# --- a driver's line reads its own log, never a sibling unit's -------
# ring-routing's line showed ring-routing-sentinel's seat: the log was picked by
# name prefix, newest first. loop-run.sh names it <unit>-<kind>-<epoch>.log.
DRV="$WORK/drvbin"; mkdir -p "$DRV" "$SCRATCH/scratchpad"
cp "$STUB/orca-ide" "$DRV/orca-ide"
printf '#!/bin/bash\nprintf "%%s loaded active running x\\n" drive-ring-routing-100.service drive-ring-routing-sentinel-200.service\n' > "$DRV/systemctl"
chmod +x "$DRV/systemctl"
echo "own seat implementer=term_own" > "$SCRATCH/scratchpad/ring-routing-drive-100.log"
touch -d '1 minute ago' "$SCRATCH/scratchpad/ring-routing-drive-100.log"
echo "sibling seat implementer=term_sib" > "$SCRATCH/scratchpad/ring-routing-sentinel-drive-200.log"
OUT=$(run "$WORK/base" "$DRV")
LINE=$(printf '%b\n' "$OUT" | grep 'drive-ring-routing-100 ' || true)
contains "a driver's line shows its own log"        "own seat" "$LINE"
absent   "and never a sibling unit's newer log"      "term_sib" "$LINE"

# --- the Mac runs unboxed (the owner 2026-09-29): no memory line ------------------
# A memory_pressure with no figure was a "dispatch nothing" block under the
# old sampled admission; now nothing on the Mac speaks about memory at all.
MAC="$WORK/mac"; mkdir -p "$MAC"
printf '#!/usr/bin/env bash\n[ "$1" != list ] || printf "PID\\tStatus\\tLabel\\n42\\t0\\tcom.commandeck.main-watch\\n"\n' >"$STUB/launchctl"; chmod +x "$STUB/launchctl"
printf '#!/usr/bin/env bash\nexit 1\n' >"$MAC/mp"; chmod +x "$MAC/mp"
mac_run() { COMMANDECK_HOST_OS=Darwin COMMANDECK_MEMORY_PRESSURE="$MAC/mp" run "$WORK/base"; }
rm -rf "$WORK/state"
OUT=$(mac_run)
absent   "a Mac prints no memory admission line" "Mac memory" "$OUT"
absent   "and never holds dispatch for memory" "dispatch nothing" "$OUT"
absent   "a Mac never prints the Linux cage line" "Orca cage:" "$OUT"
# A launchctl that cannot answer hides every live driver and any running chain:
# the hook says the state is unknown instead of printing an empty driver list.
printf '#!/usr/bin/env bash\nexit 77\n' >"$STUB/launchctl"
OUT=$(mac_run)
contains "an unreadable launchd names the unknown service state" "SERVICE STATE UNKNOWN" "$OUT"

# --- main-watch down ----------------------------------------------------------
# Nothing else wakes main, so the line repeats on every prompt: the
# once-per-state rule must not swallow it.
contains "a down main-watch is named"             "MAIN-WATCH NOT RUNNING" "$(MW_DOWN=1 run "$BASE")"
contains "on every prompt, not once"              "MAIN-WATCH NOT RUNNING" "$(MW_DOWN=1 run "$BASE")"
absent   "and a running one says nothing"         "MAIN-WATCH" "$(run "$BASE")"

# --- the owner's open decisions print every turn until answered ---------------------
# An ask the owner answered in chat stays open on the dashboard unless main records
# the answer, so the open ids and the command that closes them repeat.
mkdir -p "$LIVE_MAIN/.claude/metrics"
jq -cn '{id: "push-now", askedAt: "t", question: "Push?", proposedDefault: "yes", source: "main", answeredAt: null, answer: null},
        {id: "done-one", askedAt: "t", question: "Ring?", proposedDefault: "none", source: "main", answeredAt: "t", answer: "internal"}' \
  > "$LIVE_MAIN/.claude/metrics/decisions.jsonl"
OUT=$(run "$BASE")
contains "an open decision the owner was asked is listed for main" "push-now" "$OUT"
absent   "an answered one is not"                           "done-one" "$OUT"
contains "with the command that records his answer"         "decision.sh answer" "$OUT"
contains "and again next turn with nothing changed"         "push-now" "$(run "$BASE")"
check    "a linked-worktree worker hears none of it"        "" "$(run "$WT")"
rm "$LIVE_MAIN/.claude/metrics/decisions.jsonl"

# --- slow paths ---------------------------------------------------------------
# A driver's log tail moves on every prompt while a loop runs. It must not
# defeat the once-per-state rule: the stage word stays in the hash, the tail
# only rides along when the block prints.
CH="$WORK/chbin"; mkdir -p "$CH"
cp "$STUB/orca-ide" "$CH/orca-ide"
printf '#!/bin/bash\nprintf "%%s loaded active running x\\n" chain-demo-300.service\n' > "$CH/systemctl"
chmod +x "$CH/systemctl"
echo "stage one" > "$SCRATCH/scratchpad/chain-demo-300.log"
rm -rf "$WORK/state"
OUT=$(run "$WORK/base" "$CH")
contains "the driver block prints on a fresh state" "chain-demo-300" "$OUT"
check "the same state again prints nothing" "" "$(run "$WORK/base" "$CH")"
echo "stage two" >> "$SCRATCH/scratchpad/chain-demo-300.log"
check "a moved driver log tail alone reprints nothing" "" "$(run "$WORK/base" "$CH")"

# The Orca calls are independent, so they overlap. The stub marks itself
# running, waits, and records an overlap if another call was running too.
PAR="$WORK/parbin"; mkdir -p "$PAR" "$WORK/par"
cat > "$PAR/orca-ide" <<PAREOF
#!/bin/bash
touch "$WORK/par/run.\$\$"
sleep 0.4
[ "\$(ls "$WORK/par"/run.* | wc -l)" -gt 1 ] && touch "$WORK/par/overlapped"
rm -f "$WORK/par/run.\$\$"
PAREOF
chmod +x "$PAR/orca-ide"
rm -rf "$WORK/state"; run "$WORK/base" "$PAR" >/dev/null
check "the Orca calls run concurrently" yes "$([ -e "$WORK/par/overlapped" ] && echo yes || echo no)"

# A stalled runtime is reported as not checked, never read as an empty ledger.
TO="$WORK/tobin"; mkdir -p "$TO"
cp "$STUB/orca-ide" "$TO/orca-ide"
printf '#!/bin/bash\nexit 124\n' > "$TO/timeout"; chmod +x "$TO/timeout"
rm -rf "$WORK/state"
OUT=$(run "$WORK/base" "$TO")
contains "a timed-out Orca call says NOT CHECKED" "NOT CHECKED" "$OUT"
contains "and names the 20 s limit" "20s" "$OUT"
check "every Orca call carries the explicit 20 s cap" 3 "$(grep -cE 'timeout 20 orca-ide' "$HOOK")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
