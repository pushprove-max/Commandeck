#!/usr/bin/env bash
# unit-drive.sh start [--dry-run] <unit> <author-spec> <judge-spec> [<batch>] -- carry a unit from plan to its merge
# with no main turn between (issue 443): tier, plan-author, the plan loop (#559), builder-launch.sh --from-plan, then the
# watch to the merge (#651), which ends DONE on the merge or stops at builder-question, review, merge, builder or idle.
# A unit whose Builder pane is live is attached to and watched: no plan stage runs and no second Builder launches.
# The batch is <batch> or <main>/.claude/briefs/<unit>-batch.md, resolved once and exported to every stage as
# COMMANDECK_BATCH, beside COMMANDECK_DRIVER=1 (a driven seat sends main no wake of its own).
# start fixes or refuses everything once, before any seat: a missing Launch line or Plan section is appended to the
# batch; a missing batch, spec or Order line is refused. Then it starts `run` as the service drive-<unit>-<epoch>.
# --dry-run prints the preflight result and the stages, and creates nothing.
# run --owner <service> ... -- the stages. Tier runs plan-tier.sh on the batch first; the later stages run only the
# roles its `seat:` lines name (plan-author, then each judge in the order it lists them: Sol first, Opus when Sol is off,
# both on Panel, none for One planner). Exit 2 from plan-tier.sh stops at tier. `No plan` starts no seat and no Builder:
# the stop line hands main `builder-launch.sh --skip-plan`. Then the plan loop, per plan version (its sha256): an open
# `## Question for the owner` section is sent to main once (drive-<unit>.asked: `<sha256> <epoch>`) and the loop waits
# for decision plan-<unit> answered at or after that epoch, then one revision writes the answer in; the judges not yet
# on this version launch in tier order, are waited on together and collected. Every judge GO on the version with a report
# and no `Question for the owner:` line launches the Builder; anything else is one plan-author revision carrying every
# finding, judged again, with no round limit. A judge whose record holds a verdict on this version is not run again, so a
# re-run of start resumes. A failed or refused seat, a plan that changed while judged, a revision that changed nothing
# and a launch the launcher refused are stops: one `STOP unit=<u> stage=<s>: <why>; next: <command>` line in
# $PP_SCRATCH/unit-loop-<unit>.done, which the driver also sends to main itself (plugin main-watch posts no done file).
# Each step is a line on stderr with its UTC time, the plan version's first 8 characters and its verdict.
# One owner per unit: $PP_SCRATCH/drive-<unit>.lock (a flock file, fd 9) and drive-<unit>.owner (the service's name).
# start takes the lock for its whole admission (read the owner, take over only when hs_active says it is not running,
# write its own name, start the service with fd 9 closed); run holds it for its whole life and runs only while the owner
# file still names it, so a start that lost the race runs nothing.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
USAGE="usage: unit-drive.sh start [--dry-run] <unit> <author-spec> <judge-spec> [<batch>]"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
. "$HERE/host-services.sh"
CMD=${1:-}; shift || true
DRY=0 OWNER=
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY=1 ;;
    --owner) OWNER=${2:?--owner needs a service name}; shift ;;
    -*) echo "unknown option $1" >&2; echo "$USAGE" >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done
