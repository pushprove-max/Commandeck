#!/usr/bin/env bash
# unit-drive.sh start [--dry-run] <unit> <author-spec> <judge-spec> [<batch>] -- carry a unit from plan to Builder launch
# with no main turn between (issue 443): tier, plan-author, the plan loop (#559), builder-launch.sh --from-plan.
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
  local f add=()
  for f in "$BATCH" "$ASPEC" "$JSPEC"; do [ -s "$f" ] || { echo "REFUSED: $UNIT: no file at $f" >&2; exit 2; }; done
  grep -q '^Order:[[:space:]]*[^[:space:]]' "$BATCH" || { echo "REFUSED: $BATCH has no 'Order: <the owner's words>' line: main copies the owner's order into it" >&2; exit 2; }
  grep -qxF "Launch: new unit $UNIT" "$ASPEC" || { echo "REFUSED: $ASPEC has no 'Launch: new unit $UNIT' line: seat.sh opens the plan author only on the order's Launch and Order lines" >&2; exit 2; }
  grep -q '^Launch:' "$BATCH" || add+=("Launch: new unit $UNIT")
  grep -qE '^#+[[:space:]]+Plan([[:space:]]|$)' "$BATCH" || add+=("" "## Plan" "" ".claude/plans/$UNIT.md")
  if [ "$DRY" = 1 ]; then
    [ "${#add[@]}" = 0 ] || printf 'would append to %s: %s\n' "$BATCH" "$(printf '%s|' "${add[@]}")"
    return 0
  fi
  [ "${#add[@]}" = 0 ] || { { echo; printf '%s\n' "${add[@]}"; } >> "$BATCH"; printf 'appended to %s: %s\n' "$BATCH" "$(printf '%s|' "${add[@]}")"; }
}

stop() { # <stage> <why> <next>: the one stop line, kept in the done file and sent to main once
  local line
  line=$(printf 'STOP unit=%s stage=%s: %s; next: %s' "$UNIT" "$1" "$2" "$3")
  printf '%s\n' "$line" > "$DONE"
  echo "unit-drive: STOP $UNIT at $1: $2" >&2
  bash "$HERE/to-main.sh" question "unit-drive: $UNIT stopped at $1" "$line" >/dev/null 2>&1 || true
  exit 1
}

if [ "$CMD" = start ]; then
  BATCH=$(abs "$BATCH" 2>/dev/null) || BATCH=$BATCH
  AGAIN="bash $HERE/unit-drive.sh start $UNIT $(abs "$ASPEC" 2>/dev/null || echo "$ASPEC") $(abs "$JSPEC" 2>/dev/null || echo "$JSPEC") $BATCH"
  if [ "$DRY" = 1 ]; then
    preflight
    printf 'stages: tier (plan-tier.sh), plan-author, then per plan version: question pause, the judges the tier names together, a revision unless every judge says GO; then builder-launch.sh --from-plan %s %s\n' "$UNIT" "$BATCH"
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
  # Named before the preflight, so a start refused at the lock meanwhile names this one; a refused preflight clears it.
  printf '%s\n' "$NAME" > "$OWNF"
  trap 'rm -f "$OWNF"' EXIT
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
  flock -u 9
  echo "unit-drive: $UNIT driven by $NAME; a stop lands in $DONE; resume after a stop: $AGAIN"
  exit 0
fi

