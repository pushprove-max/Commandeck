#!/usr/bin/env bash
# unit-drive.sh start [--dry-run] <unit> <author-spec> <judge-spec> [<batch>] -- carry a unit from plan to Builder launch
# with no main turn between (issue 443): tier, plan-author, one judge round, builder-launch.sh --from-plan.
# The batch is <batch> or <main>/.claude/briefs/<unit>-batch.md, resolved once and exported to every stage as
# COMMANDECK_BATCH, beside COMMANDECK_DRIVER=1 (a driven seat sends main no wake of its own).
# start fixes or refuses everything once, before any seat: a missing Launch line or Plan section is appended to the
# batch; a missing batch, spec or Order line is refused. Then it starts `run` as the service drive-<unit>-<epoch>.
# --dry-run prints the preflight result and the stages, and creates nothing.
# run --owner <service> ... -- the stages. Tier runs plan-tier.sh on the batch first; the later stages run only the
# roles its `seat:` lines name (plan-author, then each judge: Sol, Fable when Sol is off, both on Panel, none for One
# planner). Each stage is skipped when its seat record already holds its result, so a re-run of start resumes and never
# runs a second judge round. Exit 2 from plan-tier.sh stops at tier. `No plan` starts no seat and no Builder: the stop
# line hands main `builder-launch.sh --skip-plan`. A judge NO-GO, a failed stage or a refused launch is a stop: one
# `STOP unit=<u> stage=<s>: <why>; next: <command>` line in $PP_SCRATCH/unit-loop-<unit>.done, which the driver also
# sends to main itself (plugin main-watch posts no done file). After a NO-GO main writes <main>/.claude/briefs/
# <unit>-main-rulings.md and runs start again; the launcher decides whether those rulings stand in for a revision.
# A crashed run is not resumed inside a stage: its log names the stage, and the next start repeats only that one.
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
RULINGS=$PP_MAIN/.claude/briefs/$UNIT-main-rulings.md
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
    printf 'stages: tier (plan-tier.sh), plan-author, one judge round (the seats the tier names), builder-launch.sh --from-plan %s %s\n' "$UNIT" "$BATCH"
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

at() { echo "unit-drive: $UNIT stage $1" >&2; }
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
NOGO=
for J in $(grep -v "^plan-author\$" <<<"$ROLES" || true); do
  seat_stage "$J" "$JSPEC"
  case $(rec "$J" verdict) in "VERDICT: GO"|"VERDICT: GO "*) ;; *) NOGO="$NOGO $J" ;; esac
done
for J in $NOGO; do
  # Main's rulings count only when written after every judge that said NO-GO.
  [ -s "$RULINGS" ] && [ "$RULINGS" -nt "$PP_SCRATCH/seat-$UNIT-$J.txt" ] \
    || stop judge "$J returned $(rec "$J" verdict) on $PLANF" "main rules on the findings in $RULINGS, then $AGAIN"
  echo "plan: $J returned NO-GO; main's rulings are written, the launcher decides whether they stand in for a revision" >&2
done
at launch
LOUT=$(bash "$HERE/builder-launch.sh" --from-plan "$UNIT" "$BATCH" 2>&1) \
  || stop launch "builder-launch.sh refused: $(grep -m1 -E 'REFUSED|failed' <<<"$LOUT" || tail -1 <<<"$LOUT")" "fix that, then $AGAIN"
printf '%s\n' "$LOUT" >&2
echo "unit-drive: $UNIT launched its Builder"
