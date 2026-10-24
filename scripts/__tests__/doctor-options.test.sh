#!/usr/bin/env bash
# covers: scripts/doctor.sh
# doctor-options.test.sh -- the doctor's option lines (issue 245) and its Builder and review-pass lines, on the
# hand-written commandeck.json of fixtures/doctor-setup.sh. Each /config option, its value and where it comes from,
# so an owner sees which answer runs. The other doctor cases are in doctor.test.sh and doctor-run.test.sh.
set -uo pipefail
. "$(dirname "$0")/fixtures/doctor-setup.sh"
mkdir -p "$HOME/.claude"

# --- issue 245: each /config option, its value and where that comes from, so an owner sees which answer runs ---
echo '{"version": 1, "profile": "claude", "cacheTtl": "5m", "chiefOfStaff": {"name": "r", "cacheTtl": "1h"}}' > "$PROJ/.claude/commandeck.json"
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"builderEffort": "high"}}}}' > "$HOME/.claude/settings.json"
OUT=$(lib il_options_report)
check "the doctor names each option's value and source: /config, the project's file, or the default" '1:1:1' \
  "$(grep -c '^ok option builderEffort: high (from /config)$' <<<"$OUT"):$(grep -c "^ok option promptCacheTtl: 5m (from $PROJ/.claude/commandeck.json)$" <<<"$OUT"):$(grep -c '^ok option maxReviewRounds: none (from the default)$' <<<"$OUT")"
check "one line for each option the manifest declares" "$(jq '.userConfig | length' "$REAL/.claude-plugin/plugin.json")" "$(grep -c '^ok option ' <<<"$OUT")"
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"promptCacheTtl": "leave", "relayPromptCacheTtl": "leave"}}}}' > "$HOME/.claude/settings.json"
check "the cache report follows the /config answers over the project's" 1 "$(cache | grep -c '^ok prompt cache: setup sets none$')"
# Issue 293: the Builder line names where each value comes from, so a launch below the expected effort is traced.
# Issue 312: a builder.model an older setup left in the project's file is not read; the key or routing's default runs.
jq '.builder = {model: "sonnet"}' "$PROJ/.claude/commandeck.json" > "$T/cj" && mv "$T/cj" "$PROJ/.claude/commandeck.json"
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"builderEffort": "high"}}}}' > "$HOME/.claude/settings.json"
check "the doctor's Builder line names the model's source and the effort's, and reads no builder.model from the project's file" 1 \
  "$(in_proj timeout 60 bash "$REAL/scripts/doctor.sh" 2>&1 | tee "$T/doc" | grep -cxF "ok   builder: sonnet (from the default), effort high (from /config); setup.sh --option builderModel=<m> --option builderEffort=<e>, or /plugin config")"
# The review pass the doctor checks runs on the reviewer's agent key, not the profile: a claude-profile project with
# codexReviewerAgent=codex checks the Codex pass, and is not failed for a mismatch.
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"codexReviewerAgent": "codex", "codexReviewerModel": "gpt-6.1-sol"}}}}' > "$HOME/.claude/settings.json"
check "the doctor checks the review pass on the reviewer's agent key, not the profile's" "1 0" \
  "$(in_proj timeout 60 bash "$REAL/scripts/doctor.sh" 2>&1 > "$T/doc"; grep -c 'review pass' "$T/doc") $(grep -c 'puts the reviewer on' "$T/doc")"
rm -f "$HOME/.claude/settings.json"
# Issue 327: main tracks work in the Orca task list, so the harness's task-list reminders are paid for nothing. The doctor
# warns when main's settings turn the task tools on for every model, and otherwise says how they stay off.
echo '{"env": {"CLAUDE_CODE_ENABLE_TODO_TOOLS": "1"}}' > "$PROJ/.claude/settings.local.json"
check "with CLAUDE_CODE_ENABLE_TODO_TOOLS=1 in main's settings env the doctor warns and names the fix" 1 \
  "$(in_proj timeout 60 bash "$REAL/scripts/doctor.sh" 2>&1 | grep -c '^warn main: .*CLAUDE_CODE_ENABLE_TODO_TOOLS=1.*remove it')"
rm -f "$PROJ/.claude/settings.local.json"
OUT=$(in_proj env -u CLAUDE_CODE_ENABLE_TODO_TOOLS timeout 60 bash "$REAL/scripts/doctor.sh" 2>&1)
check "without it the doctor prints the ok line, and no warning" "1:0" \
  "$(grep -c '^ok   main: task-list reminders .*deny TaskCreate' <<<"$OUT"):$(grep -c '^warn main: .*TODO_TOOLS' <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
