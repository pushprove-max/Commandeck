#!/usr/bin/env bash
# covers: scripts/doctor.sh
# doctor-run.test.sh -- the doctor's startup measure and its whole run against main's settings file, on the
# hand-written commandeck.json of fixtures/doctor-setup.sh. The other doctor cases are in doctor.test.sh and
# doctor-options.test.sh.
set -uo pipefail
. "$(dirname "$0")/fixtures/doctor-setup.sh"

# --- the doctor's startup measure takes nothing of the owner's or main's ---
# A message queued for main while it is down is main's to read; an open decision is the owner's to answer.
QD=$(in_proj bash -c '. "$0" && echo "$PP_SCRATCH/queue"' "$REAL/scripts/paths.sh")
mkdir -p "$QD" && echo '{"at":"x","type":"status","subject":"answer","body":"stop this build"}' > "$QD/main.jsonl"
in_proj bash "$REAL/scripts/decision.sh" add doctor-test 'May this build ship?' no chat >/dev/null 2>&1
in_proj bash "$REAL/scripts/startup-size.sh" >/dev/null 2>&1; in_proj bash "$REAL/scripts/startup-size.sh" --per-prompt >/dev/null 2>&1
check "the doctor's startup measure leaves the owner's open decision open" null \
  "$(in_proj bash "$REAL/scripts/decision.sh" list 2>/dev/null | jq '.[] | select(.id == "doctor-test") | .answeredAt')"
check "and main's queued messages where they are" 1 "$(grep -c 'stop this build' "$QD/main.jsonl" 2>/dev/null)"

# --- main's settings file against the orchestrator key, in the doctor's whole run ---
# The project's file as doctor-options.test.sh leaves it before its Builder line: a claude profile, an old builder.model.
mkdir -p "$HOME/.claude"
echo '{"version": 1, "profile": "claude", "cacheTtl": "5m", "chiefOfStaff": {"name": "r", "cacheTtl": "1h"}}' > "$PROJ/.claude/commandeck.json"
jq '.builder = {model: "sonnet"}' "$PROJ/.claude/commandeck.json" > "$T/cj" && mv "$T/cj" "$PROJ/.claude/commandeck.json"
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"orchestratorModel": "opus", "orchestratorEffort": "high"}}}}' > "$HOME/.claude/settings.json"
echo '{"model": "opus", "effortLevel": "medium"}' > "$PROJ/.claude/settings.local.json"
check "main's settings file differing from the orchestrator key is flagged, the matching one is not" "1 0" \
  "$(in_proj timeout 60 bash "$REAL/scripts/doctor.sh" 2>&1 > "$T/doc"; grep -c 'main: orchestratorEffort is high in /plugin config, but .* sets medium' "$T/doc") $(grep -c 'main: orchestratorModel' "$T/doc")"
rm -f "$PROJ/.claude/settings.local.json" "$HOME/.claude/settings.json"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
