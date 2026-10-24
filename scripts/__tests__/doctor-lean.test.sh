#!/usr/bin/env bash
# covers: scripts/doctor.sh
# doctor-lean.test.sh -- the doctor's line for main's lean lists (il_main_lean), on the hand-written project of
# fixtures/doctor-setup.sh. Split from doctor-options.test.sh for the shell-test time budget: each case runs the doctor.
set -uo pipefail
. "$(dirname "$0")/fixtures/doctor-setup.sh"
mkdir -p "$HOME/.claude"

# Main's lean lists (il_main_lean): the doctor warns when main's own file no longer turns off what setup turned off.
F=$PROJ/$(lib 'echo $IL_MAIN_LEAN_FILE')
lib 'il_record "$IL_PROJECT" merge "$1" && il_main_lean "$IL_PROJECT" "$1" >/dev/null' "$F"
OUT=$(in_proj timeout 60 bash "$REAL/scripts/doctor.sh" 2>&1)
check "with main's lean keys as setup left them the doctor does not warn" 0 "$(grep -c "^warn main: .*setup turned" <<<"$OUT")"
jq '.enabledPlugins["ui-themes@ui-themes"] = true' "$F" > "$T/sl" && mv "$T/sl" "$F"
# An earlier setup's cut in main's settings.local.json, which every worktree session reads over its own.
lib 'il_record "$IL_PROJECT" merge "$1" && il_main_lean "$IL_PROJECT" "$1" >/dev/null' "$PROJ/.claude/settings.local.json"
OUT=$(in_proj timeout 60 bash "$REAL/scripts/doctor.sh" 2>&1)
check "the doctor warns when main's own file no longer turns ui-themes off after setup turned it off" 1 \
  "$(grep -c '^warn main: setup turned enabledPlugins.ui-themes@ui-themes off' <<<"$OUT")"
check "the doctor warns that an earlier setup's cut in main's settings.local.json reaches every worktree" 1 \
  "$(grep -c '^warn main: an earlier setup turned enabledPlugins.mattpocock-skills@claude-plugins-official off in .*settings.local.json, which every worktree session reads' <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