case $CMD in start|run) ;; *) echo "$USAGE" >&2; exit 2 ;; esac
[ $# -ge 3 ] && [ $# -le 4 ] || { echo "$USAGE" >&2; exit 2; }
UNIT=$1 ASPEC=$2 JSPEC=$3
[[ $UNIT =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bad unit name: $UNIT" >&2; exit 2; }
BATCH=${4:-$PP_MAIN/.claude/briefs/$UNIT-batch.md}
PLANF=$PP_WORKSPACES/$UNIT/.claude/plans/$UNIT.md
LOCK=$PP_SCRATCH/drive-$UNIT.lock OWNF=$PP_SCRATCH/drive-$UNIT.owner DONE=$PP_SCRATCH/unit-loop-$UNIT.done
ASKED=$PP_SCRATCH/drive-$UNIT.asked
rec() { sed -n "s/^$2=//p" "$PP_SCRATCH/seat-$UNIT-$1.txt" 2>/dev/null | tail -1 || true; }
abs() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }
owner_of() { cat "$OWNF" 2>/dev/null || echo "${1:-nobody}"; }

preflight() { # refuses (exit 2) or prints what it did, or under --dry-run would do
  local f add=() rc
  for f in "$BATCH" "$ASPEC" "$JSPEC"; do [ -s "$f" ] || { echo "REFUSED: $UNIT: no file at $f" >&2; exit 2; }; done
  grep -q '^Order:[[:space:]]*[^[:space:]]' "$BATCH" || { echo "REFUSED: $BATCH has no 'Order: <the owner's words>' line: main copies the owner's order into it" >&2; exit 2; }
  grep -qxF "Launch: new unit $UNIT" "$ASPEC" || { echo "REFUSED: $ASPEC has no 'Launch: new unit $UNIT' line: seat.sh opens the plan author only on the order's Launch and Order lines" >&2; exit 2; }
  grep -q '^Launch:' "$BATCH" || add+=("Launch: new unit $UNIT")
  # Issue 640: any heading form (closed, indented, setext) of Plan counts; one in a fence does not. Class-miss: a Plan
  # heading written in no accepted form refuses the start (2) instead of getting a second `## Plan` appended; 1 is absent.
  rc=0
  pp_gate_awk "$PP_AWK_FENCE"'fence($0) || flen { next } { heading($0); g = hgate("^Plan([[:space:]]|$)", "plan", "eq") }
    g == 2 { bad = 1 } g == 1 { f = 1 } END { exit bad ? 2 : !f }' "$BATCH" || rc=$?
  [ "$rc" != 2 ] || { echo "REFUSED: $UNIT: a Plan heading in $BATCH is not read as its Plan section (the line above); write it \`## Plan\`" >&2; exit 2; }
  [ "$rc" = 0 ] || add+=("" "## Plan" "" ".claude/plans/$UNIT.md")
  if [ "$DRY" = 1 ]; then
    [ "${#add[@]}" = 0 ] || printf 'would append to %s: %s\n' "$BATCH" "$(printf '%s|' "${add[@]}")"
    return 0
  fi
  # The batch append is an act (a refusal stamped by the Plan read above stops it).
  [ "${#add[@]}" = 0 ] || { { echo; printf '%s\n' "${add[@]}"; } > "$PP_SCRATCH/drive-$UNIT.add"
    pp_gate_act sh -c 'cat "$1" >> "$2"' sh "$PP_SCRATCH/drive-$UNIT.add" "$BATCH" || exit 2
    printf 'appended to %s: %s\n' "$BATCH" "$(printf '%s|' "${add[@]}")"; }
}

# other_projects -- issue 648 (D2): a worktree of another Orca repo whose folder is this unit's name refuses the start
# (exit 2) before the owner file, a worktree or a seat; an unreadable repo list warns once and the start goes on.
other_projects() {
  local repos r w
  repos=$(orca-ide repo list --json 2>/dev/null | jq -r '.result.repos | if type == "array" then .[].path // empty else error("no list") end' 2>/dev/null) \
    || { echo "unit-drive: $UNIT: the Orca repo list cannot be read; a same-named unit in another project is not checked" >&2; return 0; }
  while IFS= read -r r; do
    [ -n "$r" ] && [ "$r" != "$PP_MAIN" ] && [ "$r" != "$PP_MAIN_P" ] || continue
    w=$(git -C "$r" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | awk -v u="$UNIT" '{ n = $0; sub(/.*\//, "", n) } n == u { print; exit }')
    [ -z "$w" ] || { echo "REFUSED: $UNIT: $w in another project already uses this name; pick another unit name" >&2; exit 2; }
  done <<<"$repos"
}

stop() { # <stage> <why> <next>: the one stop line, kept in the done file and sent to main once
  local line
  line=$(printf 'STOP unit=%s stage=%s: %s; next: %s' "$UNIT" "$1" "$2" "$3")
  printf '%s\n' "$line" > "$DONE"
  echo "unit-drive: STOP $UNIT at $1: $2" >&2
  echo "$line" >&2
  bash "$HERE/to-main.sh" question "unit-drive: $UNIT stopped at $1" "$line" >/dev/null 2>&1 || true
  exit 1
}

# ended -- a run that ends DONE removes the args file its start wrote: only a driver that died keeps one, so
# recover-stalls.sh's R4 never restarts a finished unit (pass 18). A stop keeps it: the done file holds R4 off, and R4b
# restarts a plan seat's driver from it.
ended() { rm -f "$PP_SCRATCH/drive-$UNIT.args"; }

# gate_why -- the run's refusal stamp on one line, or nothing when it is empty (an act's rc 2 with a line here is a refusal).
gate_why() {
  if [ ! -f "${PP_GATE_STAMP:-}" ]; then echo "the gate refusal stamp is gone"; elif [ -s "$PP_GATE_STAMP" ]; then tr '\n' ' ' < "$PP_GATE_STAMP"; fi
}

if [ "$CMD" = start ]; then
  pp_gate_init || exit 1 # a fresh stamp for this start's gate reads (an inherited one is replaced)
  BATCH=$(abs "$BATCH" 2>/dev/null) || BATCH=$BATCH
  AGAIN="bash $HERE/unit-drive.sh start $UNIT $(abs "$ASPEC" 2>/dev/null || echo "$ASPEC") $(abs "$JSPEC" 2>/dev/null || echo "$JSPEC") $BATCH"
  if [ "$DRY" = 1 ]; then
    preflight
    printf 'stages: tier (plan-tier.sh), plan-author, then per plan version: question pause, the judges the tier names together, a revision unless every judge says GO; then builder-launch.sh --from-plan %s %s, then the watch to its merge\n' "$UNIT" "$BATCH"
    pp_gate_done
    exit 0
  fi
  mkdir -p "$PP_SCRATCH"
  exec 9>>"$LOCK"
  # A start holds the lock only through its admission; a run holds it for its whole life, so a start behind a live run
  # is refused by name after the wait.
  flock -w 60 9 || { echo "REFUSED: $UNIT is driven by $(owner_of 'another start')" >&2; exit 2; }
  OLD=$(cat "$OWNF" 2>/dev/null || true)
  if [ -n "$OLD" ]; then
    RC=0; hs_active "$OLD" || RC=$?
    [ "$RC" = 1 ] || { echo "REFUSED: $UNIT is driven by $OLD$([ "$RC" = 2 ] && echo ' (its state cannot be read)')" >&2; exit 2; }
  fi
  NAME=drive-$UNIT-$(date +%s)
  # Two starts in one second would share a name, and the owner check could not tell them apart.
  while [ "$NAME" = "$OLD" ]; do sleep 1; NAME=drive-$UNIT-$(date +%s); done
  other_projects
  # Named before the preflight, so a start refused at the lock meanwhile names this one; a refused preflight clears it.
  printf '%s\n' "$NAME" > "$OWNF"
  # Issue 663 R4: the run's own trap removes the owner file on any exit, so a dead driver is named by this file, which
  # outlives it: recover-stalls.sh restarts the unit from its four lines. A refused start removes it with the owner file.
  printf '%s\n' "$(abs "$ASPEC" 2>/dev/null || echo "$ASPEC")" "$(abs "$JSPEC" 2>/dev/null || echo "$JSPEC")" "$BATCH" "$NAME" > "$PP_SCRATCH/drive-$UNIT.args"
  trap 'rm -f "$OWNF" "$PP_SCRATCH/drive-$UNIT.args"' EXIT
  preflight
  rm -f "$DONE"
  # The service starts in $HOME, where nothing resolves the project: it gets the one this start resolved, as main-watch's
  # does, not a COMMANDECK_MAIN the caller's worktree overrode.
  ENVS=(HOME="$HOME" PATH="$PATH" COMMANDECK_MAIN="$PP_MAIN")
  # CLAUDE_CONFIG_DIR is the active profile: the stages read /plugin config (seats, models, effort) from it.
  for k in $(compgen -e); do
    case $k in COMMANDECK_MAIN) ;; ORCA_*|CODEX_HOME|CLAUDE_CONFIG_DIR|COMMANDECK_*) ENVS+=("$k=${!k}") ;; esac
  done
  # The service never holds the admission lock: its own run takes the lock once this start has let go.
  hs_start "$NAME" 512M "${ENVS[@]}" -- bash "$HERE/unit-drive.sh" run --owner "$NAME" "$UNIT" "$(abs "$ASPEC")" "$(abs "$JSPEC")" "$BATCH" 9>&- \
    || { echo "REFUSED: could not start $NAME" >&2; exit 2; }
  trap - EXIT
  pp_gate_done
  flock -u 9
  echo "unit-drive: $UNIT driven by $NAME; a stop lands in $DONE; resume after a stop: $AGAIN"
  exit 0