# run: the owner file names this service, checked again under the lock, so a start that lost the race runs nothing.
[ -n "$OWNER" ] && [ "$(cat "$OWNF" 2>/dev/null)" = "$OWNER" ] || { echo "REFUSED: $UNIT is driven by $(owner_of)" >&2; exit 2; }
exec 9>>"$LOCK"
flock 9
[ "$(cat "$OWNF" 2>/dev/null)" = "$OWNER" ] || { echo "REFUSED: $UNIT is driven by $(owner_of)" >&2; exit 2; }
trap 'rm -f "$OWNF"' EXIT
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
  case $rc in 0|1) ;; *) stop "$1" "seat.sh run $1 ended with no verdict (rc $rc)" "$AGAIN" ;; esac
}

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
qsection() { awk '/^## Question for the owner/ && !s { s = 1; next } s && /^## / { exit } s' "$PLANF"; }
# The plan's Question section is open unless it is absent, empty, or ONE paragraph whose first line starts `None:` with
# no list, number or quote line in it; every other shape is open.
qopen() {
  awk '/^## Question for the owner/ && !s { s = 1; next } s && /^## / { exit }
    s && NF == 0 { if (n) gap = 1; next }
    s { if (gap || $0 ~ /^[[:space:]]*([-*+>]|[0-9]+[.)])/ || (n == 0 && $0 !~ /^[[:space:]]*None:/)) bad = 1; n++ }
    END { exit !(n && bad) }' "$PLANF"
}
revise() { # <spec>: the plan-author seat on the spec; a revision that leaves the plan unchanged stops
  at revise
  local rc=0; COMMANDECK_SEAT_FORCE=1 bash "$HERE/seat.sh" run plan-author "$UNIT" "$1" --marker PLAN-DONE >&2 || rc=$?
  [ "$rc" = 0 ] || stop revise "the revise run of plan-author ended with rc $rc, not PLAN-DONE" "$AGAIN"
  [ "$(hash_plan || true)" != "$H" ] || stop revise "the revision left the plan unchanged (sha256 $H)" "$AGAIN"
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
  local J rc i p fail= failwhy= L=() P=()
  for J in "$@"; do
    at "launch $J"; rc=0; bash "$HERE/seat.sh" launch "$J" "$UNIT" "$JS" > "$(rlog "$J")" 2>&1 || rc=$?
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
      *) p="collect failed (rc $rc)" ;;
    esac
    at "collect $J" "rc $rc"
    [ -n "$fail" ] || { fail=$J failwhy="$J: $p"; }
  done
  # Every launched judge is collected first, so a restart reruns only the one that failed.
  [ -z "$fail" ] || stop judge "$failwhy" "$AGAIN"
}
question_gate() { # an open Question section waits for the owner's answer, recorded after this version was asked
  qopen || return 0
  local ah= ae= list ans rc=0 REV
  read -r ah ae < "$ASKED" 2>/dev/null || true
  if [ "$ah" != "$H" ] || [[ ! $ae =~ ^[0-9]+$ ]]; then
    ae=$(date +%s)
    bash "$HERE/to-main.sh" question "unit-drive: $UNIT asks the owner (plan ${H:0:8})" "$(qsection)"$'\n\n'"Put it to the owner as decision plan-$UNIT; the driver waits for the answer." >/dev/null 2>&1 || rc=$?
    case $rc in 0|3) ;; *) stop question "main could not be sent the question in $PLANF (to-main.sh rc $rc)" "put the plan's Question section to the owner as decision plan-$UNIT, then $AGAIN" ;; esac
    printf '%s %s\n' "$H" "$ae" > "$ASKED"
  fi
  at question
  while :; do
    list=$(bash "$HERE/decision.sh" list 2>"$PP_SCRATCH/drive-$UNIT.decision") \
      || stop question "decision.sh list failed: $(head -1 "$PP_SCRATCH/drive-$UNIT.decision")" "$AGAIN"
    # Only an answer at or after the ask counts: the ledger keeps one row per id, so an older round's never releases it.
    ans=$(jq -r --arg id "plan-$UNIT" --argjson b "$ae" \
      '[.[] | select(.id == $id and ((.answeredAt // "" | try fromdateiso8601 catch 0) >= $b))] | last | .answer // empty' <<<"$list") \
      || stop question "the decisions ledger could not be read" "$AGAIN"
    [ -z "$ans" ] || break
    sleep "${COMMANDECK_LOOP_POLL_SECONDS:-30}"
  done
  at question answered
  REV=$PP_MAIN/.claude/briefs/_$UNIT-plan-revise-${H:0:12}.md
  mkdir -p "$(dirname "$REV")"
  { grep -m1 '^Order:' "$ASPEC" || true; echo "Launch: new unit $UNIT"; echo
    echo "# $UNIT: revise the plan on the owner's answer"
    echo
    echo "The owner answered decision plan-$UNIT: $ans"
    echo
    echo "Revise $PLANF: write the answer into the plan's Decisions, add a Plan change log line for each change, and make the section under the \`## Question for the owner\` heading read \`None: answered as D<n>\`. End with PLAN-DONE on a line of its own."
  } > "$REV" || stop question "could not write the revise spec $REV" "$AGAIN"
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
    [ -s "$RP" ] && [ -r "$RP" ] || stop judge "no report of $J's verdict at $RP" "rerun $J on this version (COMMANDECK_SEAT_FORCE=1 seat.sh run $J $UNIT $JS), then $AGAIN"
    QS+=$(qlines "$RP") || stop judge "the report $RP cannot be read" "$AGAIN"
  done
  [ "$PASS" = 0 ] || [ -n "$QS" ] || break
  # A NO-GO, or a GO asking the owner something: a revision carrying every finding, judged again next pass.
  REV=$PP_MAIN/.claude/briefs/_$UNIT-plan-revise-${H:0:12}.md
  mkdir -p "$(dirname "$REV")"
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
    for J in $JUDGES; do grep -iE '\[P[0-3]\]|question for the owner:' "$(report_of "$J")" || true; done
  } > "$REV" || stop revise "could not write the revise spec $REV" "$AGAIN"
  revise "$REV"
done
at launch
LOUT=$(bash "$HERE/builder-launch.sh" --from-plan "$UNIT" "$BATCH" 2>&1) \
  || stop launch "builder-launch.sh refused: $(grep -m1 -E 'REFUSED|failed' <<<"$LOUT" || tail -1 <<<"$LOUT")" "fix that, then $AGAIN"
printf '%s\n' "$LOUT" >&2
echo "unit-drive: $UNIT launched its Builder"
