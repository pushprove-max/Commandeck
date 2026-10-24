#!/usr/bin/env bash
# covers: scripts/doctor.sh
# doctor-wakes.test.sh -- issue 331: the doctor reads the wake log and fails when the watcher's latest wakes of main
# found no pane. The other doctor cases are in doctor-run.test.sh, doctor.test.sh and doctor-options.test.sh.
set -uo pipefail
. "$(dirname "$0")/fixtures/doctor-setup.sh"

# The line names the first of the unbroken no_pane run, and goes when a wake started a turn.
QD=$(in_proj bash -c '. "$0" && echo "$PP_SCRATCH/queue"' "$REAL/scripts/paths.sh")
WLJ=${QD%/queue}/wake-log.jsonl
mkdir -p "${WLJ%/*}"
wl() { jq -nc --arg at "$1" --arg r "$2" '{at: $at, from: "main-watch", to: "term_main", reason: "wake", result: $r, error: ""}' >> "$WLJ"; }
wl 2026-10-24T09:00:00Z turn_started; wl 2026-10-24T09:10:00Z no_pane; wl 2026-10-24T09:20:00Z no_pane
in_proj timeout 60 bash "$REAL/scripts/doctor.sh" > "$T/doc" 2>&1
check "wakes of main that found no pane: a FAIL naming the first of the run and the way out" 1 \
  "$(grep -c "^FAIL main-watch cannot find main's pane since 2026-10-24T09:10:00Z; set COMMANDECK_MAIN_PANE_DIR if main runs in another checkout" "$T/doc")"
wl 2026-10-24T09:30:00Z turn_started
in_proj timeout 60 bash "$REAL/scripts/doctor.sh" > "$T/doc" 2>&1
check "and a later wake that started a turn takes it away" 0 "$(grep -c "cannot find main's pane" "$T/doc")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