fi

# run: the owner file names this service, checked again under the lock, so a start that lost the race runs nothing.
[ -n "$OWNER" ] && [ "$(cat "$OWNF" 2>/dev/null)" = "$OWNER" ] || { echo "REFUSED: $UNIT is driven by $(owner_of)" >&2; exit 2; }
exec 9>>"$LOCK"
flock 9
[ "$(cat "$OWNF" 2>/dev/null)" = "$OWNER" ] || { echo "REFUSED: $UNIT is driven by $(owner_of)" >&2; exit 2; }
pp_gate_init || exit 1 # a fresh stamp for this run's gate reads
# Issue 659 (D6): stderr is copied into the log name board.sh and orca-wait.sh read, the epoch the service name's suffix.
DLOG=$PP_SCRATCH/scratchpad/$UNIT-drive-${OWNER##*-}.log
mkdir -p "${DLOG%/*}" && exec 2> >(tee -a "$DLOG" >&2) && TEE=$! || TEE=
trap 'rm -f "$OWNF"; [ -z "$TEE" ] || { exec 2>&-; wait "$TEE" 2>/dev/null; }' EXIT
export COMMANDECK_DRIVER=1 COMMANDECK_BATCH=$BATCH
AGAIN="bash $HERE/unit-drive.sh start $UNIT $ASPEC $JSPEC $BATCH"
# A service starts in $HOME; every stage runs in the main checkout, so gh finds the repository.
cd "$PP_MAIN" || stop drive "cannot enter the main checkout $PP_MAIN" "$AGAIN"

H=-
at() { echo "unit-drive: $(date -u +%Y-%m-%dT%H:%M:%SZ) $UNIT plan=${H:0:8} $1${2:+ $2}" >&2; } # <step> [verdict]
seat_stage() { # <role> <spec> [marker]: run the seat unless its record holds a verdict; stop on no verdict
  local rc=0
  [ -z "$(rec "$1" verdict)" ] || return 0
  at "$1"
  bash "$HERE/seat.sh" run "$1" "$UNIT" "$2" ${3:+--marker "$3"} >&2 || rc=$?
  case $rc in 0|1) ;; 5) stop "$1" "seat.sh run $1 recorded its verdict but its pane did not close (rc 5)" "bash $HERE/seat.sh close $1 $UNIT, then $AGAIN" ;;
    *) stop "$1" "seat.sh run $1 ended with no verdict (rc $rc)" "$AGAIN" ;; esac
}
# Issue 651 (D4, D6): watch_unit carries a launched unit to its merge; the Builder runs its own passes and fix rounds and
# main-watch merges, whose records are only read here. The generation is the seat record's launched= (L) and the
# worktree's HEAD, so an earlier build of a reopened unit never ends or stops this one. Each poll, in this order: a merged
# row of this unit at or after L ends DONE (its sha is the squash commit, so L binds it); an open Builder question, a
# REVIEW STOP from --verify (run when pp_gate_key changes), a merge refused for HEAD after L, a closed pane and a Builder
# quiet 3 polls in a row are each one stop. A merge job still running holds the last two. A fix round ends nothing.
watch_unit() {
  local L h wt=$PP_WORKSPACES/$UNIT r=$PP_SCRATCH/seat-$UNIT-builder.txt mr=$PP_SCRATCH/main-watch/merge-$UNIT
  local m key okey= head tip log rc run quiet=0
  L=$(rec builder launched) h=$(rec builder handle)
  [[ $L =~ ^[0-9]+$ ]] || { echo "unit-drive: $UNIT: no Builder seat record with a launch time; it is not watched to its merge" >&2; return 0; }
  pp_project "$PP_MAIN"
  while :; do
    # The row names its checkout by real path: another checkout may share this folder's name (merge-unit-local.sh).
    m=$(jq -r --arg u "$UNIT" --arg p "$PP_MAIN_P" --argjson l "$L" 'select(.how == "merged" and .unit == $u and .main == $p
      and ((.at // "" | try fromdateiso8601 catch 0) >= $l)) | .at' "$HOME/.commandeck/builds/$PP_PROJECT.jsonl" 2>/dev/null | tail -1 || true)
    if [ -n "$m" ]; then ended; echo "unit-drive: $UNIT merged at $m"; echo "DONE unit=$UNIT stage=merge: merged into main at $m" >&2; pp_gate_done; exit 0; fi
    if pp_seat_open_ask "$h" "$r"; then
      m=$(orca-ide orchestration inbox --limit 5000 --full --json 2>/dev/null | jq -r --arg id "$PP_OPEN_ASK_ID" 'first(.result.messages[]? | select(.id == $id) | .subject) // empty' 2>/dev/null || true)
      stop builder-question "the Builder asked: ${m:-question $PP_OPEN_ASK_ID}" "answer it with decision.sh, then $AGAIN"
    fi
    key=$(pp_gate_key "$UNIT" "$wt")
    if [ "$key" != "$okey" ]; then
      okey=$key m=$(timeout 60 bash "$HERE/builder-codex-pass.sh" --verify "$wt" "$UNIT" HEAD 2>&1 </dev/null | grep -m1 'REVIEW STOP:' || true)
      [ -z "$m" ] || stop review "$m" "answer decision $(sed -n 's/.*decision \(review-stop-[A-Za-z0-9._-]*\).*/\1/p' <<<"$m" | head -1), then $AGAIN"
    fi
    # main-watch's merge record: line 1 the tip the job tried, line 2 its log; the job's exit is <log>.rc (merge_collect).
    head=$(git -C "$wt" rev-parse HEAD 2>/dev/null || true) tip=$(sed -n 1p "$mr" 2>/dev/null || true) log=$(sed -n 2p "$mr" 2>/dev/null || true)
    rc=; [ -z "$log" ] || rc=$(cat "${log%.log}.rc" 2>/dev/null || true)
    if [ -n "$head" ] && [ "$tip" = "$head" ] && [ -n "$rc" ] && [ "$rc" != 0 ] && [ "$(date -r "${log%.log}.rc" +%s)" -ge "$L" ]; then
      m=$(grep '^merge-queue: ' "$log" | grep -wF -- "$UNIT" | tail -1 || true)
      stop merge "${m:-the merge job exited $rc; log $log}" "bash $HERE/merge-unit-local.sh $UNIT, then $AGAIN"
    fi
    run=; [ ! -f "$mr" ] || [ -n "$rc" ] || [ "$(date -r "$mr" +%s)" -lt "$L" ] || run=1
    [ -n "$run" ] || [ -n "$(PP_PANE_MAP_FRESH=1 pp_seat_pane "unit-$UNIT" "$wt")" ] \
      || stop builder "its pane $h closed before the merge" "bash $HERE/builder-launch.sh --from-plan $UNIT $BATCH"
    if [ -z "$run" ] && pp_turn_quiet "$(pp_seat_turn "$r")"; then quiet=$((quiet + 1)); else quiet=0; fi
    [ "$quiet" -lt 3 ] || stop idle "the Builder is idle and nothing merges" "$AGAIN"
    sleep "${COMMANDECK_LOOP_POLL_SECONDS:-30}"
  done
}
# Issue 651 (D5): a live Builder pane, by pp_seat_pane (the read main uses, here read fresh), is attached to and watched;
# builder-launch.sh is never called over it. None live: the plan stages and the launch run.
LIVE=$(PP_PANE_MAP_FRESH=1 pp_seat_pane "unit-$UNIT" "$PP_WORKSPACES/$UNIT")
if [ -n "$LIVE" ]; then
  echo "unit-drive: $UNIT attached to its Builder $LIVE" >&2
  watch_unit
  stop builder "its pane $LIVE is live but no seat record names its launch" "read the pane $LIVE"
fi

at tier
# Its stderr joins stdout: the refusal reaches the STOP line with no file kept, and the parsers below read only their lines.
TRC=0; TOUT=$(bash "$HERE/plan-tier.sh" "$BATCH" 2>&1) || TRC=$?
[ "$TRC" = 0 ] || stop tier "plan-tier.sh refused (exit $TRC): $(grep -vE '^(off|tier|seat|effort|launch): ' <<<"$TOUT" | head -3 | tr '\n' ' ')" "fix that, then $AGAIN"
TIER=$(sed -n 's/^tier: \(.*\) (trigger:.*/\1/p' <<<"$TOUT" | head -1)
if [ "$TIER" = 'No plan' ]; then
  REASON=$(sed -n "s/^launch: .*--reason '\(.*\)'\$/\1/p" <<<"$TOUT" | head -1)
  stop tier 'No plan' "bash $HERE/builder-launch.sh --skip-plan --reason '$REASON' $UNIT $BATCH"
fi
ROLES=$(sed -n 's/^seat: \([^ ]*\).*/\1/p' <<<"$TOUT")
[ -n "$ROLES" ] || stop tier "plan-tier.sh printed no seat for tier ${TIER:-unknown}" "$AGAIN"

if grep -qxF plan-author <<<"$ROLES"; then
  seat_stage plan-author "$ASPEC" PLAN-DONE
  [ "$(rec plan-author verdict)" = PLAN-DONE ] || stop plan-author "the plan author ended on $(rec plan-author verdict), not PLAN-DONE" "$AGAIN"
  [ -f "$PLANF" ] || stop plan-author "no plan at $PLANF" "$AGAIN"
fi
# The plan loop (#559): a plan version is its sha256. It passes when every judge the tier names has a GO on it, with a
# report and no question line; anything else is one revision carrying every finding, judged again, with no round limit.
JUDGES=$(grep -vx plan-author <<<"$ROLES" || true)
hash_plan() { [ -f "$PLANF" ] && sha256sum "$PLANF" | cut -d' ' -f1; }
rlog() { echo "$PP_SCRATCH/seat-$UNIT-$1.run.log"; }
report_of() { local r; r=$(rec "$1" report); printf '%s\n' "${r:-$PP_SCRATCH/reports/$UNIT-$1-$(rec "$1" launched).md}"; }
on_version() { [ "$(rec "$1" planhash)" = "$H" ] && [ -n "$(rec "$1" verdict)" ]; } # <judge>: a verdict on this version
# A report's question lines: every line holding `question for the owner:` in any case, quoted or not, unless the WHOLE
# line is the none statement. No markup is parsed to find one, so none can hide one: a misread costs a revision.
qlines() {
  LC_ALL=C awk -v f="$1" '{ l = tolower($0) } index(l, "question for the owner:") \
    && l !~ /^[[:space:]]*([-*][[:space:]]+)?(\*\*)?question for the owner:(\*\*)?[[:space:]]*none( new)?\.?[[:space:]]*$/ {
    print f ":" FNR ": " $0 }' "$1"
}
# QSEC (issue 640): the Question section by fence.sh's heading(): it starts at a heading of any level titled
# `Question for the owner` (hgate 1; one whose letters hold `question` and `owner` but is not that title is hgate 2: the
# read refuses, exit 2, the line stamped; pp_gate_awk returns 2 on it) and ends at the next heading of level 2 or less; its lines go to emit() through hold(), so a
# setext heading's title lines never count as section lines (DE13). Each reader defines emit() and done().
QSEC="$PP_AWK_FENCE"'
  { f = fence($0) } f || flen { if (s) emit(hflush() $0 "\n"); next }
  { heading($0); o = hold($0) }
  { g = hgate("^Question for the owner$", "question&owner", "has") }
  g == 2 { qbad = 1; exit 2 }
  s && hlvl && hlvl <= 2 { emit(o); exit }
  !s && g == 1 { s = 1; next }
  s { emit(o) }
  END { if (qbad) exit 2; if (s) emit(hflush()); done() }'
qsection() { pp_gate_awk "$QSEC"'function emit(t) { printf "%s", t } function done() { }' "$PLANF"; }
# The plan's Question section is open unless it is absent, empty, ONE paragraph whose first line starts `None:` with
# no list, number or quote line in it, or (issue 657) one line that is only `none`, any case, list marker optional, one
# trailing period allowed; every other shape, a quoted none or one with trailing words included, is open.
qopen() {
  pp_gate_awk "$QSEC"'function emit(t,   k, i, a) { k = split(t, a, "\n"); for (i = 1; i < k; i++) line1(a[i]) }
    function line1(l) {
      if (l !~ /[^[:space:]]/) { if (n) gap = 1; return }
      if (gap || l ~ /^[[:space:]]*([-*+>]|[0-9]+[.)])/ || (n == 0 && l !~ /^[[:space:]]*None:/)) bad = 1; n++
      if (tolower(l) ~ /^[[:space:]]*([-*+][[:space:]]+)?none\.?[[:space:]]*$/) lone++ }
    function done() { exit !(n && bad && !(n == 1 && lone == 1)) }' "$PLANF"
}
revise() { # <spec>: the plan-author seat on the spec; a revision that leaves the plan unchanged stops
  at revise
  local rc=0 w; COMMANDECK_SEAT_FORCE=1 pp_gate_act bash "$HERE/seat.sh" run plan-author "$UNIT" "$1" --marker PLAN-DONE >&2 || rc=$?
  w=$(gate_why); [ "$rc" != 2 ] || [ -z "$w" ] || stop revise "a gate read refused, so the plan author did not run: $w" "fix the heading it names, then $AGAIN"
  [ "$rc" != 5 ] || stop revise "the revise run of plan-author recorded PLAN-DONE but its pane did not close (rc 5)" "bash $HERE/seat.sh close plan-author $UNIT, then $AGAIN"
  [ "$rc" = 0 ] || stop revise "the revise run of plan-author ended with rc $rc, not PLAN-DONE" "$AGAIN"
  [ "$(hash_plan || true)" != "$H" ] || stop revise "the revision left the plan unchanged (sha256 $H)" "$AGAIN"
}
# put_rev <stage> <scratch copy> <rev> -- the revise spec into main's briefs is an act: a refusal stops, naming the stamp.
put_rev() {
  local rc=0 w; pp_gate_act cp "$2" "$3" || rc=$?
  [ "$rc" = 0 ] && return 0
  w=$(gate_why); [ "$rc" != 2 ] || [ -z "$w" ] || stop "$1" "a gate read refused, so the revise spec was not written: $w" "fix the heading it names, then $AGAIN"
  return 1
}
judge_spec() { # <file>: main's judge spec and the version it is launched for (a new hash is a spec seat.sh has not finished)
  local J p prev=
  for J in $JUDGES; do p=$(report_of "$J"); [ ! -s "$p" ] || [ -z "$(rec "$J" verdict)" ] || prev+="- $J: $p"$'\n'; done
  { cat "$JSPEC"; printf '\n## This version\n\nYou judge %s at sha256 %s. Print your report in the chat; this seat changes no file.\n' "$PLANF" "$H"
    [ -z "$prev" ] || printf "\nThe previous version's judge reports:\n\n%s" "$prev"
    printf '\nThe phrase `Question for the owner:` appears in your report only to head a new question finding.\n'
  } > "$1"
}
judge_round() { # <judge>...: launched in turn, waited on together, each collected; then at most one stop
  local J rc i p w fail= failwhy= L=() P=()
  for J in "$@"; do
    at "launch $J"; rc=0; pp_gate_act bash "$HERE/seat.sh" launch "$J" "$UNIT" "$JS" > "$(rlog "$J")" 2>&1 || rc=$?
    w=$(gate_why); [ "$rc" != 2 ] || [ -z "$w" ] || { fail=$J failwhy="$J: a gate read refused, so it did not launch: $w"; break; }
    [ "$rc" = 0 ] || { fail=$J failwhy="$J: $(grep -m1 -E 'REFUSED|BLOCKED|failed|cannot' "$(rlog "$J")" || echo "seat.sh launch ended with rc $rc")"; break; }
    L+=("$J")
  done
  # launch returns before its pane is typed into (the record's pid is the rest of it): wait only on a settled launch.
  for J in ${L[@]+"${L[@]}"}; do
    ( p=$(rec "$J" pid); while [ -n "$p" ] && kill -0 "$p" 2>/dev/null; do sleep 1; done
      [ "$(rec "$J" phase)" != failed ] || exit 1
      exec bash "$HERE/seat.sh" wait "$J" "$UNIT" --marker 'VERDICT: GO' >> "$(rlog "$J")" 2>&1 ) & P+=($!)
  done
  # A failed wait (dead pane, stall, timeout) is not the end: collect decides, as seat.sh run does.
  for i in ${L[@]+"${!L[@]}"}; do rc=0; wait "${P[$i]}" || rc=$?; at "wait ${L[$i]}" "rc $rc"; done
  for J in ${L[@]+"${L[@]}"}; do
    rc=0; bash "$HERE/seat.sh" collect "$J" "$UNIT" >> "$(rlog "$J")" 2>&1 || rc=$?
    case $rc in
      0) at "collect $J" "$(rec "$J" verdict)"; continue ;;
      3) p="no verdict" ;;
      4) p="verdict read, task not settled" ;;
      5) p="verdict recorded, pane did not close (bash $HERE/seat.sh close $J $UNIT)" ;;
      *) p="collect failed (rc $rc)" ;;
    esac
    at "collect $J" "rc $rc"
    [ -n "$fail" ] || { fail=$J failwhy="$J: $p"; }
  done
  # Every launched judge is collected first, so a restart reruns only the one that failed.
  [ -z "$fail" ] || stop judge "$failwhy" "$AGAIN"
}
# say_once <key> <line> -- the line on stderr once per question-gate entry (SAID), not once per poll.
say_once() { case $SAID in *"|$1|"*) return 0 ;; esac; SAID+="|$1|"; echo "$2" >&2; }
# other_answer <ask epoch> -- issue 632 (D13, D15): the owner may answer in another Orca repo's main session, which records
# it in that repo's ledger. Each other repo Orca lists that has a ledger is read with this gate's id and after-ask filter, and
# a row counts only when its question or source carries this ask's token `plan <hash8>`, so a same-named unit's answer
# there, or one to an older plan, never releases the gate. OANS is the answer taken; each problem is said once.
other_answer() {
  local repos r l a tok="plan ${H:0:8}"
  OANS=
  repos=$(orca-ide repo list --json 2>/dev/null | jq -r '.result.repos | if type == "array" then .[].path // empty else error("no list") end' 2>/dev/null) \
    || { say_once repos "unit-drive: $UNIT: the Orca repo list cannot be read; plan-$UNIT is read from this project's ledger only"; return 0; }
  while IFS= read -r r; do
    [ -n "$r" ] && [ "$r" != "$PP_MAIN" ] && [ "$r" != "$PP_MAIN_P" ] && [ -e "$r/.claude/metrics/decisions.jsonl" ] || continue
    a=$(COMMANDECK_MAIN=$r bash "$HERE/decision.sh" list 2>/dev/null | jq -c --arg id "plan-$UNIT" --argjson b "$1" \
      '[.[] | select(.id == $id and ((.answeredAt // "" | try fromdateiso8601 catch 0) >= $b))] | last // empty' 2>/dev/null) \
      && l=ok || l=
    [ -n "$l" ] || { say_once "list $r" "unit-drive: $UNIT: the decisions ledger of $r cannot be read; it is left out"; continue; }
    [ -n "$a" ] || continue
    if jq -e --arg t "$tok" '((.question // "") + " " + (.source // "")) | contains($t)' <<<"$a" >/dev/null 2>&1; then
      OANS=$(jq -r '.answer // empty' <<<"$a"); [ -z "$OANS" ] || return 0
    else
      say_once "token $r" "unit-drive: $UNIT: $r's decision plan-$UNIT is answered but names no \`$tok\`, so it is not taken; record the answer there again with \`$tok\` in its question"
    fi
  done <<<"$repos"
  return 0 # set -e: the loop's last test is no failure
}
question_gate() { # an open Question section waits for the owner's answer, recorded after this version was asked
  local ah= ae= list ans rc=0 REV RT resent= need
  qopen 2>"$PP_SCRATCH/drive-$UNIT.qsec" || rc=$?
  [ "$rc" != 2 ] || stop question "$(head -1 "$PP_SCRATCH/drive-$UNIT.qsec")" "fix that heading in the plan, then $AGAIN"
  [ "$rc" = 0 ] || return 0
  rc=0
  SAID=
  read -r ah ae < "$ASKED" 2>/dev/null || true
  if [ "$ah" != "$H" ] || [[ ! $ae =~ ^[0-9]+$ ]]; then
    ae=$(date +%s)
    bash "$HERE/to-main.sh" question "unit-drive: $UNIT asks the owner (plan ${H:0:8})" "$(qsection)"$'\n\n'"Put it to the owner as decision plan-$UNIT, and keep \`plan ${H:0:8}\` in its question (an answer in another repo's ledger counts only with it); the driver waits for the answer." >/dev/null 2>&1 || rc=$?
    case $rc in 0|3) ;; *) stop question "main could not be sent the question in $PLANF (to-main.sh rc $rc)" "put the plan's Question section to the owner as decision plan-$UNIT, then $AGAIN" ;; esac
    printf '%s %s\n' "$H" "$ae" > "$ASKED"
  fi
  # Issue 657 (D4): a question main never recorded as plan-<unit> is re-sent once per plan version per run, one poll after
  # the ask, with one NEEDS-MAIN line; a queued send (rc 3: main is down) says the line at once and the queue keeps it.
  need="NEEDS-MAIN: $UNIT asked main plan-$UNIT at $(jq -rn --argjson e "$ae" '$e | todate') and no decision exists; record it with decision.sh add plan-$UNIT"
  [ "$rc" != 3 ] || { resent=1; say_once needs "$need"; }
  at question
  while :; do
    list=$(bash "$HERE/decision.sh" list 2>"$PP_SCRATCH/drive-$UNIT.decision") \
      || stop question "decision.sh list failed: $(head -1 "$PP_SCRATCH/drive-$UNIT.decision")" "$AGAIN"
    # Only an answer at or after the ask counts: the ledger keeps one row per id, so an older round's never releases it.
    ans=$(jq -r --arg id "plan-$UNIT" --argjson b "$ae" \
      '[.[] | select(.id == $id and ((.answeredAt // "" | try fromdateiso8601 catch 0) >= $b))] | last | .answer // empty' <<<"$list") \
      || stop question "the decisions ledger could not be read" "$AGAIN"
    [ -z "$ans" ] || break
    other_answer "$ae"; ans=$OANS
    [ -z "$ans" ] || break
    if [ -z "$resent" ] && [ $(($(date +%s) - ae)) -ge "${COMMANDECK_LOOP_POLL_SECONDS:-30}" ] \
      && ! jq -e --arg id "plan-$UNIT" 'any(.[]; .id == $id)' <<<"$list" >/dev/null 2>&1; then
      resent=1
      bash "$HERE/to-main.sh" question "unit-drive: $UNIT NEEDS-MAIN (plan ${H:0:8})" "$need"$'\n\n'"$(qsection)" >/dev/null 2>&1 || true
      say_once needs "$need"
    fi
    sleep "${COMMANDECK_LOOP_POLL_SECONDS:-30}"
  done
  at question answered
  REV=$PP_MAIN/.claude/briefs/_$UNIT-plan-revise-${H:0:12}.md
  mkdir -p "$(dirname "$REV")"; RT=$PP_SCRATCH/drive-$UNIT.rev
  { grep -m1 '^Order:' "$ASPEC" || true; echo "Launch: new unit $UNIT"; echo
    echo "# $UNIT: revise the plan on the owner's answer"
    echo
    echo "The owner answered decision plan-$UNIT: $ans"
    echo
    echo "Revise $PLANF: write the answer into the plan's Decisions, add a Plan change log line for each change, and make the section under the \`## Question for the owner\` heading read \`None: answered as D<n>\`. End with PLAN-DONE on a line of its own."
  } > "$RT" && put_rev question "$RT" "$REV" || stop question "could not write the revise spec $REV" "$AGAIN"
  revise "$REV"
}

