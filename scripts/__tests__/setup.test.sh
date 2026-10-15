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

# --- the default Builder: Opus at effort high, no advisor, a risky build included (owner's default) ---
builder_seat() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR PATH="$BIN:$PATH" bash -c '. "$0" && pp_route_json builder | jq -c "[.model, .effort, .advisor]"' "$PLUGIN/scripts/paths.sh"); }
check "the default Builder is Opus at effort high with no advisor" '["opus","high",null]' "$(builder_seat)"
# #85: a launch that leaves out --advisor gets Claude Code's default advisor; its one off switch is a variable.
OFF=CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1
cmd_of() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR PATH="$BIN:$PATH" "${@:2}" bash -c '. "$0" && pp_route_json "$1" | jq -r ".cmd // (.argv | join(\" \"))"' "$PLUGIN/scripts/paths.sh" "$1"); }
check "a Builder and the headless reviewer launch with the advisor switched off" "1 1" "$(cmd_of builder | grep -c "$OFF") $(cmd_of claude-reviewer | grep -c "$OFF")"
jq '.roles["design-coauthor"].advisor = "opus"' "$PLUGIN/config/routing.json" > "$T/routing.json"
check "a seat that names an advisor keeps it, switched on" "1 0" \
  "$(cmd_of design-coauthor COMMANDECK_ROUTING="$T/routing.json" | grep -c -- '--advisor opus') $(cmd_of design-coauthor COMMANDECK_ROUTING="$T/routing.json" | grep -c "$OFF")"
check "the orchestrator, the owner's own session, has it off in the project's settings" '"1"' "$(jq -c '.env.CLAUDE_CODE_DISABLE_ADVISOR_TOOL' "$PROJ/.claude/settings.json")"
printf '## The issues\n1. #1: toy\n' > "$T/batch.md"
run "$PROJ" builder-launch.sh --dry-run --risky toy-unit "$T/batch.md" >"$T/brief" 2>"$T/err"
check "a risky launch gets no advisor either, and says so" '1:0' "$(grep -c '^advisor: none' "$T/err"):$(grep -c 'advisor consult' "$T/brief")"
check "and its brief keeps the design check" 1 "$(grep -c '^## Design check' "$T/brief")"
check "the brief's first line names no model: the launch may pick another" 1 "$(grep -c '^You are the Builder for `toy-unit`: one pane in your own worktree\.' "$T/brief")"
# An advisor an older set-up stored is not given (owner's order 2026-10-14), and a stored "none" is not
# told to consult one: without --small, both briefs carry the same no-advisor line a --small launch gets.
for a in opus none; do
  jq --arg a "$a" '.builder = {advisor: $a}' "$CFG" > "$T/cfg" && cp "$T/cfg" "$CFG"
  run "$PROJ" builder-launch.sh --dry-run toy-unit "$T/batch.md" >"$T/brief" 2>"$T/err"
  check "a stored advisor '$a', launched without --small: no advisor, and the brief says so" '1:1:0' \
    "$(grep -c '^advisor: none' "$T/err"):$(grep -c '^This build has no advisor\.' "$T/brief"):$(grep -c 'advisor consult' "$T/brief")"
done
jq 'del(.builder)' "$CFG" > "$T/cfg" && cp "$T/cfg" "$CFG"
# The dashboard's issue list is read from the rendered brief. A batch with a title of its own and an issue per
# sub-heading keeps every issue inside "The issues", and the batch's title does not end "## The batch".
printf '# Export batch\n## The issues\n### #3 Export times out\nSee #9 for the old report.\n### #4 Retry the upload\n' > "$T/batch2.md"
run "$PROJ" builder-launch.sh --dry-run toy-unit "$T/batch2.md" >"$T/brief2" 2>"$T/err"
check "a batch's issue sub-headings stay inside The issues; its own title stays inside The batch" '[3,9,4]:1' \
  "$(bash "$PLUGIN/scripts/brief-issues.sh" "$T/brief2" | jq -c .):$(grep -c '^### Export batch$' "$T/brief2")"
# Main writes a "leave as is" ruling under the heading its rules name; the pass reads limits from
# one heading only, so a ruling under any other is raised again as a blocker.
H=$(sed -n 's/.*stays as it is goes under `\(#[^`]*\)`.*/\1/p' "$PLUGIN/templates/main-session.md")
printf '# Rulings\n%s\n- the retry stays as it is.\n## Later\n- not a limit\n' "$H" > "$T/rulings.md"
LIMITS_AWK=$(grep -o "awk '[^']*Stated limits[^']*'" "$PLUGIN/scripts/builder-codex-pass.sh")
check "a 'leave as is' ruling under the heading main's rules name is the limit the pass reads" '- the retry stays as it is.' \
  "$(eval "$LIMITS_AWK \"\$T/rulings.md\"")"
