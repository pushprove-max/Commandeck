#!/usr/bin/env bash
# seat.sh launch <role> <unit> <spec-file>  -- open one routing.json seat in the
#     unit's worktree, hand it the spec (dispatch-task.sh's worker-start, retried
#     for about 60 s while Orca has not yet detected the pane's agent, then a
#     pane send when it is still refused), record handle and task under
#     $SCRATCH/seat-<unit>-<role>.txt.
# seat.sh collect <role> <unit> [--report <path>] [--marker <text>] [--on-go <cmd>] [--on-nogo <cmd>]
#     -- read the pane's verdict and findings (read-verdict.sh), write them to
#     --report when the pane could not (a read-only Codex sandbox cannot), close
#     the task and the pane, print the findings and the VERDICT line, then run
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
#
# Roles: any `roles.<name>.cmd` in config/routing.json. Main still writes the spec
# (the judgment); this script is the plumbing that cost six to ten main turns
# per seat by hand (ruling 2026-09-12, token cuts). Not a review-loop step:
# unit-loop.sh owns those.
set -euo pipefail
usage() { cat <<'EOF'
usage: seat.sh launch <role> <unit> <spec-file>   (COMMANDECK_SEAT_FORCE=1 reruns a spec that already finished)
       seat.sh launch builder <unit> <spec-file> [--model <alias>] [--effort medium|high] [--no-advisor]   (one launch only; builder-launch.sh passes them)
       seat.sh launch plan-<seat> <unit> <spec-file> [--model <alias>] [--effort <level>]   (the plan seat's model and effort the owner picked; it runs in <unit>-plan, made on its first launch)
       seat.sh collect <role> <unit> [--report <path>] [--marker <text>] [--on-go <cmd>] [--on-nogo <cmd>]
       seat.sh wait    <role> <unit> --marker <text> [--timeout-s <n>]
       seat.sh effort  <role> <unit> <handle> <level>
Open one routing.json seat in the unit's worktree, collect its verdict, or wait for its marker.
effort sends /effort <level> to the pane only while it is an idle Claude pane, and
never below routing's effort-stages.reviewer-floor to a read-only role.
  --report <path>   collect: write the findings here when the pane could not
  --marker <text>   collect: a marker line that stands in for VERDICT (collect falls back to the marker of the last wait); wait: the line to wait for
  --on-go <cmd>     collect: run this from the repo root on VERDICT: GO
  --on-nogo <cmd>   collect: run this from the repo root on VERDICT: NO-GO
  --timeout-s <n>   wait: give up after n seconds (default 5400)
  COMMANDECK_SEAT_REPO=<repo>   any command: the unit is a worktree of another Orca repo (other-repo)
example: scripts/seat.sh collect certifier my-unit --report /tmp/commandeck/my-unit-r1.md
EOF
}
case "${1:-}" in --help|-h) usage; exit 0 ;; launch|collect|wait|effort) ;; *) usage >&2; exit 2 ;; esac
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
# A plan seat runs before its Builder, whose launch makes the unit's worktree and refuses one already made: it works
# in its own planning worktree, <unit>-plan, which its first launch cuts from local main (below). A launched seat is
# read in the worktree its record names (worktree=); a record naming none is from before, when every seat ran in <unit>.
if [ "$CMDNAME" = launch ]; then WTN=$UNIT; [[ $ROLE != plan-* ]] || WTN=$UNIT-plan
else WTN=$(grep '^worktree=' "$REC" 2>/dev/null | tail -1 | cut -d= -f2- || true); WTN=${WTN:-$UNIT}; fi
WT=$WS/$WTN
# <unit>-plan is also a name a Builder unit can take: a plan seat reuses one only when its own first launch made it.
PLAN_OF=commandeck-plan-of
# The Panel's planners launch in parallel: the check here and the make and mark below are one step under this lock,
# or the second saw <unit>-plan made and not yet marked, and refused it (Sol r4). Released once the worktree is marked.
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
[ -d "$WT" ] || [[ $CMDNAME == launch && $ROLE == plan-* && -z $SEAT_REPO ]] || { echo "no worktree at $WT" >&2; exit 2; }
# The role whose routing the seat runs on. A plan seat put on another (pp_plan_seat: a Codex judge with no Codex
# runs as plan-judge-claude) keeps its own name, pane and record, so the Panel's two judges stay two.
RROLE=$ROLE
if [[ $ROLE == plan-* ]] && S=$(pp_plan_seat "$ROLE" 2>/dev/null); then RROLE=${S% *}; fi
# The seat's agent CLI, so the session reader looks in one provider's logs.
seat_agent() {
  pp_route "$RROLE" 2>/dev/null && printf '%s\n' "$RT_AGENT" || true
}
# The role's pane cannot write files: a codex read-only sandbox or a Claude seat without Write.
seat_readonly() {
  pp_route "$RROLE" && [ "$RT_READONLY" = 1 ]
}
# Bounded, so a blocked log read cannot freeze a wait or a launch.
worker_state_kv() {
  timeout 20 bash "$PP_SCRIPTS/read-verdict.sh" --state --worktree "$WT" --agent "${AGENT:-}" --marker "${MARKER:-}" "$@" 2>/dev/null || true
}
kv() { printf '%s\n' "$ST" | sed -n "s/^$1=//p" | head -1; }
# A record with no session= (a Codex seat, or a Claude pid lookup that failed) takes the log the reader found, so
# the seat's spend is its own (dashboard_limit.py seat_costs), not "Not tied to a seat". A Claude log binds as
# its session id, the form every reader of session= builds <projects>/<id>.jsonl from.
bind_session() {
  local s; s=$(kv session); [ "$(kv provider)" != claude ] || { s=${s##*/}; s=${s%.jsonl}; }
  grep -q '^session=' "$REC" 2>/dev/null || [ -z "$s" ] || echo "session=$s" >> "$REC"
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
  PANE=$(jq -rn --argjson ps "$(timeout 8 orca-ide worktree ps --json 2>/dev/null || echo '{}')" \
    --argjson ts "$(timeout 8 orca-ide terminal list --json 2>/dev/null || echo '{}')" --arg h "$H" '
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
      # A plan seat's effort is any level, checked with its role below; its model, one the agent it runs on already runs.
      [ -z "$LMODEL" ] || pp_seat_model_ok "$RROLE" "$LMODEL" || exit 2
    fi
  fi
  # A plan seat runs only on a model setup allows (planModels): a pick outside them is refused, and a default
  # outside them is swapped for an allowed one, which is said.
  if [[ $ROLE == plan-* ]]; then
    if [ -n "$LMODEL" ]; then
      [[ " $(pp_plan_models) " == *" $LMODEL "* ]] || { echo "REFUSED: --model $LMODEL is not one of the models this project allows a plan seat ($(pp_plan_models)); setup sets them (--plan-models)" >&2; exit 2; }
    else
      S=$(pp_plan_seat "$ROLE") || exit 2
      RROLE=${S% *} LMODEL=${S#* }
    fi
  fi
  pp_route "$RROLE" "$LEFFORT" "$LMODEL" "$LADVISOR" || { echo "no usable roles.$RROLE in routing.json" >&2; exit 2; }
  [ -n "$RT_CMD" ] || { echo "roles.$RROLE in routing.json is not a pane seat" >&2; exit 2; }
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
  # A Claude pane in a worktree takes the MAIN repo's ~/.claude.json project
  # entry. serena or codebase-memory disabled there left a worker with no
  # symbol tools and nothing said so (2026-09-18).
  if [ "$(seat_agent)" = claude ]; then
    MAIN_REPO=$(dirname "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)")
    OFF=$(jq -r --arg p "$MAIN_REPO" '.projects[$p].disabledMcpServers // [] | .[] | select(. == "serena" or . == "codebase-memory")' \
      "$HOME/.claude.json" 2>/dev/null | tr '\n' ' ' || true)
    [ -z "$OFF" ] || {
      echo "BLOCKED: ${OFF% } disabled in ~/.claude.json projects[\"$MAIN_REPO\"].disabledMcpServers; a Claude seat would run without it." >&2
      echo "Fix: re-enable it in /mcp from $MAIN_REPO, or remove it from that disabledMcpServers list, then launch again." >&2
      exit 2
    }
  fi
  # A plan seat's first launch cuts its planning worktree from local main, as builder-launch.sh cuts a Builder's.
  # Its git dir is marked as this unit's, the mark the reuse check above reads.
  if [ ! -d "$WT" ]; then
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
  # A Builder opened here by hand waits out a risky launch's second call (builder-launch.sh), which rewrites its records.
  [ "$ROLE" != builder ] || pp_builder_lock "$UNIT" || exit 1
  LAUNCH_EPOCH=$(date +%s)
  . "$PP_SCRIPTS/codex-helpers.sh"
  REUSED=0
  H=$(open_pane "path:$WT" "$(pane_title "$ROLE" "$UNIT")" "$CMD") || REUSED=$?
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
  orca-ide terminal wait --terminal "$H" --for tui-idle --timeout-ms 120000 --json >/dev/null || true
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
  SPEC_TEXT="Your task spec is the file $SPEC_ABS. Read all of it now and do what it says. Send no heartbeats, whatever the preamble above asks: main never reads one and each costs you a turn."
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
    || { echo "task-create failed for $ROLE $UNIT; closing pane $H" >&2; orca-ide terminal close --terminal "$H" --json >/dev/null 2>&1 || true; exit 1; }
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
  # The record is rewritten, but keeps the seat's first launch in this worktree: a relaunched planner's
  # planning still starts there (dashboard.sh plan_seats).
  FIRST=; [ "$(sed -n 's/^worktree=//p' "$REC" 2>/dev/null | tail -1)" != "$WTN" ] || FIRST=$(sed -n 's/^first=//p; s/^launched=//p' "$REC" | sort -n | head -1)
  printf 'handle=%s\ntask=%s\nrole=%s\nunit=%s\nworktree=%s\nlaunched=%s\nfirst=%s\nspec=%s\nspechash=%s\ntag=%s\ncmd=%s\n' "$H" "$T" "$ROLE" "$UNIT" "$WTN" "$LAUNCH_EPOCH" "${FIRST:-$LAUNCH_EPOCH}" "$SPEC_ABS" "$SPEC_HASH" "$TAG" "$CMD" > "$REC"
  seat_codex_home
  # The silent-pane relaunch below starts this seat again from its record.
  [ "${#LOPTS[@]}" -eq 0 ] || echo "opts=${LOPTS[*]}" >> "$REC"
  # A seat the origin placed here is the origin's to hear: main-watch on this
  # host skips a record that says so. A later local launch rewrites the record.
  [ -z "${COMMANDECK_ORIGIN_RUN:-}" ] || echo "origin=$COMMANDECK_ORIGIN_RUN" >> "$REC"
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
    screen=$(orca-ide terminal read --terminal "$H" --screen --json 2>/dev/null | jq -r '.result.terminal.tail[]?' 2>/dev/null || true)
    if grep -qF "$SPEC_ABS" <<<"$screen" && ! grep -qE 'esc to interrupt|· Working' <<<"$screen"; then
      # ponytail: Ctrl-U clears the composer line in the Claude and Codex TUIs; not
      # proven on a live pane, so an unrecovered launch still says UNPROVEN below.
      orca-ide terminal send --terminal "$H" --text $'\x15' --json >/dev/null 2>&1 || true
      send_pointer | submitted && PROVEN=1
    fi
  fi
  # An unproven prompt may still sit in the composer, where `go` would join it.
  if [ "$PROVEN" = 1 ]; then bash "$PP_SCRIPTS/seat-go.sh" "$H" "$CMD"
  else echo "UNPROVEN SUBMISSION: no turn start seen for $ROLE on $H (task $T). Read the pane before sending anything; nothing was typed twice." >&2
  fi
  state=$(orca-ide terminal read --terminal "$H" --screen --json | jq -r '.. | strings' | { grep -oE 'Working|Ready|model: *[^ ]+' || true; } | head -2 | tr '\n' ' ')
  echo "seat=$ROLE unit=$UNIT handle=$H task=$T state=${state:-unknown} record=$REC"
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
  H=$(grep '^handle=' "$REC" | cut -d= -f2); T=$(grep '^task=' "$REC" | cut -d= -f2)
  OUT=$(bash "$PP_SCRIPTS/read-verdict.sh" "$H" 400 "" "" "" "" "" "${LAUNCHED:-0}" 2>/dev/null || true)
  # read-verdict.sh prints its one canonical verdict line ahead of the report
  # slice; a bare VERDICT line inside the slice can be a fenced sample. With no
  # banner there is no verdict: the "NO VERDICT YET" tail it prints instead can hold one.
  V=$(printf '%s\n' "$OUT" | awk '/^=== .* : findings \+ verdict ===$/ { print v; exit } /^VERDICT:/ { v = $0 }')
  if [ -z "$V" ] && [ -n "$DONE_MARKER" ] && grep -qxF "$DONE_MARKER" <<<"$(unfenced <<<"$OUT" | sed -E 's/^[[:space:]*`]+//; s/[[:space:]*`"]+$//')"; then V=$DONE_MARKER; fi
  # A read-only seat cannot have written the report itself, so a file already
  # sitting at that path is a PREVIOUS round's and the pane is the only source
  # of truth: overwrite it. Skipping the write served h1c's triage the voided
  # report from a superseded brief on 2026-09-13 and cost the round.
  RO=0; seat_readonly && RO=1
  if [ -n "$REPORT" ] && { [ "$RO" = 1 ] || [ ! -s "$REPORT" ]; } && [ -n "$OUT" ]; then
    # A report with no `# ` heading would transcribe as an empty file and the pane
    # is closed right after, so fall back to the whole pane text.
    BODY=$(printf '%s\n' "$OUT" | sed -n '/^# /,$p'); [ -n "$BODY" ] || BODY=$OUT
    printf '%s\n' "$BODY" > "$REPORT"; echo "report transcribed: $REPORT ($(wc -l < "$REPORT") lines)"
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
  SEND_RUN=${COMMANDECK_RUN:-$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE" || true)}
  if [ -n "$SEND_RUN" ] && [ -n "$V" ] && [ "${COMMANDECK_DRIVER:-0}" != 1 ]; then
    orca-ide orchestration send --run "$SEND_RUN" --to "run:$SEND_RUN" --type question \
      --subject "seat $ROLE $UNIT: ${V#VERDICT: }" --body "$V" --json >/dev/null \
      || echo "seat: could not wake main for $ROLE $UNIT" >&2
  fi
  [ -n "$V" ] || { echo "no VERDICT yet on $H (pane kept open)"; exit 3; }
  case ${LAUNCHED:-} in ''|*[!0-9]*) echo "invalid launch epoch in $REC" >&2; exit 1 ;; esac
  # seat-event.sh sums this pane's own session log; a missing or unreadable log
  # writes tokens:null with the reason and never blocks the row. A read VERDICT is done.
  # The row goes to the main checkout's ledger (seat-event.sh's own default), which the dashboard reads, wherever collect is run from.
  SEAT_EVENT_WORKTREE=$WT SEAT_EVENT_AGENT=$(seat_agent) SEAT_EVENT_STOP=done SEAT_EVENT_SPEC=$(sed -n 's/^tag=//p' "$REC" | tail -1) \
    "$(dirname "$0")/seat-event.sh" "$UNIT" "$ROLE" "$T" "$LAUNCHED" || echo "seat: no seat event recorded for $ROLE $UNIT" >&2
  pp_task_close "$T" completed "{\"verdict\":\"${V#VERDICT: }\"}" || true
  orca-ide terminal close --terminal "$H" --json >/dev/null 2>&1 || true
  echo "verdict=$V" >> "$REC"
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
        # The pane is closed next, so ending its active dispatch is safe; a bare
        # task-update is refused while that dispatch is active.
        pp_task_close "$T" failed '{"done":"silent, relaunched"}' || true
        orca-ide terminal close --terminal "$H" --json >/dev/null 2>&1 || true
        read -ra LOPTS <<<"$(grep '^opts=' "$REC" | cut -d= -f2- || true)"
        COMMANDECK_DRIVER=1 bash "$0" launch "$ROLE" "$UNIT" "$SPEC" ${LOPTS[@]+"${LOPTS[@]}"} || { echo "seat $ROLE $UNIT: relaunch failed" >&2; exit 1; }
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
      echo "seat $ROLE $UNIT stalled: first turn ended without starting work"
      echo "STOP unit=$UNIT round=- route=stalled next=phase=seat:$ROLE pane=$H task=$T no tool call yet, last message: $(kv last_message) -- answer the pane, then bash $PP_SCRIPTS_Q/seat.sh wait $ROLE $UNIT --marker $MARKER && bash $PP_SCRIPTS_Q/seat.sh collect $ROLE $UNIT"
      exit 1
    fi
    if [ "$(kv stalled)" = 1 ]; then
      echo "STOP unit=$UNIT round=- route=stalled next=phase=seat:$ROLE pane=$H task=$T idle=$(kv idle_seconds)s; answer the pane, then bash $PP_SCRIPTS_Q/seat.sh wait $ROLE $UNIT --marker $MARKER && bash $PP_SCRIPTS_Q/seat.sh collect $ROLE $UNIT"
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
