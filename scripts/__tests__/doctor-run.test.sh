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
# The one doctor run of these files that measures (the fixture skips it): both modes, through the doctor.
in_proj env COMMANDECK_DOCTOR_SIZE= timeout 60 bash "$REAL/scripts/doctor.sh" > "$T/doc" 2>&1
check "the doctor measures the hooks' output" 1 "$(grep -c '^ok   hook output: session start and per prompt are under 10240 bytes$' "$T/doc")"
check "the doctor's startup measure leaves the owner's open decision open" null \
  "$(in_proj bash "$REAL/scripts/decision.sh" list 2>/dev/null | jq '.[] | select(.id == "doctor-test") | .answeredAt')"
check "and main's queued messages where they are" 1 "$(grep -c 'stop this build' "$QD/main.jsonl" 2>/dev/null)"

# --- issue 314: a doctor-only run updates Codex when a newer one is out, and reports the update check ---
# Update check off in the Codex config; installed 0.40.0, latest 0.41.0 (fakes of fixtures/doctor-setup.sh).
{ echo 'check_for_update_on_startup = false'; cat "$CFG"; } > "$T/cfg" && mv "$T/cfg" "$CFG"
echo 0.40.0 > "$T/codex-version"; echo "echo 0.41.0 > $T/codex-version" > "$T/codex-update"; : > "$T/codex-log"
in_proj timeout 60 bash "$REAL/scripts/doctor.sh" > "$T/doc" 2>&1; RC1=$?
check "a doctor-only run updates Codex once and reports the check off and the update" "update:1:1" \
  "$(paste -sd' ' "$T/codex-log"):$(grep -c '^ok   codex update check: off' "$T/doc"):$(grep -c '^ok   codex: updated 0.40.0 -> 0.41.0 (codex update)$' "$T/doc")"
echo 0.40.0 > "$T/codex-version"; echo 'echo "installer broke" >&2; exit 1' > "$T/codex-update"; : > "$T/codex-log"
in_proj timeout 60 bash "$REAL/scripts/doctor.sh" > "$T/doc" 2>&1; RC2=$?
check "a failed update is a warn, not a FAIL: the exit code is the passing run's" "update:1:$RC1" \
  "$(paste -sd' ' "$T/codex-log"):$(grep -c '^warn codex: update 0.40.0 -> 0.41.0 FAILED (installer broke); Codex stays on 0.40.0' "$T/doc"):$RC2"
echo 0.41.0 > "$T/codex-version"; : > "$T/codex-update"

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
