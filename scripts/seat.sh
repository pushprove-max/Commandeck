#!/usr/bin/env bash
# seat.sh launch <role> <unit> <spec-file>  -- open one routing.json seat in the
#     unit's worktree, hand it the spec (dispatch-task.sh's worker-start, retried
#     for about 60 s while Orca has not yet detected the pane's agent, then a
#     pane send when it is still refused), record handle and task under
#     $SCRATCH/seat-<unit>-<role>.txt. It returns once the pane, its task and that
#     record exist (phase=launching); the rest runs in the background, logged to
#     the record's .log, and ends phase=dispatched or phase=failed.
# seat.sh status <role> <unit> -- the record's phase, handle and task, whether its pane is live, gone or unknown, and its log's last line.
# seat.sh collect <role> <unit> [--report <path>] [--marker <text>] [--on-go <cmd>] [--on-nogo <cmd>]
#     -- read the pane's verdict and findings (read-verdict.sh), write them to
#     --report when the pane could not (a read-only Codex sandbox cannot), or with
#     none to $SCRATCH/reports/<unit>-<role>-<launched>.md (read-verdict.sh --seat), close
#     the task and the pane (a task that will not settle keeps the pane open and exits 4: rerun collect), print the findings and the VERDICT line, then run
#     the --on-go or --on-nogo command (from the repo root, via eval) that the
#     verdict selects, so a GO launches the next seat or loop in the same call.
#     --marker: a seat that ends on a marker line (plan-author's PLAN-DONE) and
#     prints no VERDICT is collected with the marker standing in for the verdict;
#     without it, collect falls back to the marker of the last wait.
# seat.sh wait <role> <unit> --marker <text> [--timeout-s <n>] -- block until the
#     pane shows the marker more times than the injected spec did AND is idle
#     (the spec echoes the marker the moment it lands, so count alone is not
#     enough; same rule as unit-loop.sh wait_worker). For a driver, never main:
#     main waits on the Orca inbox. A wait that sees the marker end a finished
#     turn keeps it in the record for collect.
# seat.sh run <role> <unit> <spec-file> [--marker <text>] [launch options] -- launch, wait on the marker (default VERDICT: GO; any
#     VERDICT line ends the wait too), collect, and print one line: seat=<role> unit=<unit> <verdict> report=<path>.
#     Exit 0 on GO, 1 on NO-GO, 3 with no verdict, 4 when the verdict is read but its task would not settle (the pane
#     stays open; rerun collect), the launch's own code when it is refused. Never a Builder. In
#     main's own foreground it restarts itself detached and prints its pid and log. Each outcome is one wake for
#     main: collect's verdict wake, or this script's own line when there is no verdict.
#
# Roles: any `roles.<name>.cmd` in config/routing.json. Main still writes the spec
# (the judgment); this script is the plumbing that cost six to ten main turns
# per seat by hand (ruling 2026-09-12, token cuts). Not a review-loop step:
# unit-loop.sh owns those.
set -euo pipefail
usage() { cat <<'EOF'
usage: seat.sh launch <role> <unit> <spec-file>   (COMMANDECK_SEAT_FORCE=1 reruns a spec that already finished)
       seat.sh launch builder <unit> <spec-file> [--model <alias>] [--effort medium|high] [--no-advisor]   (one launch only; builder-launch.sh passes them)
       seat.sh launch plan-<seat> <unit> <spec-file> [--model <alias>] [--effort <level>]   (the plan seat's model and effort the owner picked; it runs in <unit>, made on its first launch, or a marked <unit>-plan from before 0.18.0)
       seat.sh collect <role> <unit> [--report <path>] [--marker <text>] [--on-go <cmd>] [--on-nogo <cmd>]
       seat.sh wait    <role> <unit> --marker <text> [--timeout-s <n>]
       seat.sh status  <role> <unit>   (a launch's phase: launching, dispatched or failed; its pane: live, gone or unknown)
       seat.sh run     <role> <unit> <spec-file> [--marker <text>] [launch options]   (launch, wait, collect; one line back; not for a Builder)
       seat.sh effort  <role> <unit> <handle> <level>
Open one routing.json seat in the unit's worktree, collect its verdict, or wait for its marker.
effort sends /effort <level> to the pane only while it is an idle Claude pane, and
never below routing's effort-stages.reviewer-floor to a read-only role.
  --report <path>   collect: write the findings here when the pane could not (default: the scratch folder's reports/)
  --marker <text>   collect: a marker line that stands in for VERDICT (collect falls back to the marker of the last wait); wait: the line to wait for
  --on-go <cmd>     collect: run this from the repo root on VERDICT: GO
  --on-nogo <cmd>   collect: run this from the repo root on VERDICT: NO-GO
  --timeout-s <n>   wait: give up after n seconds (default 5400)
  COMMANDECK_SEAT_REPO=<repo>   any command: the unit is a worktree of another Orca repo (other-repo)
example: scripts/seat.sh collect certifier my-unit --report /tmp/commandeck/my-unit-r1.md
EOF
}
case "${1:-}" in --help|-h) usage; exit 0 ;; launch|collect|wait|effort|status|run) ;; *) usage >&2; exit 2 ;; esac
[ $# -ge 3 ] || { usage >&2; exit 2; }
CMDNAME=$1; shift
ROLE=$1; UNIT=$2; shift 2
ROOT=$(git rev-parse --show-toplevel)
# COMMANDECK_SEAT_REPO names another Orca repo (other-repo) by name, not
# path, so it cannot point a seat outside the workspaces directory.
SEAT_REPO=${COMMANDECK_SEAT_REPO:-}
[[ -z $SEAT_REPO || $SEAT_REPO =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "COMMANDECK_SEAT_REPO must be a repo name: $SEAT_REPO" >&2; exit 2; }
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
WS=$PP_WORKSPACES
[ -z "$SEAT_REPO" ] || [ -n "$PP_WORKSPACES_GIVEN" ] || WS=$HOME/orca/workspaces/$SEAT_REPO
SCRATCH=$PP_SCRATCH
# Another repo's unit can carry this repo's unit name; its record must not be
# this one's. "@" keeps the two names apart because no unit name may hold it:
# with "." this repo's unit "ops.foo" and repo "ops" unit "foo" shared a record.
case $UNIT in *@*) echo "a unit name cannot hold @: $UNIT" >&2; exit 2 ;; esac
REC=$SCRATCH/seat-${SEAT_REPO:+$SEAT_REPO@}$UNIT-$ROLE.txt
# A unit is planned and built in one worktree, <unit>: a plan seat's first launch cuts it from local main (below) and
# marks it, and the Builder's launch adopts it (plan-worktree-close.sh --adopt). A launched seat is read in the
# worktree its record names (worktree=): <unit>-plan for a unit planned before 0.18.0, and <unit> when it names none.
# <unit> is also the Builder's worktree: a plan seat reuses one only when its own first launch made it.
PLAN_OF=commandeck-plan-of
if [ "$CMDNAME" = launch ]; then WTN=$UNIT
  # A plan seat of a unit planned before 0.18.0 goes on in its marked <unit>-plan: a <unit> cut from main lacks the
  # plan not yet committed there.
  [[ $ROLE != plan-* || -d $WS/$UNIT ]] || [ "$(cat "$(git -C "$WS/$UNIT-plan" rev-parse --absolute-git-dir 2>/dev/null)/$PLAN_OF" 2>/dev/null)" != "$UNIT" ] || WTN=$UNIT-plan
else WTN=$(grep '^worktree=' "$REC" 2>/dev/null | tail -1 | cut -d= -f2- || true); WTN=${WTN:-$UNIT}; fi
WT=$WS/$WTN
# Issue 256: the plan a plan seat reads or leaves, with its hash; builder-launch.sh --from-plan installs only that one.
plan_lines() { local p=$WT/.claude/plans/$UNIT.md; [ ! -f "$p" ] || printf 'plan=%s\nplanhash=%s\n' "$p" "$(sha256sum < "$p" | cut -d' ' -f1)"; }
# Issue 320: a plan author's own completion message or fresh plan commit is its finish too (pp_seat_done); a judge's is not.
# reported [marker] -- it stands in for PLAN-DONE only (no marker is PLAN-DONE): never for a verdict or another marker.
reported() { [[ $ROLE == plan-author* ]] && [ "${1:-PLAN-DONE}" = PLAN-DONE ] && pp_seat_done "$REC"; }
# The Panel's planners launch in parallel: the check here and the make and mark below are one step under this lock,
# or the second saw <unit> made and not yet marked, and refused it (Sol r4). Released once the worktree is marked.
if [[ $CMDNAME == launch && $ROLE == plan-* ]]; then
  mkdir -p "$SCRATCH" && exec {PLAN_LOCK_FD}>>"$SCRATCH/${SEAT_REPO:+$SEAT_REPO@}$UNIT-plan-worktree.lock" && flock -w 600 "$PLAN_LOCK_FD" \
    || { echo "cannot lock $SCRATCH/$UNIT-plan-worktree.lock; nothing was opened" >&2; exit 1; }
  if [ -d "$WT" ] && [ "$(cat "$(git -C "$WT" rev-parse --absolute-git-dir 2>/dev/null)/$PLAN_OF" 2>/dev/null)" != "$UNIT" ]; then
    echo "REFUSED: $WT is not $UNIT's planning worktree (no plan seat of $UNIT made it; a Builder unit of that name may own it). Nothing was opened." >&2
    exit 2
  fi
fi
# read-verdict.sh ties a Codex pane's session log by worktree and launch epoch,
# so two seats in one worktree would transcribe each other's review without it.
LAUNCHED=$(grep '^launched=' "$REC" 2>/dev/null | cut -d= -f2 || true)
# A role routed to its own Codex home (routing's codexHome) logs there, in no home the session readers search by
# default: every read below (read-verdict.sh, seat-event.sh) looks there too, by the command the record launched.
seat_codex_home() {
  local h; h=$(sed -nE 's/^cmd=(.*[ ;])?CODEX_HOME=([^ ;]+).*/\2/p' "$REC" 2>/dev/null | tail -1 || true)
  export COMMANDECK_SEAT_CODEX_HOME=${h/#\~/$HOME}
}
seat_codex_home
[ -d "$WT" ] || [[ $CMDNAME =~ ^(launch|run)$ && $ROLE == plan-* && -z $SEAT_REPO ]] || { echo "no worktree at $WT" >&2; exit 2; }
# The seat's agent CLI, so the session reader looks in one provider's logs. A seat runs as its own role, on the
# agent its /plugin config key names (issue 312): two judges on Claude stay two seats, each with its own record.
seat_agent() {
  pp_route "$ROLE" 2>/dev/null && printf '%s\n' "$RT_AGENT" || true
}
# The role's pane cannot write files: a codex read-only sandbox or a Claude seat without Write.
seat_readonly() {
  pp_route "$ROLE" && [ "$RT_READONLY" = 1 ]
}
# Bounded, so a blocked log read cannot freeze a wait or a launch.
worker_state_kv() {
  timeout --kill-after=2 20 bash "$PP_SCRIPTS/read-verdict.sh" --state --worktree "$WT" --agent "${AGENT:-}" --marker "${MARKER:-}" "$@" 2>/dev/null || true
}
kv() { printf '%s\n' "$ST" | sed -n "s/^$1=//p" | head -1; }
rec() { sed -n "s/^$1=//p" "$REC" 2>/dev/null | tail -1; }
# pane_state -- live or gone: whether the record's handle is in Orca's terminal list; unknown when the record has no handle
# or the list cannot be read (#382: main sees a Builder whose pane is gone and relaunches it over the old record).
pane_state() {
  local h; h=$(rec handle); [ -n "$h" ] || { echo unknown; return; }
  timeout --kill-after=2 8 orca-ide terminal list --json 2>/dev/null | jq -er --arg h "$h" \
    '((.result // []) | if type == "array" then . else (.terminals // []) end) | if any(.[]; .handle == $h) then "live" else "gone" end' 2>/dev/null \
    || echo unknown
}
seat_status() { printf 'phase=%s handle=%s task=%s pane=%s last: %s\n' "$(rec phase)" "$(rec handle)" "$(rec task)" "$(pane_state)" "$(grep . "$REC.log" 2>/dev/null | tail -1)"; }
# settled -- wait out a launch's background part; fails when it ended phase=failed.
settled() { local p; p=$(rec pid); while [ -n "$p" ] && kill -0 "$p" 2>/dev/null; do sleep 1; done; [ "$(rec phase)" != failed ]; }
# A record with no session= (a Codex seat, or a Claude pid lookup that failed) takes the log the reader found, so
# the seat's spend is its own (dashboard_limit.py seat_costs), not "Not tied to a seat". A Claude log binds as
# its session id, the form every reader of session= builds <projects>/<id>.jsonl from.
bind_session() {
  local s; s=$(kv session); [ "$(kv provider)" != claude ] || { s=${s##*/}; s=${s%.jsonl}; }
  grep -q '^session=' "$REC" 2>/dev/null || [ -z "$s" ] || echo "session=$s" >> "$REC"
}
# seat_delivered <receipt> <log> <size> -- the receipt (line 1 the log, line 2 its size) names this log at this size: main
# already has this finish. No receipt, no log or any difference is no.
seat_delivered() {
  [ -n "${2:-}" ] && [ -n "${3:-}" ] && [ "$(sed -n 1p "$1" 2>/dev/null)" = "$2" ] && [ "$(sed -n 2p "$1" 2>/dev/null)" = "$3" ]
}
# A marker inside a fence is a quoted sample, never the pane's own (Sol r4): every fenced line, its delimiters too,
# reads as blank, by the fence rule paths.sh gives every report reader.
# A screen is a viewport: when the plain reading ends inside a fence and the first delimiter is bare, as a closing
# line is, the screen may have opened inside one. That text is also a bare opening fence still streaming, so it
# fails closed (Sol r5): a line counts only when the reading as opening inside a fence also puts it outside one.
# Ceiling: a cropped screen whose fences then pair up reads plain, as in read-verdict.sh.
unfenced() {
  awk "$PP_AWK_FENCE"'
    { raw[NR] = $0; out[NR] = (fence($0) || flen) ? "" : $0 }
    END {
      if (flen) for (i = 1; i <= NR; i++) if (raw[i] ~ /^[[:space:]]*(```+|~~~+)/) {
        if (raw[i] !~ /^[[:space:]]*(```+|~~~+)[[:space:]]*$/) break
        flen = 0; for (k = i + 1; k <= NR; k++) if (fence(raw[k]) || flen) out[k] = ""
        for (k = 1; k <= i; k++) out[k] = ""
        break
      }
      for (i = 1; i <= NR; i++) print out[i]
    }'
}

case "$CMDNAME" in
run)
  # Issue 257: launch, wait and collect were three calls of main's per seat.
  [ "$ROLE" != builder ] || { echo "REFUSED: seat.sh run does not run a Builder: builder-launch.sh launches it, and its passes are the pass script's" >&2; exit 2; }
  SPEC=${1:?spec file}; shift; MARKER='VERDICT: GO'
  [ "${1:-}" != --marker ] || { MARKER=${2:?marker}; shift 2; }
  SPEC=$(realpath "$SPEC") || exit 2   # what is left is the launch's own options (a plan seat's --model, --effort)
  # Main never blocks on a seat: in its own foreground the run goes on detached. Plain nohup, not pp_detach,
  # whose exit note would be a second wake for the outcome collect already sends.
  if pp_main_foreground; then
    LOG=$SCRATCH/run-${SEAT_REPO:+$SEAT_REPO@}$UNIT-$ROLE.log; mkdir -p "$SCRATCH"
    # A seat run started by main survives main's pane closing (host issue 3162): its own session, so a kill of the
    # pane's process group does not reach it. macOS has no setsid; perl's POSIX::setsid detaches the same way
    # (context-clear-stop.sh does the same).
    if command -v setsid >/dev/null 2>&1; then DETACH=(setsid); else DETACH=(perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec $ARGV[0]: $!\n"'); fi
    COMMANDECK_FOREGROUND=1 nohup "${DETACH[@]}" bash "$0" run "$ROLE" "$UNIT" "$SPEC" --marker "$MARKER" "$@" > "$LOG" 2>&1 < /dev/null &
    echo "seat.sh run $ROLE $UNIT: running detached, pid $!; log $LOG. Its verdict comes to main as a wake."; exit 0
  fi
  # No verdict sends nothing from collect, so this one line is that outcome's wake. A question, as collect's own:
  # orca-wait.sh drops a status sent from main's handle, which a run started by main sends from.
  none() { bash "$PP_SCRIPTS/to-main.sh" question "seat $ROLE $UNIT: $1" "$2" >/dev/null 2>&1 || true; }
  # stdout carries the one result line; the launch's and wait's progress go to stderr.
  rc=0; bash "$0" launch "$ROLE" "$UNIT" "$SPEC" "$@" >&2 || rc=$?
  [ "$rc" = 0 ] || { none "launch refused (exit $rc)" "seat.sh run $ROLE $UNIT $SPEC"; exit "$rc"; }
  settled || { none "no verdict: the launch failed" "$(seat_status)"; echo "seat=$ROLE unit=$UNIT no verdict report=none"; exit 3; }
  bash "$0" wait "$ROLE" "$UNIT" --marker "$MARKER" >&2 || true   # a pane gone or silent: collect then finds no verdict
  rc=0; bash "$0" collect "$ROLE" "$UNIT" >&2 || rc=$?
  V=$(sed -n 's/^verdict=//p' "$REC" | tail -1); RP=$(sed -n 's/^report=//p' "$REC" | tail -1)
  # Collect read a verdict and woke main with it, but the task would not settle: not "no verdict", so no second wake.
  [ "$rc" != 4 ] || { echo "seat=$ROLE unit=$UNIT verdict read, task not settled; pane kept open; rerun: bash $PP_SCRIPTS_Q/seat.sh collect $ROLE $UNIT report=${RP:-none}"; exit 4; }
  if [ "$rc" != 0 ] || [ -z "$V" ]; then
    none "no verdict (exit 3)" "$(seat_status)"; echo "seat=$ROLE unit=$UNIT no verdict report=${RP:-none}"; exit 3
  fi
  echo "seat=$ROLE unit=$UNIT $V report=${RP:-none}"
  case $V in "VERDICT: GO"*|"$MARKER") exit 0 ;; *) exit 1 ;; esac
  ;;
status)
  [ -f "$REC" ] || { echo "no seat record at $REC" >&2; exit 2; }
  seat_status
  ;;
