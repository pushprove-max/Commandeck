#!/usr/bin/env bash
# setup.test.sh -- setup is the one command between "plugin installed" and a
# working project. What this pins: it takes every answer in one pass and asks
# nothing itself; a failed preflight changes nothing; the manifest names every
# path setup changed, with what was there before; another tool's entries in
# the files it merges into are left exactly as they were; and a second run
# adds nothing twice.
set -uo pipefail
. "$(dirname "$0")/install-fixture.sh"
MF=$HOME/.commandeck/install
CFG=$PROJ/.claude/commandeck.json
ours() { jq '[.hooks[][].hooks[] | select(.command | contains("/hooks/codex-dispatch.sh"))] | length' "$HOME/.codex/hooks.json"; }
BEFORE=$(snap); cp "$HOME/.codex/hooks.json" "$T/hooks-before.json"

# --- a failed preflight changes nothing ---
touch "$T/signed-out"
run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "a signed-out Codex CLI stops setup" 1 $?
check "the refusal says how to sign in" 1 "$(grep -c 'codex login' "$T/out")"
check "and nothing on the machine changed" "$BEFORE" "$(snap)"
rm "$T/signed-out"
run "$PROJ" setup.sh --profile nonsense >"$T/out" 2>&1; check "an unknown profile is refused" 2 $?
check "and nothing changed" "$BEFORE" "$(snap)"

# --- one pass, no questions ---
run "$PROJ" setup.sh "${ANSWERS[@]}" --standard-context >"$T/out" 2>&1; check "setup with every answer given succeeds" 0 $?
check "the config carries version 1 and the answers" '[1,"claude-openai",true,true,"true","Ada","dry and brief"]' \
  "$(jq -c '[.version, .profile, .strictHooks, .standardContext, .testCommand, .chiefOfStaff.name, .chiefOfStaff.persona]' "$CFG")"
check "the project's profile is the one the review pass uses" codex "$(cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR bash -c '. "$0" && pp_pass' "$PLUGIN/scripts/paths.sh")"
check "the project is registered with the dashboard" "$PROJ" "$(cat "$HOME/.commandeck/dashboard/projects")"
check "the dashboard job is installed, local only" 1 "$(grep -c '^Environment="COMMANDECK_DASHBOARD_BIND=127.0.0.1"$' "$HOME/.config/systemd/user/commandeck-dashboard.service")"
check "the project's watcher job is installed" 1 "$(ls "$HOME/.config/systemd/user" | grep -c '^commandeck-main-watch-proj.service$')"
check "setup prints the add-ons as commands" 1 "$(grep -c '^  serena  *claude mcp add' "$T/out")"
check "every add-on has a command: none is a placeholder" 0 "$(grep -c 'no public source' "$T/out")"
check "every add-on has a cost line" "$(grep -vc '^#' "$PLUGIN/config/addons.tsv")" "$(grep -c '^  *cost: .' "$T/out")"
# The ponytail skill is the one add-on setup installs, with the rule that keeps its name out of code comments.
check "setup installs the ponytail skill and no other" 'ponytail' "$(ls "$HOME/.claude/skills" | paste -sd' ' -)"
check "the installed skill is the shipped one" 0 "$(cmp -s "$PLUGIN/templates/ponytail/SKILL.md" "$HOME/.claude/skills/ponytail/SKILL.md"; echo $?)"
check "and it says never to write its name in a comment" '1:0' \
  "$(grep -c 'Never write "ponytail" in a comment' "$HOME/.claude/skills/ponytail/SKILL.md"):$(grep -c '`ponytail:` comment' "$HOME/.claude/skills/ponytail/SKILL.md")"
check "setup says it left the status line alone and how to set one" 1 "$(grep -c '^Status line: left as it is (.*other.sh.*setup.sh --status-line' "$T/out")"

# --- the manifest names every changed path, with what was there before ---
AFTER=$(snap)
NAMED=$(jq -r '.entries | keys[]' "$MF"/*.json | sort -u)
MISSING=$(diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | sed -n 's/^[<>] [0-9a-f]* //p' | sort -u | grep -v '^home/\.commandeck/' \
  | while read -r f; do grep -qxF "$T/$f" <<<"$NAMED" || echo "$f"; done)
check "every file setup changed or made outside its own state folder is in a manifest" '' "$MISSING"
check "a file that was there is recorded by its content hash" "sha256:$(grep ' home/.codex/hooks.json$' <<<"$BEFORE" | cut -d' ' -f1)" \
  "$(jq -r --arg p "$HOME/.codex/hooks.json" '.entries[$p].prior' "$MF/_machine.json")"
check "a file that was not is recorded as such" 'did not exist' "$(jq -r --arg p "$CFG" '.entries[$p].prior' "$(mf "$PROJ")")"
cmp -s "$MF/blobs/$(sha256sum < "$T/hooks-before.json" | cut -d' ' -f1)" "$T/hooks-before.json"; check "the prior bytes are kept, under that hash" 0 $?

# --- another tool's entries are left exactly as they were ---
check "Codex has the plugin's five entries" 5 "$(ours)"
check "the other tool's Codex hooks are still first in their groups" '["/opt/other-tool/hook.sh","/opt/other-tool/end.sh"]' \
  "$(jq -c '[.hooks.PreToolUse[0].hooks[0].command, .hooks.SessionEnd[0].hooks[0].command]' "$HOME/.codex/hooks.json")"
check "the plugin's five entries are trusted" 5 "$(grep -c "^\[hooks.state.\"$HOME/.codex/hooks.json:" "$HOME/.codex/config.toml" | awk '{print $1 - 1}')"
check "the other tool's trust entry and its disabled flag are untouched" 2 "$(grep -A2 'pre_tool_use:0:0' "$HOME/.codex/config.toml" | grep -c 'sha256:0000\|enabled = false')"
check "Codex is told where to send a finished turn" 1 "$(grep -c "^notify = \[\"$PLUGIN/hooks/codex-notify.sh\"\]$" "$HOME/.codex/config.toml")"
check "the project's own permissions and hooks are kept" '["Bash(make:*)","./own-stop.sh"]' \
  "$(jq -c '[.permissions.allow[0], .hooks.Stop[0].hooks[0].command]' "$PROJ/.claude/settings.json")"
check "the plugin's permissions are added to the project (project scope)" true "$(jq '.permissions.allow | any(contains("orca-ide"))' "$PROJ/.claude/settings.json")"
check "the machine's settings are not touched in project scope" "$(grep ' home/.claude/settings.json$' <<<"$BEFORE")" "$(grep ' home/.claude/settings.json$' <<<"$AFTER")"

# --- a second run adds nothing twice and keeps the first run's record ---
run "$PROJ" setup.sh "${ANSWERS[@]}" --name Grace >"$T/out" 2>&1; check "a second setup succeeds" 0 $?
check "the new answer is taken" Grace "$(jq -r '.chiefOfStaff.name' "$CFG")"
check "still five Codex entries" 5 "$(ours)"
check "still one block in the instruction file" 1 "$(grep -c '^<!-- commandeck:begin -->$' "$PROJ/AGENTS.md")"
check "the manifest still records what was there before the first run" 'did not exist' "$(jq -r --arg p "$CFG" '.entries[$p].prior' "$(mf "$PROJ")")"

[ "$FAIL" = 0 ] || { echo "--- last output"; tail -15 "$T/out"; }
done_tests