while :; do
  H=$(hash_plan) || stop plan "no plan at $PLANF" "$AGAIN"
  question_gate
  [ "$(hash_plan || true)" = "$H" ] || continue
  PEND=
  for J in $JUDGES; do on_version "$J" || PEND="$PEND $J"; done
  if [ -n "$PEND" ]; then
    JS=$PP_SCRATCH/drive-$UNIT-judge-${H:0:12}.md
    [ -s "$JS" ] || judge_spec "$JS" || stop judge "could not write the judge spec $JS" "$AGAIN"
    judge_round $PEND
    [ "$(hash_plan || true)" = "$H" ] || stop judge "the plan changed while it was judged (judged sha256 $H, now $(hash_plan || echo gone))" "$AGAIN"
  fi
  PASS=1 QS=
  for J in $JUDGES; do
    [ "$(rec "$J" planhash)" = "$H" ] \
      || stop judge "$J's record names plan $(rec "$J" planhash | cut -c1-8), not $H: its spec needs the line 'Plan: .claude/plans/$UNIT.md'" "$AGAIN"
    case $(rec "$J" verdict) in "VERDICT: GO"|"VERDICT: GO "*) ;; *) PASS=0 ;; esac
    # A verdict is read only with its report: a missing report is never read as one with no question.
    RP=$(report_of "$J")
    [ -s "$RP" ] && [ -r "$RP" ] || stop judge "no report of $J's verdict at $RP" "rerun $J on this version (COMMANDECK_SEAT_FORCE=1 COMMANDECK_HAND_LAUNCH=<reason> seat.sh run $J $UNIT $JS), then $AGAIN"
    QS+=$(qlines "$RP") || stop judge "the report $RP cannot be read" "$AGAIN"
  done
  [ "$PASS" = 0 ] || [ -n "$QS" ] || break
  # A NO-GO, or a GO asking the owner something: a revision carrying every finding, judged again next pass.
  REV=$PP_MAIN/.claude/briefs/_$UNIT-plan-revise-${H:0:12}.md
  mkdir -p "$(dirname "$REV")"; RT=$PP_SCRATCH/drive-$UNIT.rev
  { grep -m1 '^Order:' "$ASPEC" || true; echo "Launch: new unit $UNIT"; echo
    echo "# $UNIT: revise the plan on the judges' findings (sha256 $H)"
    echo
    echo "Revise $PLANF on every finding below. Fix each one, or rebut it in the Plan change log with a concrete counterexample; turn each \`Question for the owner:\` finding into an item under the plan's \`## Question for the owner\` heading. Add a Plan change log line for each change. End with PLAN-DONE on a line of its own."
    echo
    echo "Read each report whole:"
    echo
    for J in $JUDGES; do echo "- $J ($(rec "$J" verdict)): $(report_of "$J")"; done
    echo
    echo "Their findings:"
    echo
    # `[P1]`, and `**F1 (P1):**` (issue 625): a finding in either form is carried.
    for J in $JUDGES; do grep -iE '\[P[0-3]\]|\(P[0-3]\)|question for the owner:' "$(report_of "$J")" || true; done
  } > "$RT" && put_rev revise "$RT" "$REV" || stop revise "could not write the revise spec $REV" "$AGAIN"
  revise "$REV"