effort)
  # The one /effort send. Sent mid-turn, /effort is queued as the
  # pane's next user message, so only an idle (Orca state done) Claude pane
  # gets it; Codex seats keep their launch effort.
  H=${1:?handle}; LEVEL=${2:?level}
  rank() { case "$1" in low) echo 1 ;; medium) echo 2 ;; high) echo 3 ;; xhigh) echo 4 ;; max) echo 5 ;; *) echo 0 ;; esac; }
  [ "$(rank "$LEVEL")" -gt 0 ] || { echo "unknown effort level: $LEVEL" >&2; exit 2; }
  FLOOR=$(jq -r '."effort-stages"."reviewer-floor" // "high"' "$(pp_routing)")
  if seat_readonly && [ "$(rank "$LEVEL")" -lt "$(rank "$FLOOR")" ]; then
    echo "effort: $ROLE is a reviewer seat; /effort $LEVEL is below its floor $FLOOR, not sent" >&2; exit 1
  fi
  PANE=$(jq -rn --argjson ps "$(timeout --kill-after=2 8 orca-ide worktree ps --json 2>/dev/null || echo '{}')" \
    --argjson ts "$(timeout --kill-after=2 8 orca-ide terminal list --json 2>/dev/null || echo '{}')" --arg h "$H" '
    (($ts.result // []) | if type == "array" then . else (.terminals // []) end)[]
    | select(.handle == $h) | "\(.tabId):\(.leafId)" as $k
    | first($ps.result.worktrees[]?.agents[]? | select(.paneKey == $k)) | "\(.agentType) \(.state)"' 2>/dev/null || true)
  [ "$PANE" = "claude done" ] || { echo "effort: pane $H is not an idle Claude pane (${PANE:-unknown}); /effort $LEVEL not sent" >&2; exit 1; }
  orca-ide terminal send --terminal "$H" --text "/effort $LEVEL" --enter --wait-submit 10 --json >/dev/null \
    || { echo "effort: send to $H failed" >&2; exit 1; }
  echo "effort: $ROLE $UNIT pane $H set to $LEVEL"
  ;;
launch)
  SPEC=${1:?spec file}
  [ -s "$SPEC" ] || { echo "empty spec: $SPEC" >&2; exit 2; }
  # Issue 312: a role the owner turned off in /plugin config opens no pane and writes no record, by hand too.
  rc=0; WHY=$(pp_role_enabled "$ROLE" 2>&1) || rc=$?
  [ "$rc" = 0 ] || { echo "REFUSED: ${WHY:-$ROLE is off}; nothing was opened" >&2; exit 2; }
  # A launch of this seat still running in the background is this seat: a retry opens no second pane.
  if [ "$(rec phase)" = launching ] && kill -0 "$(rec pid)" 2>/dev/null; then
    echo "REFUSED: $ROLE for $UNIT is still launching: $(seat_status)" >&2; exit 2
  fi
  # One Builder launch may name its model, raise its effort or drop its advisor (builder-launch.sh); a plan seat
  # takes the model and effort the owner picked for it. No other seat takes any. The model and effort are checked
  # here too: this launch is also run by hand.
  LMODEL='' LEFFORT='' LADVISOR='' LOPTS=("${@:2}")
  if [ "${#LOPTS[@]}" -gt 0 ]; then
    [[ $ROLE == builder || $ROLE == plan-* ]] || { echo "seat.sh: only the builder and plan seats take a launch option (${LOPTS[*]}); nothing was done" >&2; exit 2; }
    i=0
    while [ "$i" -lt "${#LOPTS[@]}" ]; do
      case ${LOPTS[i]} in
        --model) i=$((i+1)); LMODEL=${LOPTS[i]:-}; [ -n "$LMODEL" ] || { usage >&2; exit 2; } ;;
        --effort) i=$((i+1)); LEFFORT=${LOPTS[i]:-} ;;
        --no-advisor) LADVISOR=none ;;
        *) usage >&2; exit 2 ;;
      esac
      i=$((i+1))
    done
    if [ "$ROLE" = builder ]; then
      [ -z "$LMODEL" ] || pp_builder_model_ok "$LMODEL" || exit 2
      [ -z "$LEFFORT" ] || pp_builder_effort_ok "$LEFFORT" "$(pp_route_json builder "" "$LMODEL" | jq -r '.effort // "none"')" || exit 2
    else
      # A plan seat's effort is any level, checked with its role below; its model, one of the agent it runs on.
      [ -z "$LMODEL" ] || pp_seat_model_ok "$ROLE" "$LMODEL" || exit 2
    fi
  fi
  # A plan seat on Codex where no codex is installed is refused, naming the keys that move it (pp_plan_seat). Its
  # check resolves the launch's own model: a named one needs no default to resolve.
  [[ $ROLE != plan-* ]] || pp_plan_seat "$ROLE" "$LMODEL" >/dev/null || exit 2
  pp_route "$ROLE" "$LEFFORT" "$LMODEL" "$LADVISOR" || { echo "no usable roles.$ROLE in routing.json" >&2; exit 2; }
  [ -n "$RT_CMD" ] || { echo "roles.$ROLE in routing.json is not a pane seat" >&2; exit 2; }
  LAUNCH_AGENT=$RT_AGENT  # the launch's own route: a later pp_route without its --model may resolve to none
  # Issue 316: a seat that cannot read GitHub is not launched. The read is the seat's own, against its target checkout;
  # a plan seat's first launch has no worktree yet, so it reads local main, which that worktree is cut from.
  GH_NEW=; GH_DIR=$WT; [ -d "$WT" ] || { GH_NEW=--new; GH_DIR=$PP_MAIN; }
  WHY=$(pp_gh_read ${GH_NEW:+"$GH_NEW"} "$ROLE" "$GH_DIR" "$LEFFORT" "$LMODEL") \
    || { echo "BLOCKED: $ROLE cannot read GitHub from its sandbox: $WHY" >&2; exit 2; }
  # The pane's shell knows its seat before the agent starts: the launch record is written only after the pane opens.
  CMD="export COMMANDECK_SEAT=$ROLE; $RT_CMD"
  # A finished spec does not run twice: the same plan-reviser job ran
  # three times in 22 minutes. collect writes verdict= beside this hash.
  SPEC_HASH=$(sha256sum "$SPEC" | cut -d' ' -f1)
  PREV_VERDICT=$(sed -n 's/^verdict=//p' "$REC" 2>/dev/null | tail -1 || true)
  if [ -n "$PREV_VERDICT" ] && [ "$(sed -n 's/^spechash=//p' "$REC" | tail -1)" = "$SPEC_HASH" ] \
     && [ "${COMMANDECK_SEAT_FORCE:-0}" != 1 ]; then
    echo "REFUSED: $ROLE already finished this exact spec for $UNIT ($PREV_VERDICT; $REC)." >&2
    echo "Change the spec, or rerun it on purpose with COMMANDECK_SEAT_FORCE=1." >&2
    exit 2
  fi
  # Delegate by contract (ruling 2026-09-13, orchestrator invariant 3): the
  # allowed changes a spec asks for must match the sandbox the seat runs in.
  # The certifier is `--sandbox read-only`; its spec on 2026-09-13 told it to
  # write its report to a file, it could not, and main hand-captured the pane.
  # `collect --report <path>` is the supported way to get a file out of a
  # read-only seat: main transcribes the pane after the verdict.
  if [ "$RT_READONLY" = 1 ]; then
    GREP_RC=0
    ASKS_WRITE=$(grep -inE '(^|[^a-z_./-])(write|save|append|create)s?[[:space:]][^;]{0,60}\.(md|json|jsonl|txt)([^a-z]|$)' "$SPEC") || GREP_RC=$?
    [ "$GREP_RC" -gt 1 ] || { ASKS_WRITE=$(grep -viE 'do not|does not|never|cannot|can not|read-only, so|no other' <<<"$ASKS_WRITE" | head -3) || GREP_RC=$?; }
    # Fail closed: grep exits 1 for no match and 2 or more when it could not run the check.
    [ "$GREP_RC" -le 1 ] || { printf 'BLOCKED: %s is a read-only seat and its write check could not run (grep exit %s).\n' "$ROLE" "$GREP_RC" >&2; exit 2; }
    [ -z "$ASKS_WRITE" ] || {
      printf 'BLOCKED: %s is a read-only seat and its spec asks it to write a file.\n' "$ROLE" >&2
      printf '%s\n' "$ASKS_WRITE" | cut -c1-160 >&2
      echo "Tell it to print the report in the chat, and pass 'collect --report <path>' to transcribe the pane." >&2
      exit 2
    }
  fi
  # Issue 384: a judge never reads a plan the launcher would refuse. Every launch of a judge that certifies the plan (the
  # condition of the plan copy below), a re-judge included, runs the launcher's own checks before any worktree, pane,
  # task or record exists. Its batch is the planning worktree's, else main's briefs folder's, else none.
  if [[ $ROLE == plan-judge-* ]] && grep -qxF "Plan: .claude/plans/$UNIT.md" "$SPEC" && [ -f "$WT/.claude/plans/$UNIT.md" ]; then
    PCB=
    for b in ${COMMANDECK_BATCH:+"$COMMANDECK_BATCH"} "$WT/.claude/briefs/$UNIT-batch.md" "$PP_MAIN/.claude/briefs/$UNIT-batch.md"; do [ ! -e "$b" ] || { PCB=$b; break; }; done
    bash "$PP_SCRIPTS/plan-check.sh" "$WT/.claude/plans/$UNIT.md" "$PCB" >/dev/null || exit 2
  fi
  # A Claude pane in a worktree takes the MAIN repo's ~/.claude.json project
  # entry. serena disabled there left a worker with no
  # symbol tools and nothing said so (2026-09-18).
  if [ "$(seat_agent)" = claude ]; then
    MAIN_REPO=$(dirname "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)")
    OFF=$(jq -r --arg p "$MAIN_REPO" '.projects[$p].disabledMcpServers // [] | .[] | select(. == "serena")' \
      "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" 2>/dev/null | tr '\n' ' ' || true)
    [ -z "$OFF" ] || {
      echo "BLOCKED: ${OFF% } disabled in ${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json projects[\"$MAIN_REPO\"].disabledMcpServers; a Claude seat would run without it." >&2
      echo "Fix: re-enable it in /mcp from $MAIN_REPO, or remove it from that disabledMcpServers list, then launch again." >&2
      exit 2
    }
  fi
  # A plan seat's first launch cuts its planning worktree from local main, as builder-launch.sh cuts a Builder's.
  # Its git dir is marked as this unit's, the mark the reuse check above reads.
  if [ ! -d "$WT" ]; then
    # A new unit opens only on an order that names it (issue 234), as builder-launch.sh holds a batch to.
    sed -n 's/^Launch:[[:space:]]*//p' "$SPEC" | sed 's/[[:space:]]*$//' | grep -qxF "new unit $UNIT" \
      || { echo "REFUSED: $SPEC has no 'Launch: new unit $UNIT' line, and this launch would open the unit $UNIT: copy the batch's Launch and Order lines into the spec. Nothing was opened; the Order line must quote the owner's yes naming this unit or its issues." >&2; exit 2; }
    pp_worktree_new "$WTN" && echo "$UNIT" > "$(git -C "$WT" rev-parse --absolute-git-dir)/$PLAN_OF" || exit 1
  fi
  [ -z "${PLAN_LOCK_FD:-}" ] || exec {PLAN_LOCK_FD}>&-
  ORCA_TERMINAL_HANDLE=$(bash "$PP_SCRIPTS/run-bound.sh") || exit 2; export ORCA_TERMINAL_HANDLE
  # Same reason as dispatch-unit.sh: a seat in a worktree with no node_modules
  # symlink gets a silently toothless eslint, ts-suggestions and parser-backed
  # hooks. Idempotent, so a worktree already set up pays nothing. Another
  # repo's worktree must not get this repo's node_modules.
  [ -n "$SEAT_REPO" ] || bash "$PP_SCRIPTS/worktree-setup.sh" "$WT" >/dev/null
  # Stamp the launch BEFORE the pane exists. read-verdict.sh skips any session
  # log whose first timestamp predates this number, and the agent writes that
  # first line seconds before `terminal create` returns -- a record stamped
  # afterwards rejected the round's own log and sent every Claude seat down the
  # partial rendered-screen path (three drivers stalled on 2026-09-13).
  # A Builder opened here by hand waits out a builder-launch.sh call for the same unit, which writes its records.
  [ "$ROLE" != builder ] || pp_builder_lock "$UNIT" || exit 1
  . "$PP_SCRIPTS/codex-helpers.sh"
  # Issue 256: under the owner's Builder cap (maxBuilders in /config), one launch at a time counts the live Builder
  # panes of other units and opens its own before the next counts. The unit lock above is always taken first, so two
  # launches never wait on each other. With no cap nothing is locked or counted. A pane is a Builder by the title it
  # was opened under (the registry), else by the title Orca lists; live as live_pane_with_title reads it: an agent
  # in it, or opened in the last 120 s.
  CAP=; [ "$ROLE" != builder ] || CAP=$(pp_option maxBuilders)
  if [ -n "$CAP" ]; then
    [[ $CAP =~ ^[1-9][0-9]*$ ]] || { echo "REFUSED: maxBuilders is \"$CAP\", not a whole number of 1 or more; change it in /config. The Builder was not launched." >&2; exit 2; }
    exec {ADMIT_FD}>>"$PP_SCRATCH/builder-admission.lock" && flock -w 600 "$ADMIT_FD" \
      || { echo "cannot lock $PP_SCRATCH/builder-admission.lock; the Builder was not launched" >&2; exit 1; }
    OWN=$(pane_title builder "$UNIT") REG=
    [ ! -e "$PANE_TITLES" ] || REG=$(cat -- "$PANE_TITLES") \
      || { echo "REFUSED: the pane title registry $PANE_TITLES could not be read, so the Builders running cannot be counted against the maxBuilders cap in /config; the Builder was not launched" >&2; exit 1; }
    LIVE=$(timeout --kill-after=2 10 orca-ide terminal list --json 2>/dev/null | jq -er --arg reg "$REG" --arg o "$OWN" --argjson now "$(date +%s)" '
      (reduce ($reg | split("\n")[] | split("\t") | select(length >= 4)) as $r ({}; .[$r[2]] = {title: $r[1], at: ($r[3] | tonumber? // 0)})) as $m
      | [.result | if type == "array" then . else .terminals end | .[]
        | select(.connected != false and .orphaned != true) | . as $t | ($m[$t.handle] // {}) as $r
        | select(($r.title // $t.title // "") | startswith("Builder — ") and . != $o)
        | select($t.agentIdentity != null or $now - ($r.at // 0) < 120) | .handle] | unique | join(" ")') \
      || { echo "REFUSED: the pane list could not be read, so the Builders running cannot be counted against the maxBuilders cap in /config; the Builder was not launched" >&2; exit 1; }
    N=$(wc -w <<<"$LIVE" | tr -d ' ')
    [ "$N" -lt "$CAP" ] || { echo "REFUSED: $N Builders are running ($LIVE), the maxBuilders cap in /config; close one or raise the cap" >&2; exit 2; }
  fi
  LAUNCH_EPOCH=$(date +%s)
  REUSED=0
  # Issue 315: trust the Codex home's hooks again right before the pane starts, so a hook a tool update changed
  # since the last launch does not open the pane on the review menu.
  [ "$LAUNCH_AGENT" != codex ] || pp_codex_retrust "$CMD"
  H=$(open_pane "path:$WT" "$(pane_title "$ROLE" "$UNIT")" "$CMD") || REUSED=$?
  # The pane is listed and recorded now; the launch's background part must not hold the next launch's count.
  [ -z "${ADMIT_FD:-}" ] || exec {ADMIT_FD}>&-
  [ -n "$H" ] || { echo "terminal create returned no handle" >&2; exit 1; }
  # A reused pane this record names holds its task: prompt nothing, and refuse
  # a changed spec rather than drop it.
  if [ "$REUSED" = 3 ]; then
    grep -qx "handle=$H" "$REC" 2>/dev/null \
      || { echo "REFUSED: live $ROLE seat $H for $UNIT is not in $REC; read it, then close it or let its driver finish." >&2; exit 2; }
    grep -qx "spechash=$SPEC_HASH" "$REC" \
      || { echo "REFUSED: live $ROLE seat $H for $UNIT is on another spec ($REC); collect or close it first." >&2; exit 2; }
    # The pane keeps the model, effort and advisor it opened with: a launch that resolves to another
    # command, by its options or by a changed project setting, is not this seat.
    [ "$(sed -n 's/^cmd=//p' "$REC" | tail -1)" = "$CMD" ] \
      || { echo "REFUSED: live $ROLE seat $H for $UNIT was opened with other launch settings (model, effort or advisor; $REC); close it, then launch again." >&2; exit 2; }
    echo "seat=$ROLE unit=$UNIT handle=$H task=$(sed -n 's/^task=//p' "$REC" | tail -1) state=reused record=$REC"
    exit 0
  fi
  # Main's ruling 2: a judge certifies the unit's plan only when a whole line of its spec sends it there ("do not
  # judge .claude/plans/u.md" or u.md.bak binds nothing), and it reads a read-only copy taken now, through a copy of
  # its spec whose Plan: line names that copy: an edit to the live plan while it reads is never what its GO certifies.
  PTR=$(realpath "$SPEC") PLAN_REC=
  if [[ $ROLE == plan-judge-* ]] && grep -qxF "Plan: .claude/plans/$UNIT.md" "$SPEC" && [ -f "$WT/.claude/plans/$UNIT.md" ]; then
    SNAP=$SCRATCH/seat-$UNIT-$ROLE-$LAUNCH_EPOCH-$$-plan.md PTR=$SCRATCH/seat-$UNIT-$ROLE-$LAUNCH_EPOCH-$$-spec.md
    { cp "$WT/.claude/plans/$UNIT.md" "$SNAP" && chmod 444 "$SNAP" \
      && sed "s#^Plan: \.claude/plans/$UNIT\.md\$#Plan: $SNAP (a read-only copy of .claude/plans/$UNIT.md taken at launch: judge this file, never the live one)#" "$SPEC" > "$PTR"; } \
      || { echo "cannot copy the plan for $ROLE $UNIT to $SCRATCH; closing pane $H" >&2; pp_pane_close "$H" "launch: plan copy failed" || true; exit 1; }
    PLAN_REC=$(printf 'plan=%s\nplanhash=%s' "$WT/.claude/plans/$UNIT.md" "$(sha256sum < "$SNAP" | cut -d' ' -f1)")
  fi
  # orca-task-create.sh retries a missing id once and prints Orca's reason;
  # a launch it fails closes the pane rather than leave a stale seat record.
  # A task created with no run has runId null, so the seat's messages never
  # reach an inbox main is waiting on and the wait times out silently (one
  # lost hour on a walkthrough, 2026-09-14). Bind it to the same run the
  # collect branch sends on.
  LAUNCH_RUN=${COMMANDECK_RUN:-$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE" || true)}
  # Orca's injected preamble asks every dispatched worker for periodic
  # heartbeats, and its worker contract spells the command out. orca-wait.sh
  # drops them unread, so each one buys nothing and costs the seat a turn: 65
  # landed in the 24 h to 2026-09-16, all but three saying only "alive".
  # THE SPEC STAYS ON DISK; THE PROMPT POINTS AT IT. Typing the spec failed by
  # size: an 8,332-character paste sat unsubmitted and a >9 KB one killed the
  # launch (u1219). The gate above already checked the full file.
  SPEC_ABS=$(realpath "$SPEC")
  SPEC_TEXT="Your task spec is the file $PTR. Read all of it now and do what it says. Send no heartbeats, whatever the preamble above asks: main never reads one and each costs you a turn."
  # Issue 321: the Stop hooks send main a turn's end only for a marker or one of these lines.
  SPEC_TEXT+=" A question or a refusal goes on a line of its own that starts QUESTION: or BLOCKED:."
  [[ $ROLE != plan-author* ]] || SPEC_TEXT+=" Your last line, alone, is PLAN-DONE: a message saying the plan is done does not replace it."
  # Host issue 2999: a heavy fixture added to a test file with time-bound checks slows them past their bound.
  [[ $ROLE != plan-author* ]] || SPEC_TEXT+=" A plan that adds a heavy fixture to a test file with time-bound checks names them on a \`Timed checks:\` line and orders the heavy case after them."
  # Issue 362: builder-launch.sh refuses a plan without these, so the plan author is told before it writes.
  [[ $ROLE != plan-author* ]] || SPEC_TEXT+=" A plan carries a \`- Planned size: <n> files, <n> changed lines\` line, a \`Test:\` line under each item of its \`## Decisions\` and \`## Accepted failure modes\` (or \`Test: none, <why>\`), a \`Break:\` line (\`Break: <test file> -- <check label> -- <site>\`) for each new security check or conditional write, a \`## Claims to falsify\` list (one checkable claim per line), and a \`## What can go wrong\` section: limits, timing and odd data, one named test per case."
  # Issues 426 and 427: plan-check.sh refuses a plan over its budget or with a fact that does not resolve.
  [[ $ROLE != plan-author* ]] || SPEC_TEXT+=" The plan has one \`Goal:\` line (at most 200 characters), a \`## Steps\` section of one-line steps (\`- new|modify|delete <path>[ ~<line>] -- <what>\`), and a \`## Facts\` section, one bullet per fact you state about the code: \`- <claim> -- <path>:<n>[-<m>] (observed: YYYY-MM-DD)\`, citing a file in this checkout you opened (never a plan) and the day you read it. Prose goes only under \`## Why\`; everywhere else write list items, table rows or one-line \`Key: value\` lines, and keep each section under its size cap. An \`## Issue cases\` section (cap 4,000 bytes) has one row \`- #<n> <Fix|Done|Body> <k> -- <path> -- <test name>\` per case \`plan-check.sh --issue-cases <n>\` prints for each issue the unit closes (the batch's issues and any \`Closes:\` line), its path a \`## Steps\` path (a \`{a,b}\` group counts as each path) and its test named in \`## Acceptance test\`."
  # Issue 384: the judge launch runs plan-check.sh and refuses what it refuses, so the author runs it first.
  [[ $ROLE != plan-author* ]] || SPEC_TEXT+=" Before PLAN-DONE run \`plan-check.sh .claude/plans/<unit>.md <batch>\` and fix every REFUSED: line; name each mockup on its own \`Mockup: <path or URL>\` line and make sure the batch carries it."
  # Issue 359: the table's shape, the settled claims and the contracts a cut produces and consumes.
  [[ $ROLE != plan-author* ]] || SPEC_TEXT+=" The What can go wrong section is a table of case, input or starting state, expected result and test name, at most five rows (\`checked, none\` when empty), and each row's test is among the acceptance tests. Every claim you mark [likely] or [uncertain] is settled in the plan (the command and its output) or is a Builder check before the cut that depends on it, with the action for each outcome. Each cut lists what it Produces and Consumes, and every existing consumer of a contract it changes. A judge finding you accept goes into the plan, one \`## Plan change log\` line each, before the Builder starts."
  # Issue 360: scope is the owner's words. The plan carries them; each judge traces every requirement to them.
  [[ $ROLE != plan-author* ]] || SPEC_TEXT+=" The plan opens with an \`Owner's words:\` line copied word for word from the order (the batch's \`Order:\` line), and every requirement it plans traces to those words or to an addition the owner approved by name."
  # Issue 456: plan-check.sh refuses a Done line that names a component; the author is told the shape first.
  [[ $ROLE != plan-author* ]] || SPEC_TEXT+=" Under \`## Done\` write one \`- #<n> Done: <user action> -- <what the user sees>\` line per issue the unit closes: what a user does and what the user sees, never a component. Good: \`- #39 Done: a user retries an import from the dashboard after a lost response -- no duplicate import appears\`. Bad: \`- #39 Done: retry key handling (API)\`. Where the issue names only a component, write the user path with every hop, or name the missing hop as a stated limit."
  [[ $ROLE != plan-judge-* ]] || SPEC_TEXT+=" Check that every requirement in the plan traces to its \`Owner's words:\` line or to an addition the owner approved by name (the order's NOT-ordered section, with the owner's yes for it): an untraced requirement is a finding."
  [[ $ROLE != plan-judge-* ]] || SPEC_TEXT+=" plan-check.sh has passed this plan (seat.sh runs it before every judge launch), so report none of its checks: the sections, the size line, the \`Test:\` lines, the \`Mockup:\` lines, the budget and that each Facts citation resolves."
  # Host rule drift: the plan judge's reading.
  [[ $ROLE != plan-judge-* ]] || SPEC_TEXT+=" Read the plan as a Builder who cannot ask: list every place a wrong guess would change the code. Try to falsify each claim under Claims to falsify and each Facts line (read the cited lines). Name the established industry practice for the problem: a departure the plan does not justify is a finding. On a revised plan, recheck only what its Plan change log names; a revised plan is not judged again."
  [[ $ROLE != plan-judge-* ]] || SPEC_TEXT+=" A plan or batch line that describes existing placeholder UI (a disabled control, 'coming soon' copy) as context is a finding: an open problem until the plan removes it or names it on a \`Placeholder:\` line."
  # Issue 457: a stated limit can strand a fix, so the judge reads the limits for a fix nothing in production reaches.
  [[ $ROLE != plan-judge-* ]] || SPEC_TEXT+=" A stated limit that leaves a planned fix with no real caller in production (no client sends it, a gate blocks it, nothing routes to it) makes your verdict NO-GO unless the owner approved that limit by name."
  # Issue 413: a judge prints its inputs in one call from the frozen copy; with no copy it is never pointed at the live plan.
  [[ $ROLE != plan-judge-* || -z ${SNAP:-} ]] || SPEC_TEXT+=" Print your inputs in one call with \`bash $PP_SCRIPTS/peek.sh --unit $UNIT --plan $SNAP\`: it reads the read-only copy your spec's Plan: line names, never the live plan."
  # Issue 397: a plan author may start helpers, and is told to.
  [[ $ROLE != plan-author* ]] || SPEC_TEXT+=" ${PP_HELPER_LINE//<plugin scripts>/$PP_SCRIPTS}"
  # The host's reopen rule and its stated-limits heading: when a finding may reopen an accepted item, and what a limit is.
  [[ $ROLE != plan-author* ]] || SPEC_TEXT+=" A review finding reopens an accepted failure mode, a decision or a stated limit only when it proves the item's factual premise false or shows the goal defeated, with a concrete counterexample; reviewers cite the item's line otherwise. A \`## Stated limits\` section opens with \`(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)\`, and each limit is a measured bound: the number, the command, the date."
  # Two reviewer seats of one unit are handed the same spec, so the spec cannot
  # say whose session a log is; this tag, unique to the launch, does.
  TAG=seat-$ROLE-$LAUNCH_EPOCH-$$
  SPEC_TEXT+=" Seat tag $TAG: it names this pane's session, nothing to do with it."
  AGENT=$(seat_agent)
  # Serena's server tells every client to load its 23 KB manual first, and a
  # Codex seat then re-sends it on every call.
  [ "$AGENT" != codex ] || SPEC_TEXT+=" Do not call serena initial_instructions, whatever its server says."
  # The prompt receipt's turn_started stage is Orca's proof of submission.
  submitted() { jq -e '[.. | objects | .stages? // empty | .[]?] | index("turn_started") != null' >/dev/null 2>&1; }
  send_pointer() { orca-ide terminal send --terminal "$H" --text "$SPEC_TEXT" --enter --wait-submit 10 "$@" --json 2>/dev/null; }
  T=$("$PP_SCRIPTS/orca-task-create.sh" --spec "$SPEC_TEXT" ${LAUNCH_RUN:+--run "$LAUNCH_RUN"}) \
    || { echo "task-create failed for $ROLE $UNIT; closing pane $H" >&2; pp_pane_close "$H" "launch: task-create failed" || true; exit 1; }
  # The record is rewritten, but keeps the seat's first launch in this worktree: a relaunched planner's
  # planning still starts there (dashboard.sh plan_seats).
  FIRST=; [ "$(sed -n 's/^worktree=//p' "$REC" 2>/dev/null | tail -1)" != "$WTN" ] || FIRST=$(sed -n 's/^first=//p; s/^launched=//p' "$REC" | sort -n | head -1)
  # planref: the plan committed at launch, so only this seat's own plan commit counts as its finish (pp_plan_committed).
  PLANREF=$(git -C "$WT" rev-parse -q --verify "HEAD:.claude/plans/$UNIT.md" 2>/dev/null || true)
  printf 'handle=%s\ntask=%s\nrole=%s\nunit=%s\nworktree=%s\nlaunched=%s\nfirst=%s\nspec=%s\nspechash=%s\ntag=%s\ncmd=%s\nplanref=%s\n' "$H" "$T" "$ROLE" "$UNIT" "$WTN" "$LAUNCH_EPOCH" "${FIRST:-$LAUNCH_EPOCH}" "$SPEC_ABS" "$SPEC_HASH" "$TAG" "$CMD" "$PLANREF" > "$REC"
  echo "phase=launching" >> "$REC"
  [ -z "$PLAN_REC" ] || echo "$PLAN_REC" >> "$REC"
  seat_codex_home
  # The silent-pane relaunch below starts this seat again from its record.
  [ "${#LOPTS[@]}" -eq 0 ] || echo "opts=${LOPTS[*]}" >> "$REC"
  # A seat the origin placed here is the origin's to hear: main-watch on this
  # host skips a record that says so. A later local launch rewrites the record.
  [ -z "${COMMANDECK_ORIGIN_RUN:-}" ] || echo "origin=$COMMANDECK_ORIGIN_RUN" >> "$REC"
  # Issue 233: the launch returns once the pane, its task and its record exist. The waits below (tui-idle up to
  # 120 s, the dispatch retries up to 60 s) outlasted callers' timeouts, and a retry then opened a second pane.
  # This part runs in the background, its output in $REC.log; it ends the record phase=dispatched or phase=failed.
  launch_rest() {
    # Issue 315: a Codex pane left on the "hooks need review" menu (a hook trust could not cover) never takes the task.
    # Read at the end of the bounded tui-idle wait, and again when no turn started; the launch ends phase=failed.
    # screen_lines -- the pane's screen, one line each (a string tail as its lines); status 2 when Orca gives no screen
    # within 8 s.
    screen_lines() {
      local r
      r=$(timeout --kill-after=2 8 orca-ide terminal read --terminal "$H" --screen --json 2>/dev/null) \
        && jq -nr 'input.result.terminal.tail | if type == "array" then .[] elif type == "string" then . else error end' <<<"$r" 2>/dev/null \
        || return 2
    }
    fail_if_review_menu() {
      [ "$LAUNCH_AGENT" = codex ] || return 0
      local msg
      # No screen is not the menu: the first call follows a read that answer_update_prompt proved, the second a launch already failing.
      msg=$(pp_codex_blocked "$(pp_codex_home "$CMD")" "$(screen_lines)") && { printf '%s\n' "$msg" >&2; exit 1; }
      return 0
    }
    # Issue 314: a Codex pane left on Codex's "Update available" prompt never takes the task. Always Skip (key 2), never
    # Update now: in a pane that runs the installer and exits Codex with the task untaken; setup/update.sh update Codex
    # outside panes. Bounded: each Orca call ends in 8 s (the 15 s answer wait in 20 s), the answer is re-read 3 times.
    # Only a screen read without the prompt clears it: no screen, a refused Skip or the prompt still there ends the
    # launch phase=failed before the task is typed (its text could pick "1. Update now").
    # update_prompt_heading -- status 0 and the heading: the prompt is on screen; 1: a screen without it; 2: no screen.
    update_prompt_heading() {
      local s
      s=$(screen_lines) || return 2
      awk '/^[[:space:]]*Update available/ && /→/ { h = $0 } /Skip until next version/ { m = 1 } END { if (h != "" && m) { print h; exit 0 } exit 1 }' <<<"$s"
    }
    answer_update_prompt() {
      [ "$LAUNCH_AGENT" = codex ] || return 0
      local h s
      h=$(update_prompt_heading) && s=0 || s=$?
      [ "$s" != 1 ] || return 0
      [ "$s" = 0 ] || { echo "Codex pane $H: its screen could not be read (orca-ide terminal read), so its update prompt cannot be ruled out; the task was not sent" >&2; exit 1; }
      h=${h%"${h##*[![:space:]]}"}
      timeout --kill-after=2 8 orca-ide terminal send --terminal "$H" --text 2 --json 2>/dev/null | jq -e '.ok == true' >/dev/null 2>&1 \
        || { echo "Codex pane $H is on its update prompt and Skip could not be sent (orca-ide terminal send); the task was not sent. Answer it in the pane, then run: bash $PP_SCRIPTS/update.sh" >&2; exit 1; }
      timeout --kill-after=2 20 orca-ide terminal wait --terminal "$H" --for tui-idle --timeout-ms 15000 --json >/dev/null || true
      for _ in 1 2 3; do
        update_prompt_heading >/dev/null && s=0 || s=$?
        [ "$s" != 1 ] || { echo "codex update prompt: answered Skip (${h#*· }); Codex is updated outside panes: bash $PP_SCRIPTS/update.sh"; return 0; }
        sleep 1
      done
      if [ "$s" = 2 ]; then echo "Codex pane $H: its screen could not be read after answering Skip (orca-ide terminal read); the task was not sent" >&2
      else echo "Codex pane held by its update prompt after answering Skip; run: bash $PP_SCRIPTS/update.sh" >&2; fi
      exit 1
    }
    orca-ide terminal wait --terminal "$H" --for tui-idle --timeout-ms 120000 --json >/dev/null || true
    answer_update_prompt
    fail_if_review_menu
    # Issue 278: the agent retitles its pane as it starts, so the title given at create is lost; an older Orca has no such command.
    timeout --kill-after=2 8 orca-ide terminal set-pane-title --terminal "$H" --title "$(pane_title "$ROLE" "$UNIT")" >/dev/null 2>&1 || true
    # Orca detects the agent in a fresh pane seconds after tui-idle, and until then
    # refuses inject with "no recognized agent". Retrying that refusal is
    # fewer lines than polling the pane's agent state; --keep-task leaves the task
    # open for the next try. Any other refusal falls through at once.
    dispatch_when_detected() {
      local err
      for _ in $(seq 30); do
        err=$("$PP_SCRIPTS/dispatch-task.sh" "$T" "terminal:$H" --keep-task 2>&1) \
          && { [ -z "$err" ] || printf '%s\n' "$err" >&2; return 0; }
        case $err in *"no recognized agent"*) sleep 2 ;; *) break ;; esac
      done
      printf '%s\n' "$err" >&2; return 1
    }
    PROVEN=0 DIRECT=0
    if ! dispatch_when_detected; then
      # Load-bearing: a pane Orca still does not see as an agent after the retry
      # window, or one refusing for another reason, gets the pointer typed, and
      # collect (not a worker_done) is what closes that seat. Say it loudly.
      echo "NO-WAKE: task $T was typed into $H, not dispatched; Orca sends no worker_done for it" >&2
      DIRECT=1
      # No Orca preamble names the task in a typed pane: the id ties its session to the task (read-verdict.sh --task).
      SPEC_TEXT+=" Task id $T."
      # dispatch-task.sh's busy refusal lands here too; typing would bypass it.
      rc=0; pane_is_busy "$H" || rc=$?
      [ "$rc" = 1 ] || { echo "REFUSED: $H is mid-turn or its agent state cannot be read; the pointer was not typed" >&2; exit 1; }
      RECEIPT=$(send_pointer || true)
      printf '%s' "$RECEIPT" | jq -e '.ok' >/dev/null 2>&1 || { echo "send failed to $H" >&2; exit 1; }
      if printf '%s' "$RECEIPT" | submitted; then PROVEN=1
      else
        # Replaying the same request id returns the receipt; it never types again.
        REQ=$(printf '%s' "$RECEIPT" | jq -r '[.. | objects | .requestId? // empty][0] // empty')
        [ -z "$REQ" ] || { send_pointer --retry-request "$REQ" | submitted && PROVEN=1; }
      fi
    fi
    # The pane's Claude session id ties collect to this seat's log after the pane closes.
    SID=$(bash "$PP_SCRIPTS/read-verdict.sh" --session "$H" 2>/dev/null || true)
    [ -z "$SID" ] || [ "$(printf '%s\n' "$SID" | wc -l)" -ne 1 ] || echo "session=$SID" >> "$REC"
    # seat.sh wait counts the marker against what was typed, which is now this
    # pointer rather than the spec; a re-prompt that repoints spec= drops it.
    printf '%s\n' "$SPEC_TEXT" > "$REC.prompt"
    printf 'prompt=%s\n' "$REC.prompt" >> "$REC"
    # The record above is what main-watch.sh reads to wake main when this seat
    # finishes; collect completing task $T is what stops it.
    # PROVE THE TURN STARTED from the seat's session log, for up to the settle
    # window. Input acceptance and a painted prompt are not proof.
    SETTLE=${COMMANDECK_SEAT_SETTLE_SECONDS:-20} waited=0
    while [ "$PROVEN" = 0 ]; do
      ST=$(worker_state_kv --launched "$LAUNCH_EPOCH")
      case "$(kv state)" in running|complete) PROVEN=1; break ;; esac
      [ "$waited" -lt "$SETTLE" ] || break
      timeout 2 tail -f /dev/null || true; waited=$((waited + 2))
    done
    # Recover only a POSITIVELY unsubmitted composer: the agent's session exists
    # with no turn and the pane still shows the pointer. Anything less could be a
    # slow start, and a second prompt then runs the spec twice.
    if [ "$PROVEN" = 0 ] && [ "$DIRECT" = 0 ] && [ "$(kv reason)" = "no turn" ]; then
      screen=$(screen_lines || true)
      if grep -qF "$PTR" <<<"$screen" && ! grep -qE 'esc to interrupt|· Working' <<<"$screen"; then
        # ponytail: Ctrl-U clears the composer line in the Claude and Codex TUIs; not
        # proven on a live pane, so an unrecovered launch still says UNPROVEN below.
        timeout --kill-after=2 8 orca-ide terminal send --terminal "$H" --text $'\x15' --json >/dev/null 2>&1 || true
        send_pointer | submitted && PROVEN=1
      fi
    fi
    # An unproven prompt may still sit in the composer, where `go` would join it.
    if [ "$PROVEN" = 1 ]; then bash "$PP_SCRIPTS/seat-go.sh" "$H" "$CMD"
    else fail_if_review_menu; echo "UNPROVEN SUBMISSION: no turn start seen for $ROLE on $H (task $T). Read the pane before sending anything; nothing was typed twice." >&2
    fi
    # The seat is launched: a failed read only leaves its state unknown, never fails the launch (builder-launch.sh undoes those).
    state=$(timeout --kill-after=2 8 orca-ide terminal read --terminal "$H" --screen --json | jq -r '.. | strings' | { grep -oE 'Working|Ready|model: *[^ ]+' || true; } | head -2 | tr '\n' ' ') || true
    echo "seat=$ROLE unit=$UNIT handle=$H task=$T state=${state:-unknown} record=$REC"
    echo "phase=dispatched" >> "$REC"
  }
  ( trap 'rc=$?; [ "$rc" = 0 ] || echo "phase=failed" >> "$REC"' EXIT; trap '' HUP; launch_rest ) > "$REC.log" 2>&1 < /dev/null &
  echo "pid=$!" >> "$REC"
  echo "seat=$ROLE unit=$UNIT handle=$H task=$T phase=launching record=$REC log=$REC.log (seat.sh status $ROLE $UNIT)"
  ;;
collect)
  # A detached driver is a fresh process with no run bound, so the task close
  # below fails silently and the row outlives its pane. Tolerated, never fatal:
  # collect exists to harvest a verdict, and losing one costs a whole round.
  BOUND=$(bash "$PP_SCRIPTS/run-bound.sh" 2>/dev/null) && export ORCA_TERMINAL_HANDLE=$BOUND || true
  REPORT=""; ON_GO=""; ON_NOGO=""; DONE_MARKER=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --report) REPORT=${2:?}; shift 2 ;;
      --marker) DONE_MARKER=${2:?}; shift 2 ;;
      --on-go) ON_GO=${2:?}; shift 2 ;;
      --on-nogo) ON_NOGO=${2:?}; shift 2 ;;
      *) echo "collect: unknown flag $1" >&2; usage >&2; exit 2 ;;
    esac
  done
  [ -f "$REC" ] || { echo "no seat record at $REC" >&2; exit 2; }
  [ -n "$DONE_MARKER" ] || DONE_MARKER=$(sed -n 's/^marker=//p' "$REC" | tail -1)
  # An absolute --report (the usage example's form) is used as given; only a relative one lives in the worktree.
  case $REPORT in ''|/*) ;; *) REPORT=$WT/$REPORT ;; esac
  # With none given the report still outlives the pane collect closes, at a path read-verdict.sh --seat finds.
  [ -n "$REPORT" ] || { mkdir -p "$SCRATCH/reports"; REPORT=$SCRATCH/reports/$UNIT-$ROLE-${LAUNCHED:-0}.md; }
  H=$(grep '^handle=' "$REC" | cut -d= -f2); T=$(grep '^task=' "$REC" | cut -d= -f2)
  # The session log and its size BEFORE the read: the delivery receipt below is this pre-read pair, so a turn that
  # lands during the send is not counted as delivered.
  RLOG=$(pp_seat_log "$WT" "$(rec session)"); RSZ=""; [ -z "$RLOG" ] || RSZ=$(stat -c %s "$RLOG" 2>/dev/null || true)
  OUT=$(bash "$PP_SCRIPTS/read-verdict.sh" "$H" 400 "" "" "" "" "" "${LAUNCHED:-0}" 2>/dev/null || true)
  # read-verdict.sh prints its one canonical verdict line ahead of the report
  # slice; a bare VERDICT line inside the slice can be a fenced sample. With no
  # banner there is no verdict: the "NO VERDICT YET" tail it prints instead can hold one.
  V=$(printf '%s\n' "$OUT" | awk '/^=== .* : findings \+ verdict ===$/ { print v; exit } /^VERDICT:/ { v = $0 }')
  if [ -z "$V" ] && [ -n "$DONE_MARKER" ] && grep -qxF "$DONE_MARKER" <<<"$(unfenced <<<"$OUT" | sed -E 's/^[[:space:]*`]+//; s/[[:space:]*`"]+$//')"; then V=$DONE_MARKER; fi
  SD=$(reported "$DONE_MARKER" || true); [ -n "$V" ] || [ -z "$SD" ] || V=PLAN-DONE
  # A read-only seat cannot have written the report itself, so a file already
  # sitting at that path is a PREVIOUS round's and the pane is the only source
  # of truth: overwrite it. Skipping the write served h1c's triage the voided
  # report from a superseded brief on 2026-09-13 and cost the round.
  # The same holds for a file an earlier collect wrote (the record lists it): it is the pane text of a seat that
  # had not finished, and this collect's is newer.
  RO=0; seat_readonly && RO=1
  if [ -n "$REPORT" ] && { [ "$RO" = 1 ] || [ ! -s "$REPORT" ] || grep -qxF "report=$REPORT" "$REC"; } && [ -n "$OUT" ]; then
    # A report with no `# ` heading would transcribe as an empty file and the pane
    # is closed right after, so fall back to the whole pane text.
    BODY=$(printf '%s\n' "$OUT" | sed -n '/^# /,$p'); [ -n "$BODY" ] || BODY=$OUT
    printf '%s\n' "$BODY" > "$REPORT"; echo "report: $REPORT ($(wc -l < "$REPORT" | tr -d ' ') lines)"
    echo "report=$REPORT" >> "$REC"
  fi
  # The 240-char bound keeps a pane's findings out of main's context.
  # grep finds nothing on a marker-only seat; under pipefail that ended collect silently.
  printf '%s\n' "$OUT" | { grep -E '^\[P[0-3]\]|^- \[P[0-3]\]|^VERDICT|DONE$' || true; } | awk '{ print substr($0, 1, 240) }'
  # MAIN HEARS NOTHING BETWEEN DISPATCH AND THE DRIVER'S EXIT without this. The
  # loop never messages main at all and unit-drive.sh wakes it only on a failure
  # or the final merge, so three brief reviews finished on 2026-09-13 and main
  # learned of them an hour later, by hand. Every seat of every role routes
  # through collect, so one send here covers them all. SEND ONLY -- a drain here
  # would consume main's own wake-ups.
  # ADDRESS THE RUN, NEVER A PANE. A pane handle from a previous main resolves to
  # two durable mailboxes and Orca refuses the message as recipient_ambiguous;
  # that is how every wake was lost on 2026-09-13. `run:<id>` is canonical and
  # follows main to whatever pane it lives in.
  # A DRIVER'S SEAT SENDS NOTHING (COMMANDECK_DRIVER=1): the driver's own wake is
  # the one message for this event, and this send was its duplicate.
  # ONE REPORT PER FINISH (issue 321): a collect in main's own foreground sends only a finish a seat.sh wait claimed:
  # one main-watch posted is main's call, and main reads this output. One the seat reported itself already reached main.
  # A detached run's collect still sends when its wait gave up: nothing else tells main.
  SEND_RUN=${COMMANDECK_RUN:-$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE" || true)}
  if [ -n "$SEND_RUN" ] && [ -n "$V" ] && [ "${COMMANDECK_DRIVER:-0}" != 1 ] && [ "$SD" != message ] \
     && { ! pp_main_foreground || pp_waited_on "$H" "" "$V"$'\n'"$OUT"; }; then
    # One send per finish: under the seat's delivery lock (the one main-watch.sh flush takes) the receipt is read, so a
    # second collect, or one main-watch already posted, sends nothing. The receipt is written after Orca took the send
    # only, from the log read before it. A lock not had in 20s, or any doubt about the log, sends anyway: a duplicate,
    # never silence.
    DKEY=$SCRATCH/main-watch/delivered-seat-$H-$T; DFD=""
    mkdir -p "$SCRATCH/main-watch"
    { exec {DFD}>>"$DKEY.lock" && flock -w "${COMMANDECK_MAIN_WATCH_LOCK_S:-20}" "$DFD"; } 2>/dev/null || DFD=""
    if ! seat_delivered "$DKEY" "$RLOG" "$RSZ"; then
      if SENT=$(orca-ide orchestration send --run "$SEND_RUN" --to "run:$SEND_RUN" --type question \
          --subject "seat $ROLE $UNIT: ${V#VERDICT: }" --body "$V" --json 2>/dev/null) && jq -e '.ok == true' <<<"$SENT" >/dev/null 2>&1; then
        pp_wake_log seat "run:$SEND_RUN" "seat $ROLE $UNIT: ${V#VERDICT: }" sent
        { [ -z "$RLOG" ] || [ -z "$RSZ" ]; } || printf '%s\n%s\n' "$RLOG" "$RSZ" > "$DKEY"
      else pp_wake_log seat "run:$SEND_RUN" "seat $ROLE $UNIT: ${V#VERDICT: }" refused; echo "seat: could not wake main for $ROLE $UNIT" >&2; fi
    fi
    [ -z "$DFD" ] || exec {DFD}>&-
  fi
  [ -n "$V" ] || { echo "no VERDICT yet on $H (pane kept open)"; exit 3; }
  case ${LAUNCHED:-} in ''|*[!0-9]*) echo "invalid launch epoch in $REC" >&2; exit 1 ;; esac
  # SETTLE BEFORE ANYTHING ENDS THE SEAT (host issue 2998): the seat's task and every task answer-worker.sh made to carry
  # main's answers close first. A refusal (pane still working, an open question, a check that could not be read) is
  # retried for COMMANDECK_SEAT_SETTLE_RETRY_S, since a pane that just printed its verdict is often still ending its
  # turn; still refused, the pane stays open, no verdict= is written and collect exits 4. A rerun is the retry: the
  # report is on disk and the delivery receipt keeps it from waking main twice. settled= keeps a rerun from closing a
  # task twice.
  settle_seat() {
    local t res
    for t in "$T" $(sed -n 's/^answer_task=//p' "$REC"); do
      ! grep -qxF "settled=$t" "$REC" || continue
      if [ "$t" = "$T" ]; then res="{\"verdict\":\"${V#VERDICT: }\"}"; else res='{"done":"answer carried"}'; fi
      pp_task_close "$t" completed "$res" || return 1
      echo "settled=$t" >> "$REC"
    done
  }
  SETTLE_END=$(( $(date +%s) + ${COMMANDECK_SEAT_SETTLE_RETRY_S:-60} ))
  until SERR=$(settle_seat 2>&1); do
    [ "$(date +%s)" -lt "$SETTLE_END" ] || {
      printf '%s\n' "$SERR" >&2
      echo "seat $ROLE $UNIT: $V read, but its task is not settled (above); pane $H kept open, no verdict recorded. Rerun: bash $PP_SCRIPTS/seat.sh collect $ROLE $UNIT" >&2
      exit 4; }
    sleep 5
  done
  # seat-event.sh sums this pane's own session log; a missing or unreadable log
  # writes tokens:null with the reason and never blocks the row. A read VERDICT is done.
  # The row goes to the main checkout's ledger (seat-event.sh's own default), which the dashboard reads, wherever collect is run from.
  SEAT_EVENT_WORKTREE=$WT SEAT_EVENT_AGENT=$(seat_agent) SEAT_EVENT_STOP=done SEAT_EVENT_SPEC=$(sed -n 's/^tag=//p' "$REC" | tail -1) \
    "$(dirname "$0")/seat-event.sh" "$UNIT" "$ROLE" "$T" "$LAUNCHED" || echo "seat: no seat event recorded for $ROLE $UNIT" >&2
  pp_close_items "$H"
  pp_pane_close "$H" "verdict collected" || true
  echo "verdict=$V" >> "$REC"
  echo "collected=$(date +%s)" >> "$REC"
  [[ $ROLE != plan-author* ]] || plan_lines >> "$REC"
  echo "closed seat=$ROLE unit=$UNIT $V"
  case "$V" in
    "VERDICT: GO"*)    [ -z "$ON_GO" ]   || { echo "on-go: $ON_GO";     (cd "$ROOT" && eval "$ON_GO"); } ;;
    "VERDICT: NO-GO"*) [ -z "$ON_NOGO" ] || { echo "on-nogo: $ON_NOGO"; (cd "$ROOT" && eval "$ON_NOGO"); } ;;
  esac
  ;;
wait)
  MARKER=""; TIMEOUT=${COMMANDECK_SEAT_WAIT_SECONDS:-5400}; POLL=${COMMANDECK_LOOP_POLL_SECONDS:-30}
  while [ $# -gt 0 ]; do
    case "$1" in
      --marker) MARKER=${2:?}; shift 2 ;;
      --timeout-s) TIMEOUT=${2:?}; shift 2 ;;
      *) echo "wait: unknown flag $1" >&2; usage >&2; exit 2 ;;
    esac
  done
  [ -n "$MARKER" ] || { echo "wait: --marker is required" >&2; exit 2; }
  [ -f "$REC" ] || { echo "no seat record at $REC" >&2; exit 2; }
  # collect with no --marker closes on the marker of the latest wait that saw it end a finished turn (the exit trap):
  # a wait that gave up proved nothing, and the pane may still quote the marker unfinished.
  sed -i '/^marker=/d' "$REC"
  H=$(grep '^handle=' "$REC" | cut -d= -f2); SPEC=$(grep '^spec=' "$REC" | cut -d= -f2-)
  T=$(grep '^task=' "$REC" | cut -d= -f2); PROMPT=$(grep '^prompt=' "$REC" | cut -d= -f2- || true)
  TAG=$(grep '^tag=' "$REC" | cut -d= -f2- || true)
  # This wait is the pane's report: the record pp_waited_on reads keeps main-watch
  # and the turn-complete hooks from waking main for the same turn. It names the
  # line the wait actually saw: the marker, or the verdict that released it.
  WAITF=$SCRATCH/waiting-$H; pp_wait_mark > "$WAITF"; SEEN_MARK=$MARKER
  # stop_or_reported -- a plan author that reported or committed its plan since its latest prompt (pp_seat_since) is
  # released as PLAN-DONE; else the stop goes on.
  stop_or_reported() { reported "$MARKER" >/dev/null || return 0; SEEN_MARK=$MARKER; echo "marker $MARKER: $ROLE $UNIT reported its finish ($H)"; exit 0; }
  trap 'if [ $? = 0 ]; then printf "%s\nseen %s %s\n" "$$" "$(date +%s)" "$SEEN_MARK" > "$WAITF"
    [ "$SEEN_MARK" != "$MARKER" ] || echo "marker=$MARKER" >> "$REC"; else rm -f "$WAITF"; fi' EXIT
  # The pointer usually holds no marker; grep's exit 1 must not end the wait under pipefail.
  AGENT=$(seat_agent)
  # The rendered screen is the only pane text: Orca 1.4.220 keeps no accumulated
  # history for an agent TUI pane (its stream is one empty line). The screen can
  # show the spec's prose naming the marker, so only a line that IS the marker
  # counts, as collect reads it; the agent's bullet and gutter are stripped.
  # A pane can also echo its prompt, marker line included, and
  # the echo scrolls away while the agent works, so the prompt's marker lines
  # are told apart by the line above them, not counted off as a fixed baseline.
  # shortcut: a prompt whose FIRST line is the marker has no line above it and
  # its echo counts as the answer; give the marker a line of prose above it.
  # shortcut: an answer that repeats the prompt's line above the marker is not
  # seen once the echo has scrolled away; end a spec on prose the reply will
  # not repeat, or read the session log where the agent keeps one.
  marker_count() {
    local strip='s/^[[:space:]*`•]+//; s/[[:space:]*`"]+$//'
    unfenced | sed -E "$strip" | awk -v m="$MARKER" '
      !screen { if ($0 == m) { above[p] = 1; if (p != "") inprompt++ } else if ($0 != "") p = $0; next }
      $0 == m { own = 1
        # A wrapped prompt line shows only its tail above the marker.
        if (prev != "") for (a in above) if (substr(a, length(a) - length(prev) + 1) == prev) own = 0
        if (own) n++; else echoed++; next }
      $0 != "" { prev = $0 }
      # The echo shows each of the prompt markers once at most; more than that
      # is an answer that repeats the line above its marker.
      END { print n + (echoed > inprompt ? echoed - inprompt : 0) }' <(sed -E "$strip" "${PROMPT:-$SPEC}" 2>/dev/null) screen=1 -
  }
  END=$(( $(date +%s) + TIMEOUT )); busy_seen=0; idle_hits=0
  # A SILENT REVIEW SEAT IS RELAUNCHED ONCE. The one idle limit: a
  # read-only seat whose screen shows nothing new for this long (its status
  # line and digits aside) is closed and opened again on the same
  # spec; a second silence ends the wait with the pane's last lines. Median
  # brief review is 6-7 minutes.
  SEAT_SILENT_SECONDS=${COMMANDECK_SEAT_SILENT_SECONDS:-1800}
  RO=0; seat_readonly && RO=1
  last_sig="" last_change=$(date +%s)
  while [ "$(date +%s)" -lt "$END" ]; do
    # A pane that died never prints the marker, and every read below swallows
    # its error, so without this the wait burns the whole TIMEOUT (90 min by
    # default) before the driver learns anything. Only conclude "gone" when the
    # list call itself succeeded, so a transient CLI failure does not end a
    # healthy wait.
    # The membership test is a shell glob, NOT `printf | grep -q`. grep -q exits
    # the instant it matches, printf then takes SIGPIPE writing the rest, and
    # pipefail reports the whole pipeline failed -- so the negation read a LIVE
    # pane as gone and killed the driver. It only fires once the list outgrows
    # the 64 KB pipe buffer, which is why it appeared the first time six units
    # ran at once: wt1171's brief-reviewer was still writing its log when its
    # driver declared the pane gone and exited (2026-09-15).
    if LIST=$(orca-ide terminal list 2>/dev/null) && [ "${LIST#*"$H"}" = "$LIST" ]; then
      echo "seat $ROLE $UNIT: pane $H is gone; $MARKER will never arrive" >&2; exit 1
    fi
    # read_ok: a blank screen that was really read counts as silence; a failed read does not.
    raw=$(orca-ide terminal read --terminal "$H" --screen --json 2>/dev/null) && read_ok=1 || read_ok=0
    screen=$(printf '%s' "$raw" | jq -r '.result.terminal.tail[]?' 2>/dev/null || true)
    # OFFLINE IS CHECKED BEFORE BUSY, and it has to be: codex keeps "esc to
    # interrupt" up while it retries a dead endpoint, so the busy branch below
    # swallows a pane that will never finish and the wait burns all 90 minutes.
    # 2026-09-15: the proxy the reviewer CODEX_HOME routes through died and two
    # reviewers sat on "Reconnecting... waiting for network" for 46 and 33
    # minutes. Only the live spinner line counts (read-verdict.sh, exit 6).
    if grep -qE 'Reconnecting\.\.\. waiting for network' <<<"$screen"; then
      printf '%s\n' "$screen" | grep -aE 'Reconnecting\.\.\. waiting for network|Connection (refused|failed)|stream disconnected' | tail -3
      echo "seat $ROLE $UNIT: pane $H cannot reach a model, so $MARKER will never arrive" >&2; exit 1
    fi
    if [ "$RO" = 1 ] && [ "$read_ok" = 1 ]; then
      # The status line animates (spinner glyph, rotating verb, clock) on a
      # pane doing nothing, so it is not output.
      sig=$(printf '%s\n' "$screen" | { grep -viE 'esc to interrupt|extra thought|faster model' || true; } | tr -d '0-9' | cksum)
      if [ "$sig" != "$last_sig" ]; then last_sig=$sig last_change=$(date +%s)
      elif [ $(( $(date +%s) - last_change )) -ge "$SEAT_SILENT_SECONDS" ]; then
        if grep -qx 'relaunched=1' "$REC"; then
          printf '%s\n' "$screen" | tail -15
          echo "seat $ROLE $UNIT: relaunched pane $H showed nothing new for ${SEAT_SILENT_SECONDS}s either; $MARKER will not arrive" >&2; exit 1
        fi
        echo "seat $ROLE $UNIT: pane $H showed nothing new for ${SEAT_SILENT_SECONDS}s; closing it and relaunching once"
        # Close first: pp_task_close refuses a pane that still works, and the dispatch is ended only once the pane is
        # gone. A refusal at either step stops the wait with the old record intact, never a relaunch over a live task.
        pp_pane_close "$H" "silent, relaunching" || { echo "seat $ROLE $UNIT: pane $H did not close; not relaunching" >&2; exit 1; }
        pp_task_close "$T" failed '{"done":"silent, relaunched"}' || { echo "seat $ROLE $UNIT: task $T not settled; not relaunching" >&2; exit 1; }
        read -ra LOPTS <<<"$(grep '^opts=' "$REC" | cut -d= -f2- || true)"
        { COMMANDECK_DRIVER=1 bash "$0" launch "$ROLE" "$UNIT" "$SPEC" ${LOPTS[@]+"${LOPTS[@]}"} && settled; } || { echo "seat $ROLE $UNIT: relaunch failed: $(seat_status)" >&2; exit 1; }
        echo 'relaunched=1' >> "$REC"
        H=$(grep '^handle=' "$REC" | cut -d= -f2); T=$(grep '^task=' "$REC" | cut -d= -f2)
        rm -f "$WAITF"; WAITF=$SCRATCH/waiting-$H; pp_wait_mark > "$WAITF"
        LAUNCHED=$(grep '^launched=' "$REC" | cut -d= -f2); PROMPT=$(grep '^prompt=' "$REC" | cut -d= -f2- || true)
        TAG=$(grep '^tag=' "$REC" | cut -d= -f2- || true); seat_codex_home
        busy_seen=0 idle_hits=0 last_sig="" last_change=$(date +%s)
        continue
      fi
    fi
    # The session log outranks the screen: a completed turn ending in the marker
    # releases, a running turn or a background command waits, and a turn idle
    # past the reader's five-minute line stops the wait so the driver wakes main.
    # The spec picks this seat's session from a sibling's in the same worktree.
    # The launch proof above does not ask for it: a turn that has started has
    # not always written its prompt yet.
    ST=$(worker_state_kv --launched "${LAUNCHED:-0}" --spec "${TAG:-$SPEC}"); bind_session
    if [ "$(kv state)" = complete ] && [ -z "$(kv outstanding)" ] && [ "$(kv marker)" = 1 ]; then
      SEEN_MARK=$MARKER; echo "marker $MARKER up on $H (session log)"; exit 0
    fi
    # The driver wakes main with this output and keeps a route=stalled line
    # whole, so the pane's last words ride on it.
    if [ "$(kv first_turn_stall)" = 1 ]; then
      stop_or_reported
      echo "seat $ROLE $UNIT stalled: first turn ended without starting work"
      echo "STOP unit=$UNIT round=- route=stalled next=phase=seat:$ROLE pane=$H task=$T no tool call yet, last message: $(kv last_message) -- answer the pane, then bash $PP_SCRIPTS_Q/seat.sh wait $ROLE $UNIT --marker $MARKER && bash $PP_SCRIPTS_Q/seat.sh collect $ROLE $UNIT"
      exit 1
    fi
    if [ "$(kv stalled)" = 1 ]; then
      stop_or_reported
      echo "STOP unit=$UNIT round=- route=stalled next=phase=seat:$ROLE pane=$H task=$T idle=$(kv idle_seconds)s, last message: $(kv last_message) -- answer the pane, then bash $PP_SCRIPTS_Q/seat.sh wait $ROLE $UNIT --marker $MARKER && bash $PP_SCRIPTS_Q/seat.sh collect $ROLE $UNIT"
      echo "seat $ROLE $UNIT: pane $H is idle without $MARKER" >&2; exit 1
    fi
    if [ "$(kv state)" = running ] || [ -n "$(kv outstanding)" ]; then sleep "$POLL"; continue; fi
    if grep -qE 'esc to interrupt|· Working|extra thought|faster model' <<<"$screen"; then busy_seen=1; idle_hits=0
    else
      # A completed turn in the session log that did not end on the marker is no marker: its screen can still
      # show a quoted one (Sol r2). The screen counts only when the log cannot say.
      count=0; [ "$(kv state)" = complete ] || count=$(printf '%s\n' "$screen" | marker_count); SEEN_MARK=$MARKER
      # A marker scrolled off the screen is still in the session log, read the way collect reads it.
      # Any VERDICT line counts, not just GO/NO-GO: a seat may end on another
      # word, and a GO/NO-GO-only match left the drivers of
      # two builds waiting out a 90-minute timeout on seats that had
      # finished 35 minutes earlier (2026-09-13).
      if [ "${count:-0}" -eq 0 ]; then
        RV=$(bash "$PP_SCRIPTS/read-verdict.sh" "$H" 5 "" "" "" "" "" "${LAUNCHED:-0}" 2>/dev/null) && RVRC=0 || RVRC=$?
        # Only the reader's canonical line ahead of its banner, as collect reads it:
        # a "no verdict yet" tail can quote one in a fence.
        RVV=$(printf '%s\n' "$RV" | awk '/^=== .* : findings \+ verdict ===$/ { print v; exit } /^VERDICT:/ { v = $0 }')
        if [ -n "$RVV" ]; then count=1; SEEN_MARK=$RVV
        elif [ "$RVRC" -eq 5 ] || [ "$RVRC" -eq 6 ]; then
          # Exit 5 is "the pane's turn is over and it never printed the marker";
          # exit 6 is "the pane cannot reach a model", reached here only when the
          # screen read above came back empty. Neither ever prints the marker.
          # Waiting the rest of the timeout out cannot change that, and the
          # thing main needs is in $RV: wt775's plan-author ended on
          # PLAN-BLOCKED asking for a ruling and nobody heard it for 75 minutes.
          stop_or_reported
          printf '%s\n' "$RV"
          echo "seat $ROLE $UNIT: pane $H finished without $MARKER" >&2
          exit 1
        fi
      fi
      if [ "${count:-0}" -gt 0 ]; then
        idle_hits=$((idle_hits + 1))
        if [ "$busy_seen" = 1 ] || [ "$idle_hits" -ge 3 ]; then echo "marker $MARKER up on $H"; exit 0; fi
      fi
    fi
    sleep "$POLL"
  done
  echo "seat $ROLE $UNIT: no $MARKER on $H within ${TIMEOUT}s" >&2; exit 1
  ;;
*) usage >&2; exit 2 ;;
esac
