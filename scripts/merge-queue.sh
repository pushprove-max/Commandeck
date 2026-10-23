#!/usr/bin/env bash
# merge-queue.sh [--train] <unit>[@<sha>] ... -- run merge-unit-local.sh for each unit in order,
# one at a time, stopping at the first failure, merged (a step after its commit
# failed) or not. <unit>@<sha> merges with --auto <sha>: only while
# the unit's tip is still the commit its gate passed.
# --train (issue 307): every unit given as <unit>@<sha>. The units are squashed in order on a scratch copy of main, the
# project's check runs once on the combined tip, and on green each unit merges in
# order as it would alone: its own check runs unless its closing pass's run stands
# (issue 307's rule), never on the train's run, which tested a tree it is not; a unit
# merged with a later step failed (3, 5) does not stop it. A unit the real merge refuses stops the queue there, named,
# with nothing of it merged (issue 306: the train runs no dry-run pass). On red the train is bisected to the
# first unit that turns it red: the units before it merge, it is named, and the ones
# after it wait.
# Logs: <scratch>/merge-<unit>.log, <scratch>/merge-train.log (paths.sh PP_SCRATCH)
# Self-test: bash scripts/__tests__/merge-queue.test.sh
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
USAGE="usage: merge-queue.sh [--train] <unit>[@<sha>] ..."
TRAIN=0; [ "${1:-}" != --train ] || { TRAIN=1; shift; }
[ $# -gt 0 ] || { echo "$USAGE" >&2; exit 2; }
for arg in "$@"; do
  [[ $arg =~ ^[A-Za-z0-9._-]+(@[0-9a-f]{7,40})?$ ]] && { [ "$TRAIN" = 0 ] || [[ $arg == *@* ]]; } \
    || { echo "merge-queue: not a <unit> or <unit>@<sha> (--train takes each with its sha): $arg" >&2; echo "$USAGE" >&2; exit 2; }
done
ROOT=$(git rev-parse --show-toplevel) || exit 1
COMMANDECK_MAIN=$ROOT . "$HERE/paths.sh" || exit 1
mkdir -p "$PP_SCRATCH" || exit 1
# Each merge's exit is what the queue goes on: in main's foreground the queue detaches itself (issue 230), and its
# merges run in its own foreground, never detached.
# --train was shifted off above; the detached queue gets it back.
if pp_main_foreground; then
  [ "$TRAIN" = 0 ] || set -- --train "$@"
  pp_detach "$PP_SCRATCH/merge-queue.log" "merge-queue.sh $*" bash "$0" "$@"; exit
fi
export COMMANDECK_FOREGROUND=1
LATE=0

queue() { # <unit>[@<sha>] ...: merge each in order; returns 1 at the first that did not merge cleanly
  local arg unit log rc
  for arg in "$@"; do
    unit=${arg%@*}
    # Appended, never emptied: a merge of this unit may be writing it now, and a request that turns out a duplicate
    # (exit 4) must leave its steps in place (issue 317).
    log=$PP_SCRATCH/merge-$unit.log
    if [[ $arg == *@* ]]; then "$HERE/merge-unit-local.sh" "$unit" --auto "${arg#*@}" >> "$log" 2>&1; rc=$?
    else "$HERE/merge-unit-local.sh" "$unit" >> "$log" 2>&1; rc=$?; fi
    # 3 and 5 are a unit that merged and then failed a later step: merging it again would merge it twice. A train
    # goes on past it: each unit after it is checked or reused on its own tree, as it would be alone.
    if { [ "$rc" = 3 ] || [ "$rc" = 5 ]; } && [ "$TRAIN" = 1 ]; then
      echo "merge-queue: $unit MERGED, but a step after the merge commit failed or was refused (exit $rc); finish it by hand, do not merge it again; the train goes on; log: $log" >&2
      tail -n 3 "$log" >&2; LATE=1; continue
    fi
    if [ "$rc" != 0 ]; then
      if [ "$rc" = 3 ] || [ "$rc" = 5 ]; then echo "merge-queue: STOPPED at $unit (MERGED, but a step after the merge commit failed or was refused; finish it by hand, do not merge it again); log: $log" >&2
      else echo "merge-queue: STOPPED at $unit (not merged); log: $log" >&2; fi
      tail -n 3 "$log" >&2
      return 1
    fi
    echo "merge-queue: $unit merged; $(tail -n 1 "$log" | cut -c1-160)"
  done
}

if [ "$TRAIN" = 1 ]; then
  CHECK_CMD=$(jq -r '.testCommand // empty' "$ROOT/.claude/commandeck.json" 2>/dev/null || true)
  TLOG=$PP_SCRATCH/merge-train.log
  COPY=$(mktemp -d) || exit 1
  trap 'git -C "$ROOT" worktree remove --force "$COPY/tree" >/dev/null 2>&1; pp_rm_rf "$COPY"; git -C "$ROOT" worktree prune' EXIT
  git -C "$ROOT" worktree add -q --detach "$COPY/tree" main >/dev/null 2>&1 || { echo "merge-queue: could not make the train's scratch copy of main" >&2; exit 1; }
  pp_link_node_modules "$ROOT" "$COPY/tree"
  # One commit per unit, each the squash of the unit's sha on the ones before it: STEP[k] is the tree main will
  # hold once the first k units merge.
  STEP=("$(git -C "$COPY/tree" rev-parse HEAD)")
  for arg in "$@"; do
    git -C "$COPY/tree" merge -q --squash "${arg#*@}" >/dev/null 2>&1 \
      && git -C "$COPY/tree" -c user.name=merge-train -c user.email=merge-train@localhost -c core.hooksPath=/dev/null commit -qm "train: ${arg%@*}" >/dev/null 2>&1 \
      || { echo "merge-queue: train refused, nothing merged: ${arg%@*} does not merge cleanly on top of the units before it" >&2; exit 1; }
    STEP+=("$(git -C "$COPY/tree" rev-parse HEAD)")
  done
  green() { # <commit> <what>: the check on that commit
    git -C "$COPY/tree" checkout -qf --detach "$1" || return 1
    echo "== check on $2: $1" >> "$TLOG"
    (cd "$COPY/tree" && bash -c "$CHECK_CMD") >> "$TLOG" 2>&1
  }
  : > "$TLOG"; N=$#
  if [ -z "$CHECK_CMD" ] || green "${STEP[N]}" "the first $N unit(s)"; then
    echo "merge-train: the combined tip of $N unit(s) is green${CHECK_CMD:+ ($CHECK_CMD)}; merging each in order"
    queue "$@" || exit 1
    echo "merge-queue: all $N unit(s) in the train merged"
    [ "$LATE" = 0 ] || exit 1
    exit 0
  fi
  # Red: the first k whose combined tip is red. LO is green (0, main itself), HI red.
  LO=0 HI=$N
  while [ $((HI - LO)) -gt 1 ]; do
    MID=$(((LO + HI) / 2))
    if green "${STEP[MID]}" "the first $MID unit(s)"; then LO=$MID; else HI=$MID; fi
  done
  ARGS=("$@") BAD=${ARGS[HI-1]%@*}
  [ "$LO" = 0 ] || queue "${ARGS[@]:0:LO}" || exit 1
  echo "merge-queue: train red at $BAD: the combined tip turns red with it (log $TLOG); merged ${LO} unit(s) before it; waiting: $(printf '%s ' "${ARGS[@]:HI}" | sed 's/@[0-9a-f]*//g; s/ $//')" >&2
  exit 1
fi

queue "$@" || exit 1
echo "merge-queue: all $# unit(s) merged"