echo "review this" > "$T/spec.md"; mkdir -p "$HOME/orca/workspaces/proj/seat-unit"
run "$PROJ" seat.sh launch claude-reviewer seat-unit "$T/spec.md" >"$T/out" 2>&1
check "a headless role is still refused as a pane seat" "2:1" "$?:$(grep -c 'is not a pane seat' "$T/out")"
# A read-only seat is refused a spec that asks it to write a file, but a verb that ends a clause is prose.
printf 'Write the findings to out.md.\n' > "$T/spec-w.md"; printf 'Read the fenced write). Map: x.md\n' > "$T/spec-p.md"
check "a read-only seat asked to write a file is refused; a clause ending on the verb is not an ask" '1:0' \
  "$(run "$PROJ" seat.sh launch codex-reviewer seat-unit "$T/spec-w.md" 2>&1 | grep -c 'spec asks it to write'):$(run "$PROJ" seat.sh launch codex-reviewer seat-unit "$T/spec-p.md" 2>&1 | grep -c 'spec asks it to write')"

# --- the manifest names every changed path, with what was there before ---
# A hash read off a folder link fails, and the path then compares as unchanged (#80).
check "every path setup left is read for the comparison" '' "$(snap 2>&1 >/dev/null)"
AFTER=$(snap)
NAMED=$(jq -r '.entries | keys[]' "$MF"/*.json | sort -u)
MISSING=$(diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | sed -n 's/^[<>] [0-9a-f]* //p' | sort -u | grep -v '^home/\.commandeck/' \
  | while read -r f; do grep -qxF "$T/$f" <<<"$NAMED" || echo "$f"; done)
check "every file setup changed or made outside its own state folder is in a manifest" '' "$MISSING"
check "a file that was there is recorded by its content hash" "sha256:$(grep ' home/.codex/hooks.json$' <<<"$BEFORE" | cut -d' ' -f1)" \
  "$(jq -r --arg p "$HOME/.codex/hooks.json" '.entries[$p].prior' "$MF/_machine.json")"
check "a file that was not is recorded as such" 'did not exist' "$(jq -r --arg p "$CFG" '.entries[$p].prior' "$(mf "$PROJ")")"
cmp -s "$MF/blobs/$(sha256sum < "$T/hooks-before.json" | cut -d' ' -f1)" "$T/hooks-before.json"; check "the prior bytes are kept, under that hash" 0 $?

# --- a live Builder pane is reused only while the project's Builder settings are the ones it opened with ---
# The Orca stand-in has one pane: the first launch makes it, and it stays live.
SWT=$HOME/orca/workspaces/proj/seat-builder; git -C "$PROJ" worktree add -q "$SWT"
cp "$BIN/orca-ide" "$T/orca-ide.kept"
cat > "$BIN/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "terminal create"*) touch "$T/pane-up"; echo '{"ok":true,"result":{"terminal":{"handle":"h1"}}}' ;;
  "terminal list"*) [ -e "$T/pane-up" ] && t='[{"handle":"h1","agentIdentity":"claude","worktreeId":"w1","worktreePath":"$SWT"}]' || t='[]'
    echo "{\"ok\":true,\"result\":{\"terminals\":\$t}}" ;;
  "orchestration task-create"*) echo '{"ok":true,"result":{"task":{"id":"task_1"}}}' ;;
  "worktree ps --json") echo '{"result":{"worktrees":[]}}' ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
EOF
seat() { COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run "$PROJ" seat.sh launch builder seat-builder "$T/spec.md"; }
jq '.builder = {model: "sonnet"}' "$CFG" > "$T/cfg" && cp "$T/cfg" "$CFG"
seat >"$T/out" 2>&1; check "the first Builder launch opens a pane" 0 $?
seat >"$T/out" 2>&1; check "a second launch on the same settings reuses it" '0:1' "$?:$(grep -c 'state=reused' "$T/out")"
jq 'del(.builder)' "$CFG" > "$T/cfg" && cp "$T/cfg" "$CFG"
seat >"$T/out" 2>&1
check "once the project's Builder model changed, the live pane is refused, and the refusal says why" '2:0:1' \
  "$?:$(grep -c 'state=reused' "$T/out"):$(grep -c 'REFUSED: live builder seat h1 for seat-builder was opened with other launch settings' "$T/out")"
# A pane with no verdict yet whose last lines quote one in a fence is still working: the
# reader prints those lines under "NO VERDICT YET", and reading a verdict there closed the seat.
cat > "$BIN/orca-ide" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "terminal read"*) jq -n '{ok: true, result: {terminal: {tail: "Reviewing.\nThe last line will read:\n```\nVERDICT: GO\n```\nStill reading the diff."}}}' ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
EOF
run "$PROJ" seat.sh collect builder seat-builder >"$T/out" 2>&1
check "a fenced verdict in an unfinished pane's last lines is no verdict" '3:0' "$?:$(grep -c 'closed seat' "$T/out")"
cp "$T/orca-ide.kept" "$BIN/orca-ide"

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

# A path a session prints rides into its checkpoint and outlives an update: it names the stable link, not the versioned folder.
check "setup links ~/.commandeck/plugin to the plugin" "$PLUGIN" "$(readlink "$HOME/.commandeck/plugin")"
check "a session's startup context names the plugin by that link" 1 \
  "$(cd "$PROJ" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN PATH="$BIN:$PATH" bash "$PLUGIN/hooks/agent-startup-context.sh" </dev/null 2>/dev/null | grep -c "^# Commandeck plugin folder: $HOME/.commandeck/plugin\. ")"

# --- the review loop: an owner who takes every default sees no change; numbers are saved as typed ---
check "with every default taken the config holds no review-loop setting" false "$(jq 'has("reviewLoop")' "$CFG")"
run "$PROJ" setup.sh "${ANSWERS[@]}" --max-rounds six >"$T/out" 2>&1
check "a round cap that is not a whole number is refused, and nothing is saved" "1:false" "$?:$(jq 'has("reviewLoop")' "$CFG")"

# --- a second run adds nothing twice and keeps the first run's record ---
jq '.builder = {model: "sonnet", advisor: "opus"}' "$CFG" > "$T/cfg" && cp "$T/cfg" "$CFG"
PLUGIN_DIR=$HOME/.commandeck/plugin run "$PROJ" setup.sh "${ANSWERS[@]}" --name Grace --max-rounds 6 --closing-pass no --small-build 150 --max-review-min 45.50 --max-test-percent 40 --max-usd 25 >"$T/out" 2>&1; check "a second setup succeeds" 0 $?
check "the new answer is taken" Grace "$(jq -r '.chiefOfStaff.name' "$CFG")"
check "a rerun keeps the Builder model an older set-up stored and drops its advisor" '{"model":"sonnet"}' "$(jq -c '.builder' "$CFG")"
check "setup run through the stable link keeps the link on the plugin" "$PLUGIN" "$(readlink "$HOME/.commandeck/plugin")"
run "$PROJ" update.sh >"$T/out" 2>&1; check "an update with the link recorded succeeds" 0 $?
check "and keeps the link" "$PLUGIN" "$(readlink "$HOME/.commandeck/plugin")"
check "the review-loop answers are saved as typed" '{"maxRounds":"6","closingPass":"no","smallBuild":"150","maxReviewMinutes":"45.50","maxTestPercent":"40","maxUsd":"25"}' "$(jq -c '.reviewLoop' "$CFG")"
run "$PROJ" builder-launch.sh --dry-run toy-unit "$T/batch.md" >"$T/brief" 2>"$T/err"
check "a Builder's brief carries them: the small-build line, the round cap, no closing pass" '1:1:1' \
  "$(grep -c 'under 150 changed lines' "$T/brief"):$(grep -c 'at most 6 rounds' "$T/brief"):$(grep -c 'This project runs no closing pass' "$T/brief")"
check "the build review flags at the saved thresholds" '[45.5, 0.4, 25.0]' \
  "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import collect; print(list(collect.loop_limits(sys.argv[2])))' "$PLUGIN/skills/worktreereview/scripts" "$PROJ")"
check "still five Codex entries" 5 "$(ours)"
check "still one block in the instruction file" 1 "$(grep -c '^<!-- commandeck:begin -->$' "$PROJ/AGENTS.md")"
check "the manifest still records what was there before the first run" 'did not exist' "$(jq -r --arg p "$CFG" '.entries[$p].prior' "$(mf "$PROJ")")"

# --- the global CLAUDE.md template and the rules: offered, never written over the owner's file unasked ---
G=$HOME/.claude/CLAUDE.md
printf '# Mine\n\nKeep it short.\n' > "$G"
# A saved setting the loop refuses is repaired by answering again: setup's own check reads the new answers.
jq '.reviewLoop.smallBuild = "lots"' "$CFG" > "$T/cfg" && cp "$T/cfg" "$CFG"
run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1
check "a saved setting the loop refuses, not answered again, fails setup and names it" "1:1" "$?:$(grep -c 'reviewLoop.smallBuild = "lots"' "$T/out")"
run "$PROJ" setup.sh "${ANSWERS[@]}" --global-claude install --global-rules install --max-rounds '' --closing-pass yes --small-build '' --max-review-min '' --max-test-percent '' --max-usd '' >"$T/out" 2>&1; check "install over an existing file succeeds" 0 $?
check "the review-loop answers taken back to the defaults leave no setting" false "$(jq 'has("reviewLoop")' "$CFG")"
check "and leaves the owner's file exactly as it was, saying how to add a block" '# Mine||Keep it short.|2' \
  "$(paste -sd'|' - < "$G")|$(grep -c "^global .*: $G exists, left as it is; to add it as a marked block: --global-.* block$" "$T/out")"
# #87: off is an answer of its own, saved as the word: for the flag set, and for each flag.
run "$PROJ" setup.sh "${ANSWERS[@]}" --review-flags off >"$T/out" 2>&1
check "--review-flags off saves each review flag as off" '0:{"maxReviewMinutes":"off","maxTestPercent":"off","maxUsd":"off"}' "$?:$(jq -cS .reviewLoop "$CFG")"
run "$PROJ" setup.sh "${ANSWERS[@]}" --max-review-min '' --max-test-percent 40 --max-usd off >"$T/out" 2>&1
check "one flag back to its default, one a number, one off" '0:{"maxTestPercent":"40","maxUsd":"off"}' "$?:$(jq -cS .reviewLoop "$CFG")"
run "$PROJ" setup.sh "${ANSWERS[@]}" --small-build off >"$T/out" 2>&1
check "small build has no off, and says what to use" "1:1" "$?:$(grep -c 'no off: 1 makes no build small' "$T/out")"
run "$PROJ" setup.sh "${ANSWERS[@]}" --max-test-percent '' --max-usd '' >"$T/out" 2>&1; check "and back to the defaults" "0:false" "$?:$(jq 'has("reviewLoop")' "$CFG")"
run "$PROJ" setup.sh "${ANSWERS[@]}" --global-claude block --global-rules block >"$T/out" 2>&1; check "adding both as blocks succeeds" 0 $?
run "$PROJ" setup.sh "${ANSWERS[@]}" --global-claude block --global-rules block >"$T/out" 2>&1
check "a second run replaces its blocks: one of each, the owner's text first" '1:1:1' \
  "$(grep -c '^<!-- commandeck:claude-md:begin -->$' "$G"):$(grep -c '^<!-- commandeck:rules:begin -->$' "$G"):$(head -1 "$G" | grep -c '^# Mine$')"
check "the blocks hold the shipped templates" '1:1' "$(grep -c '^## Rule 12 - Fail loud$' "$G"):$(grep -c '^- "Create a PR" is a request' "$G")"
run "$PROJ" setup.sh "${ANSWERS[@]}" --global-rules skip >"$T/out" 2>&1
check "skip changes nothing already there" 1 "$(grep -c '^<!-- commandeck:rules:begin -->$' "$G")"
run "$PROJ" uninstall.sh >"$T/out" 2>&1; check "uninstall succeeds" 0 $?
check "uninstall takes out only the plugin's blocks" '# Mine||Keep it short.' "$(paste -sd'|' - < "$G")"
rm "$G"
run "$PROJ" setup.sh "${ANSWERS[@]}" --global-claude install --global-rules install >"$T/out" 2>&1; check "install with no file succeeds" 0 $?
check "it creates the file with both blocks" '1:1' "$(grep -c '^<!-- commandeck:claude-md:end -->$' "$G"):$(grep -c '^<!-- commandeck:rules:end -->$' "$G")"
run "$PROJ" uninstall.sh >/dev/null 2>&1
check "and uninstall removes the file it created" no "$([ -e "$G" ] && echo yes || echo no)"

[ "$FAIL" = 0 ] || { echo "--- last output"; tail -15 "$T/out"; }
done_tests
