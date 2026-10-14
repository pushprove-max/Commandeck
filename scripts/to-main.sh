#!/usr/bin/env bash
# to-main.sh [--unit <unit>] <type> <subject> <body> -- send one message to main
# (or to the Builder of <unit>), the one way a script or the relay reaches it.
# The pane is looked up by its worktree at send time (pp_pane_of), never taken
# from a saved handle: a restart gives the pane a new one, and a send to the old
# handle is lost. With no live pane the message is queued, and the pane's next
# session shows it first (inbox-drain.sh, at session start). Exit 0: sent;
# 3: queued, said on stderr; 1: the send failed.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
KEY=main WT=$PP_MAIN WHO=main
if [ "${1:-}" = --unit ]; then
  [[ ${2:-} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "to-main: --unit takes a unit name" >&2; exit 2; }
  # unit-<name>: a Builder named "main" must not share main's queue.
  KEY=unit-$2 WT=$PP_WORKSPACES/$2 WHO="the Builder of $2"; shift 2
fi
[ $# = 3 ] || { echo "usage: to-main.sh [--unit <unit>] <type> <subject> <body>" >&2; exit 2; }
H=$(pp_seat_pane "$KEY" "$WT")
if [ -z "$H" ]; then
  mkdir -p "$PP_SCRATCH/queue" && jq -cn --arg at "$(date +%FT%T)" --arg t "$1" --arg s "$2" --arg b "$3" '{at: $at, type: $t, subject: $s, body: $b}' >> "$PP_SCRATCH/queue/$KEY.jsonl" \
    || { echo "to-main: $WHO is not running, and the message could not be queued: it is lost" >&2; exit 1; }
  echo "to-main: $WHO is not running; message queued ($PP_SCRATCH/queue/$KEY.jsonl), shown first when it starts again" >&2
  exit 3
fi
orca-ide orchestration send --to "$H" --type "$1" --subject "$2" --body "$3" --json 2>/dev/null | jq -e '.ok' >/dev/null \
  || { echo "to-main: the send to $WHO ($H) failed; the message was not delivered" >&2; exit 1; }
echo "to-main: sent to $WHO ($H)"