done
at launch
LRC=0; LOUT=$(pp_gate_act bash "$HERE/builder-launch.sh" --from-plan "$UNIT" "$BATCH" 2>&1) || LRC=$? # an act
if [ "$LRC" != 0 ]; then
  W=$(gate_why); [ "$LRC" != 2 ] || [ -z "$W" ] || stop launch "a gate read refused, so the Builder did not launch: $W" "fix the heading it names, then $AGAIN"
  stop launch "builder-launch.sh refused: $(grep -m1 -E 'REFUSED|failed' <<<"$LOUT" || tail -1 <<<"$LOUT")" "fix that, then $AGAIN"
fi
printf '%s\n' "$LOUT" >&2
# Issue 659 (D5): seat.sh launch returns before its pane is typed into; the record's pid runs the rest. The driver waits
# for a turn that started after the record's launched=, flags the pane once 60 s after the launch with none, and stops
# with the dispatch command when the launch failed or never proved its turn; it never dispatches again itself.
launch_wait() {
  local l h t p ph line flagged= poll=${COMMANDECK_LAUNCH_POLL_SECONDS:-5} rl=$PP_SCRATCH/seat-$UNIT-builder.txt.log
  l=$(rec builder launched)
  [[ $l =~ ^[0-9]+$ ]] || { echo "unit-drive: $UNIT: no Builder seat record with a launch time; its turn start is not checked" >&2; return 0; }
  h=$(rec builder handle) t=$(rec builder task)
  while :; do
    case $(bash "$HERE/read-verdict.sh" --state --worktree "$PP_WORKSPACES/$UNIT" --launched "$l" 2>/dev/null | sed -n 's/^state=//p') in
      running|complete) return 0 ;;
    esac
    p=$(rec builder pid) ph=$(rec builder phase)
    if [ "$ph" = failed ] || grep -q 'UNPROVEN SUBMISSION' "$rl" 2>/dev/null \
      || { [ "$ph" != dispatched ] && ! { [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }; }; then
      stop launch "the Builder pane $h opened but no turn started (task $t)" "bash $HERE/dispatch-task.sh $t terminal:$h, then read the pane"
    fi
    # dispatched with no UNPROVEN line: seat.sh proved the turn from the same session log.
    [ "$ph" != dispatched ] || { [ -n "$p" ] && kill -0 "$p" 2>/dev/null; } || return 0
    if [ -z "$flagged" ] && [ $(($(date +%s) - l)) -ge 60 ]; then
      flagged=1 line="FLAG: $UNIT Builder pane $h has no started turn 60 s after launch (task $t, phase $ph)"
      echo "$line" >&2
      bash "$HERE/to-main.sh" question "unit-drive: $UNIT Builder not started" "$line" >/dev/null 2>&1 || true
    fi
    sleep "$poll"
  done
}
launch_wait
watch_unit
ended
pp_gate_done
echo "unit-drive: $UNIT launched its Builder"
echo "DONE unit=$UNIT stage=launch: Builder launched" >&2
