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
# They name this machine's plugin folder, so they go in the file git never sees (finding 13), not the committed one.
check "the plugin's permissions are added to the project (project scope), outside git" 'true:false:0' \
  "$(jq '.permissions.allow | any(contains("orca-ide"))' "$PROJ/.claude/settings.local.json"):$(jq '.permissions.allow | any(contains("orca-ide"))' "$PROJ/.claude/settings.json"):$(git -C "$PROJ" status --porcelain -- .claude/settings.local.json | wc -l | tr -d ' ')"
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
  "$(paste -sd'|' - < "$G")|$(grep -c "^global .*: $G exists, left as it is; to add it as a marked block: --global-.* block, or only what it lacks: --global-.* merge$" "$T/out")"
# #87: off is an answer of its own, saved as the word: for the flag set, and for each flag.
run "$PROJ" setup.sh "${ANSWERS[@]}" --review-flags off >"$T/out" 2>&1
check "--review-flags off saves each review flag as off" '0:{"maxReviewMinutes":"off","maxTestPercent":"off","maxUsd":"off"}' "$?:$(jq -cS .reviewLoop "$CFG")"
run "$PROJ" setup.sh "${ANSWERS[@]}" --max-review-min '' --max-test-percent 40 --max-usd off >"$T/out" 2>&1
check "one flag back to its default, one a number, one off" '0:{"maxTestPercent":"40","maxUsd":"off"}' "$?:$(jq -cS .reviewLoop "$CFG")"
# Small build off (owner ruling 2026-10-15): saved as the word, and a Builder's brief says no first pass is one reviewer.
run "$PROJ" setup.sh "${ANSWERS[@]}" --small-build off >"$T/out" 2>&1
check "small build off is saved as the word" '0:"off"' "$?:$(jq -c .reviewLoop.smallBuild "$CFG")"
run "$PROJ" builder-launch.sh --dry-run toy-unit "$T/batch.md" >"$T/brief" 2>"$T/err"
check "and the brief says the first pass is never one reviewer" '1:0' "$(grep -c 'three reviewers at once, never one: this project turned the small build off' "$T/brief"):$(grep -c 'under off' "$T/brief")"
run "$PROJ" setup.sh "${ANSWERS[@]}" --max-test-percent '' --max-usd '' --small-build '' >"$T/out" 2>&1; check "and back to the defaults" "0:false" "$?:$(jq 'has("reviewLoop")' "$CFG")"
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
check "and uninstall removes the file it created, with no copy of it left" 'no:0' "$([ -e "$G" ] && echo yes || echo no):$(ls "$HOME/.claude" | grep -c 'CLAUDE.md.commandeck-bak')"

# --- 0.7.0 setup: a plan that writes nothing, and each answer for the owner's own rule files ---
# one1 <template> <n> -- its nth one-line top-level bullet that names no path the session hook rewrites.
one1() { awk '/^- / && !/scripts\/|hooks\/|templates\/|200K/ { if (p) print p; p = $0; next } { if (p && ($0 == "" || /^- /)) print p; p = "" }' "$1" | sed -n "${2}p"; }
S1=$(one1 "$PLUGIN/templates/AGENT_STARTUP.md" 1)
MS() { awk '/^## Details \(not injected\)/ {exit} 1' "$PLUGIN/templates/main-session.md"; }   # the part sessions load
M1=$(one1 <(MS) 1)
# Another rule sessions load, by its id and its first line (merge-rules.py --units), for the drop below.
U=$(python3 "$PLUGIN/scripts/merge-rules.py" <(MS) --units | awk -F'\t' -v m="$M1" 'length($2) < 100 && $2 ~ /^- / && $2 != m && $2 !~ /scripts\/|hooks\/|templates\/|200K/' | head -1)
ID=${U%%$'\t'*} M2=${U#*$'\t'}
G1=$(one1 "$PLUGIN/templates/global-rules.md" 1)
P2=$T/proj2; project "$P2"; M2F=$(mf "$P2"); Q=$P2/.git/commandeck-setup-questions
printf '# Our startup\n\n- Run make before you push.\n%s\n' "$S1" > "$P2/AGENT_STARTUP.md"
printf 'Our persona.\n\n## Ours\n\n- Main merges.\n\n## Details (not injected)\n\nLong notes.\n' > "$P2/.claude/main-session.md"
mkdir -p "$P2/.claude/rules"; printf '# House\n\n%s\n' "$M1" > "$P2/.claude/rules/house.md"
git -C "$P2" add -A && git -C "$P2" -c user.name=t -c user.email=t@t commit -qm own
printf '# Mine\n\n%s\n' "$G1" > "$G"
printf '#!/usr/bin/env bash\necho "$PWD $*" >> %q\n[ ! -e %q ]\n' "$T/claude.log" "$T/claude-fails" > "$BIN/claude"
STARTUP() { (cd "$P2" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN PATH="$BIN:$PATH" bash "$PLUGIN/hooks/agent-startup-context.sh" </dev/null 2>/dev/null); }
ASK=(--own-startup merge --own-main-session replace --rules merge --global-rules merge --addons serena --cache-ttl recommended)

run "$P2" setup.sh --questions begin >"$T/out" 2>&1
check "--questions begin names the owner's own files and rules, and suspends the decoy" '0:1:1:1:1' \
  "$?:$(grep -c '^  your own AGENT_STARTUP.md: it loads instead' "$T/out"):$(grep -c '^  your own .claude/main-session.md' "$T/out"):$(grep -cx '  your project rules: .claude/rules/house.md\. Merging leaves out the 1 plugin rule you already have\.' "$T/out"):$([ -s "$Q" ] && echo 1)"
# What it prints is read to the owner: plain words, and the context window when a model setting names it.
check "--questions begin says nothing of a decoy" 0 "$(grep -ci decoy "$T/out")"
ANTHROPIC_MODEL='opus[1m]' run "$P2" setup.sh --questions begin >"$T/out" 2>&1
check "a model setting that ends in [1m] is a 1M window: Larger is preselected" '0:1' "$?:$(grep -c '^  context window: 1M (the model setting is opus\[1m\]): preselect Larger$' "$T/out")"
B2=$(snap)
run "$P2" setup.sh "${ANSWERS[@]}" "${ASK[@]}" --plan >"$T/out" 2>&1
check "--plan succeeds and writes nothing, in the project or in HOME" '0:same' "$?:$([ "$B2" = "$(snap)" ] && echo same)"
check "the plan names what it would create, change, run, and the backup it would make" '1:1:1:1:1' \
  "$(grep -c "^plan: would create $P2/.claude/commandeck.json" "$T/out"):$(grep -c "^plan: would change $P2/AGENT_STARTUP.md:" "$T/out"):$(grep -c '^plan: would install the add-on serena' "$T/out"):$(grep -c "^plan: would copy $G to " "$T/out"):$(grep -c '^plan: .*nothing was written' "$T/out")"
check "the plan shows the prompt-cache lifetimes it would write" '1:1' "$(grep -c '^ *+ *"promptCacheTtl": "1h"' "$T/out"):$(grep -c '^ *+ *"subagentPromptCacheTtl": "5m"' "$T/out")"
check "a plan installs nothing and keeps the decoy off" '0:1' "$(cat "$T/claude.log" 2>/dev/null | grep -c 'mcp add'):$([ -s "$Q" ] && echo 1)"

run "$P2" setup.sh "${ANSWERS[@]}" "${ASK[@]}" >"$T/out" 2>&1
check "setup with the owner's files answered succeeds, and its end brings the decoy back" '0:gone' "$?:$([ -e "$Q" ] || echo gone)"
# Merge: the owner's text stays first and whole; the plugin's rules it lacks follow in one marked block; a rule
# already there (in the file, or in .claude/rules/) is left out; a copy of the file was made first.
B=$P2/AGENT_STARTUP.md.commandeck-bak-$(date +%Y%m%d)
check "merge keeps the owner's text, adds one block, leaves out a rule the owner has, keeps a backup" '0:1:1:same' \
  "$(git -C "$P2" show HEAD:AGENT_STARTUP.md | diff - <(head -4 "$P2/AGENT_STARTUP.md") >/dev/null; echo $?):$(grep -c '^<!-- commandeck:merge:begin -->$' "$P2/AGENT_STARTUP.md"):$(grep -cxF -- "$S1" "$P2/AGENT_STARTUP.md"):$(git -C "$P2" show HEAD:AGENT_STARTUP.md | cmp -s - "$B" && echo same)"
# Replace: the owner's file is not touched; the answer is saved and the hook loads the plugin's version.
check "replace leaves the owner's file as it was and saves the answer" '0:"replace"' \
  "$(git -C "$P2" diff --quiet HEAD -- .claude/main-session.md; echo $?):$(jq -c '.ownFiles[".claude/main-session.md"]' "$P2/.claude/commandeck.json")"
STARTUP > "$T/ctx"
# The merged block is committed, so it names no machine path; the hook writes the plugin folder in as it loads it.
check "the merged block names the plugin's scripts by their plugin path, and sessions get them by the stable link" '0:0:1' \
  "$(grep -c "$T" "$P2/AGENT_STARTUP.md"):$(grep -c '\.commandeck-bak\|commandeck/plugin' "$P2/AGENT_STARTUP.md"):$(grep -q "$HOME/.commandeck/plugin/scripts/builder-launch.sh" "$T/ctx" && echo 1)"
check "sessions load the owner's merged startup file and the plugin's main-session" '1:0:1' \
  "$(grep -c '^# AGENT_STARTUP.md (auto-loaded' "$T/ctx"):$(grep -c '^# .claude/main-session.md (main only' "$T/ctx"):$(grep -c 'templates/main-session.md (main only' "$T/ctx")"
# Rules merge: a plugin rule .claude/rules/ already states is left out of what sessions load; another stays.
C=$P2/.claude/commandeck.json; jq '.rules = "skip"' "$C" > "$T/c" && cp "$C" "$T/c.kept" && cp "$T/c" "$C"
check "with rules merge, a plugin rule the project already states is not loaded twice; another is, and skip loads both" '0:1:1' \
  "$(grep -cxF -- "$M1" "$T/ctx"):$(grep -cxF -- "$M2" "$T/ctx"):$(STARTUP | grep -cxF -- "$M1")"
cp "$T/c.kept" "$C"
check "global merge adds a block without the rule the owner's file already has" '1:1:1' \
  "$(grep -c '^<!-- commandeck:rules:begin -->$' "$G"):$(grep -cxF -- "$G1" "$G"):$(head -1 "$G" | grep -c '^# Mine$')"
check "the chosen add-on is installed for the main checkout, and its hooks are on" "1:1:1:true" \
  "$(grep -c "^$P2 mcp add serena" "$T/claude.log"):$(grep -c "^add-on serena: installed, for $P2" "$T/out"):$(grep -c '^serena (read-tracker nudge and pane-budget gate): on$' "$T/out"):$(jq .serena "$P2/.claude/commandeck.json")"
check "the commit advice names the merged startup file, never the machine's settings" '1:0' \
  "$(grep -c '^  not committed yet: .*AGENT_STARTUP.md' "$T/out"):$(grep -c 'not committed yet: .*settings.local.json' "$T/out")"
# Prompt-cache lifetimes (main's ruling): recommended writes both into the project's settings and says so.
check "recommended prompt-cache lifetimes are written, saved and reported" '1h:5m:recommended:1' \
  "$(jq -r .promptCacheTtl "$P2/.claude/settings.json"):$(jq -r .subagentPromptCacheTtl "$P2/.claude/settings.json"):$(jq -r .cacheTtl "$P2/.claude/commandeck.json"):$(grep -c '^prompt cache: main 1h, subagents 5m$' "$T/out")"
check "the summary has its three parts" '1:1:1' "$(grep -c '^Done:$' "$T/out"):$(grep -c '^Needs you:' "$T/out"):$(grep -c '^Optional\.' "$T/out")"
# A plugin rule the owner keeps their own wording for (--rules-drop, by its id) is left out too.
run "$P2" setup.sh "${ANSWERS[@]}" --rules-drop "$ID" >"$T/out" 2>&1
check "a dropped rule is saved and no longer loaded" "0:1:0" "$?:$(jq --arg i "$ID" '.mergeDecisions | has($i)' "$P2/.claude/commandeck.json" | grep -c true):$(STARTUP | grep -cxF -- "$M2")"
# Keep both is saved too, so a rerun need not ask it again, and the rule loads beside the owner's.
run "$P2" setup.sh "${ANSWERS[@]}" --rules-keep "$ID" >"$T/out" 2>&1
check "a rule answered keep both is saved and loaded again" "0:keep-both:1" "$?:$(jq -r --arg i "$ID" '.mergeDecisions[$i]' "$P2/.claude/commandeck.json"):$(STARTUP | grep -cxF -- "$M2")"
# Default takes out only what setup wrote: a value the owner changed since is theirs and stays.
jq '.promptCacheTtl = "5m"' "$P2/.claude/settings.json" > "$T/s" && cp "$T/s" "$P2/.claude/settings.json"
run "$P2" setup.sh "${ANSWERS[@]}" --cache-ttl default >"$T/out" 2>&1
check "leave default takes out setup's lifetime and keeps the one the owner changed" '0:5m:false:default' \
  "$?:$(jq -r .promptCacheTtl "$P2/.claude/settings.json"):$(jq 'has("subagentPromptCacheTtl")' "$P2/.claude/settings.json"):$(jq -r .cacheTtl "$P2/.claude/commandeck.json")"
# Recommended again, over the owner's own value: theirs stays, the missing one is added; uninstall below takes out only setup's.
run "$P2" setup.sh "${ANSWERS[@]}" --cache-ttl recommended >"$T/out" 2>&1
check "recommended leaves an owner's own lifetime as it is" '0:5m:5m' "$?:$(jq -r .promptCacheTtl "$P2/.claude/settings.json"):$(jq -r .subagentPromptCacheTtl "$P2/.claude/settings.json")"
jq 'del(.promptCacheTtl)' "$P2/.claude/settings.json" > "$T/s" && cp "$T/s" "$P2/.claude/settings.json"
# Skip: a rerun takes the merge block back out, so the owner's file is as it was.
touch "$T/claude-fails"
run "$P2" setup.sh "${ANSWERS[@]}" --own-startup skip --addons serena >"$T/out" 2>&1
check "skip after merge leaves the owner's file exactly as committed" '0:0' "$?:$(git -C "$P2" diff --quiet HEAD -- AGENT_STARTUP.md; echo $?)"
check "an add-on that fails to install is under Needs you, with its command" 1 "$(grep -c '^  add-on serena: the install FAILED .*run in .*claude mcp add serena' "$T/out")"
# Off: the ponytail skill an earlier setup installed goes, and the answer is saved.
run "$P2" setup.sh "${ANSWERS[@]}" --no-ponytail >"$T/out" 2>&1
check "ponytail off removes setup's copy and saves the answer" '0:gone:false' "$?:$([ -e "$HOME/.claude/skills/ponytail" ] || echo gone):$(jq .ponytail "$P2/.claude/commandeck.json")"
# A project set up before 0.7.0 kept the rules in .claude/settings.json: a rerun moves them out of the committed file.
R=$(jq -c '.permissions.allow' "$P2/.claude/settings.local.json"); S=$P2/.claude/settings.json L=$P2/.claude/settings.local.json
jq --argjson r "$R" '.permissions.allow += $r' "$S" > "$T/s" && cp "$T/s" "$S"; rm "$L"
jq --arg s "$S" --arg l "$L" --argjson r "$R" '.entries[$s].added = $r | del(.entries[$l])' "$M2F" > "$T/m" && cp "$T/m" "$M2F"
# An update whose doctor fails puts back what its setup wrote, also a file the older manifest never named.
touch "$T/orca-down"; run "$P2" update.sh >"$T/out" 2>&1; R1=$?; rm "$T/orca-down"
check "a failed update takes out the local settings the older install never had, and leaves the rules where they were" '1:gone:true' \
  "$R1:$([ -e "$L" ] || echo gone):$(jq '.permissions.allow | any(contains("orca-ide"))' "$S")"
run "$P2" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1
check "a deployed install's rules move from settings.json to settings.local.json" '0:["Bash(make:*)"]:true' "$?:$(jq -c .permissions.allow "$S"):$(jq '.permissions.allow | any(contains("orca-ide"))' "$L")"
# A new scope moves the rules instead of refusing (finding 14), and back.
run "$P2" setup.sh "${ANSWERS[@]}" --scope machine >"$T/out" 2>&1
check "a new scope moves the rules" '0:true:false:1' "$?:$(jq '.permissions.allow | any(contains("orca-ide"))' "$HOME/.claude/settings.json"):$(jq '.permissions.allow // [] | any(contains("orca-ide"))' "$L"):$(grep -c '^permissions: moved from project scope to machine scope' "$T/out")"
run "$P2" setup.sh "${ANSWERS[@]}" --scope project >"$T/out" 2>&1
check "and back, leaving the machine's file the other tool's" '0:["Bash(ls:*)"]' "$?:$(jq -c .permissions.allow "$HOME/.claude/settings.json")"
# The relay pane says why its servers read as blocked "by enterprise policy".
git -C "$P2" worktree add -q "$T/wt/Chief-of-Staff" 2>/dev/null
check "the relay pane explains the enterprise-policy block" 1 "$(cd "$T/wt/Chief-of-Staff" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN PATH="$BIN:$PATH" bash "$PLUGIN/hooks/agent-startup-context.sh" </dev/null 2>/dev/null | grep -c 'enterprise policy')"
git -C "$P2" worktree remove --force "$T/wt/Chief-of-Staff"
run "$P2" uninstall.sh >"$T/out" 2>&1
check "uninstall puts the owner's files back and removes setup's backup and local settings" '0:0:gone:gone' \
  "$?:$(git -C "$P2" status --porcelain -- AGENT_STARTUP.md .claude/settings.json .claude/main-session.md | wc -l | tr -d ' '):$([ -e "$B" ] || echo gone):$([ -e "$L" ] || echo gone)"

# --- a plan shows what apply does; a failed check keeps the decoy; merge counts only what a seat loads ---
P3=$T/proj3; project "$P3"; Q3=$P3/.git/commandeck-setup-questions
echo '{"version":2}' > "$P3/.claude/commandeck.json"
run "$P3" setup.sh --questions begin >"$T/out" 2>&1
check "a --questions begin that stops leaves the picker guard's decoy on" '1:gone' "$?:$([ -e "$Q3" ] || echo gone)"
rm "$P3/.claude/commandeck.json"
# A plan reads what it would already have written: Codex's hooks file it would create first, then fill;
# and an AGENTS.md that is not there yet.
mv "$HOME/.codex/hooks.json" "$T/hooks.kept"; rm "$P3/AGENTS.md"
run "$P3" setup.sh "${ANSWERS[@]}" --plan >"$T/out" 2>&1
check "a plan with no Codex hooks file yet runs to its end and creates it" '0:1:1' \
  "$?:$(grep -c "^plan: would create $HOME/.codex/hooks.json" "$T/out"):$(grep -c '^plan: .*nothing was written' "$T/out")"
mv "$T/hooks.kept" "$HOME/.codex/hooks.json"
# Install over an owner's global file: the plan says what apply does (left as it is), not a new block.
run "$P3" setup.sh "${ANSWERS[@]}" --global-rules install --plan >"$T/out" 2>&1
check "a plan to install over the owner's global file shows no change to it, as apply makes none" '0:0:1' \
  "$?:$(grep -c "^plan: would change $G" "$T/out"):$(grep -c "^global rules: $G exists, left as it is" "$T/out")"
# A path-scoped rule loads only for its paths, and a Builder never loads agents.md (worktree-setup.sh
# --builder): neither stands in for a plugin rule. Details below its heading are never loaded either.
S2=$(one1 "$PLUGIN/templates/AGENT_STARTUP.md" 2)
mkdir -p "$P3/.claude/rules"
printf -- '---\npaths: ["docs/**"]\n---\n\n%s\n' "$S1" > "$P3/.claude/rules/docs.md"
printf '%s\n' "$S2" > "$P3/.claude/rules/agents.md"
printf 'Our persona.\n\n## Details (not injected)\n\n%s\n' "$M1" > "$P3/.claude/main-session.md"
git -C "$P3" add -A && git -C "$P3" -c user.name=t -c user.email=t@t commit -qm own
run "$P3" setup.sh "${ANSWERS[@]}" --rules merge --own-main-session merge >"$T/out" 2>&1; R1=$?
CTX=$(cd "$P3" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN PATH="$BIN:$PATH" bash "$PLUGIN/hooks/agent-startup-context.sh" </dev/null 2>/dev/null)
check "main still loads a plugin rule that only a path-scoped rule states, and not one an always-on rule states" '0:1:0' \
  "$R1:$(grep -cxF -- "$S1" <<<"$CTX"):$(grep -cxF -- "$S2" <<<"$CTX")"
check "a main-session merge adds a rule the owner has only under Details" 1 "$(awk '/^## Details \(not injected\)/ {exit} 1' "$P3/.claude/main-session.md" | grep -cxF -- "$M1")"
git -C "$P3" worktree add -q "$T/wt/b3"
jq -n --arg a "$T/wt/b3/.claude/rules/agents.md" '{claudeMdExcludes: [$a]}' > "$T/wt/b3/.claude/settings.local.json"
check "a Builder, which never loads agents.md, still gets the plugin rule it states" 1 \
  "$(cd "$T/wt/b3" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN COMMANDECK_BUILDER=1 PATH="$BIN:$PATH" bash "$PLUGIN/hooks/agent-startup-context.sh" </dev/null 2>/dev/null | grep -cxF -- "$S2")"
git -C "$P3" worktree remove --force "$T/wt/b3"
# The owner's AGENT_STARTUP.md loads in every seat, a Builder's too: its merge keeps both rules.
printf '# Ours\n\n- Run make before you push.\n' > "$P3/AGENT_STARTUP.md"
git -C "$P3" add -A && git -C "$P3" -c user.name=t -c user.email=t@t commit -qm startup
run "$P3" setup.sh "${ANSWERS[@]}" --own-startup merge >"$T/out" 2>&1
check "a startup merge adds the rules only a path-scoped rule or agents.md states" '0:1:1' \
  "$?:$(grep -cxF -- "$S1" "$P3/AGENT_STARTUP.md"):$(grep -cxF -- "$S2" "$P3/AGENT_STARTUP.md")"
run "$P3" uninstall.sh >/dev/null 2>&1

# --- what a seat loads is read as Claude Code reads it, and decided for that seat when it starts ---
P4=$T/proj4; project "$P4"; mkdir -p "$P4/.claude/rules"; L4=$P4/.claude/settings.local.json
CTX4() { (cd "$1" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN PATH="$BIN:$PATH" ${2:+COMMANDECK_BUILDER=1} bash "$PLUGIN/hooks/agent-startup-context.sh" </dev/null 2>/dev/null); }
ex4() { jq --arg x "$2" '.claudeMdExcludes = [$x]' "$1" 2>/dev/null > "$T/x" || jq -n --arg x "$2" '{claudeMdExcludes: [$x]}' > "$T/x"; cp "$T/x" "$1"; }
run "$P4" setup.sh "${ANSWERS[@]}" --rules merge >"$T/out" 2>&1; check "setup with rules merge succeeds" 0 $?
# Frontmatter is YAML: a paths: key spelt any way YAML allows still scopes the file to its paths.
n=0
for fm in '"paths": ["docs/**"]' "'paths': [docs/**]" 'paths : [docs/**]' '{paths: [docs/**]}' $'? paths\n: [docs/**]' $'"trigger": always_off\n"paths": [docs/**]'; do
  n=$((n + 1)); printf -- '---\n%s\n---\n\n%s\n' "$fm" "$(cat "$PLUGIN/templates/AGENT_STARTUP.md")" > "$P4/.claude/rules/docs.md"
  check "a rules file scoped by paths: spelling $n stands in for no plugin rule" 1 "$(CTX4 "$P4" | grep -cxF -- "$S1")"
done
printf '\357\273\277---\r\npaths: [docs/**]\r\n---\r\n\r\n%s\r\n' "$S1" > "$P4/.claude/rules/docs.md"
check "a rules file scoped by paths: behind a byte-order mark, with CRLF lines, stands in for no plugin rule" 1 "$(CTX4 "$P4" | grep -cxF -- "$S1")"
printf -- '---\n"description": a rule\n---\n\n%s\n' "$S1" > "$P4/.claude/rules/docs.md"
check "a rules file with no paths: in its frontmatter stands in for the plugin rule" 0 "$(CTX4 "$P4" | grep -cxF -- "$S1")"
printf -- '\n%s\n' "$S1" > "$P4/.claude/rules/docs.md"
check "and so does a rules file with no frontmatter" 0 "$(CTX4 "$P4" | grep -cxF -- "$S1")"
# Fail safe (main's ruling): a file counts as always loaded only when its frontmatter is read with certainty
# and has no paths key. Any paths key, and any frontmatter this cannot read for sure, keeps the plugin rule:
# a rule loaded twice is a duplicate line, a rule left out is lost.
n=0
for fm in $'"trigger": "always_on"\n"paths": [docs/**]' '  paths: [docs/**]' $'description: a rule\n  paths: [docs/**]' \
  $'paths:\n  - docs/**' '  description: a rule' 'this is not yaml' $'base: &b {paths: [docs/**]}\n<<: *b' \
  $'description: a rule\ndescription: again'; do
  n=$((n + 1)); printf -- '---\n%s\n---\n\n%s\n' "$fm" "$S1" > "$P4/.claude/rules/docs.md"
  check "a rules file whose frontmatter has paths: or is not read for sure ($n) stands in for no plugin rule" 1 "$(CTX4 "$P4" | grep -cxF -- "$S1")"
done
printf -- '---\npaths: [docs/**]\n\n%s\n' "$S1" > "$P4/.claude/rules/docs.md"
check "a rules file whose frontmatter never closes stands in for no plugin rule" 1 "$(CTX4 "$P4" | grep -cxF -- "$S1")"
# Rules that share no plugin rule: a count of 0 must not stop setup (grep -c finds nothing).
printf '# Ours\n\n- Run make before you push.\n' > "$P4/.claude/rules/docs.md"
run "$P4" setup.sh --questions begin >"$T/out" 2>&1
check "--questions begin counts no plugin rule your rules lack" '0:1' "$?:$(grep -cx '  your project rules: .claude/rules/docs.md\. Merging leaves out the 0 plugin rules you already have\.' "$T/out")"
run "$P4" setup.sh --questions end >/dev/null 2>&1
rm "$P4/.claude/rules/docs.md"; printf '# House\n\n%s\n\n%s\n' "$S1" "$M1" > "$P4/.claude/rules/house.md"
# An exclude is a glob as Claude Code reads it: ** spans no folder too, so it takes a direct child.
n=0
for x in "$P4/.claude/rules/**/*.md" "$P4/**" "$P4/**/house.md" "$P4/.claude/rules/{house,other}.md" "$P4/.claude/rules/hous?.md" "$P4/.claude/rules/[h]ouse.md"; do
  n=$((n + 1)); ex4 "$L4" "$x"
  check "a rules file excluded by glob $n stands in for no plugin rule" 1 "$(CTX4 "$P4" | grep -cxF -- "$S1")"
done
ex4 "$L4" "$P4/.claude/rules/**/*.md"
run "$P4" setup.sh --questions begin >"$T/out" 2>&1
check "--questions begin does not list a rules file a glob excludes" '0:0' "$?:$(grep -c '^  your project rules: .*house.md' "$T/out")"
run "$P4" setup.sh --questions end >/dev/null 2>&1
jq 'del(.claudeMdExcludes)' "$L4" > "$T/x" && cp "$T/x" "$L4"
# The owner's merged startup file is committed, and a seat may exclude what main loads: each seat decides when it starts.
printf '# Ours\n\n- Run make before you push.\n' > "$P4/AGENT_STARTUP.md"
printf 'Our persona.\n\n## Details (not injected)\n\nLong notes.\n' > "$P4/.claude/main-session.md"
git -C "$P4" add AGENT_STARTUP.md .claude/main-session.md .claude/rules && git -C "$P4" -c user.name=t -c user.email=t@t commit -qm own
run "$P4" setup.sh "${ANSWERS[@]}" --rules merge --own-startup merge --own-main-session merge --plan >"$T/out" 2>&1
# One plain line per merged block, not a third count in a row.
check "the plan says main's sessions leave out of each merged block what the rule files state" '0:2:0' "$?:$(grep -c ": main's sessions also drop any plugin rule your rule files already state\.$" "$T/out"):$(grep -c 'when main starts' "$T/out")"
run "$P4" setup.sh "${ANSWERS[@]}" --rules merge --own-startup merge --own-main-session merge >"$T/out" 2>&1; R1=$?
git -C "$P4" add AGENT_STARTUP.md .claude/main-session.md && git -C "$P4" -c user.name=t -c user.email=t@t commit -qm merged
check "main, which loads the house rules, gets neither plugin rule they state twice" '0:0:0' "$R1:$(CTX4 "$P4" | grep -cxF -- "$S1"):$(CTX4 "$P4" | grep -cxF -- "$M1")"
git -C "$P4" worktree add -q "$T/wt/b4"
ex4 "$T/wt/b4/.claude/settings.local.json" "$T/wt/b4/.claude/rules/house.md"
check "a Builder whose own settings exclude the house rules gets the merged startup rule they state" 1 "$(CTX4 "$T/wt/b4" 1 | grep -cxF -- "$S1")"
git -C "$P4" worktree remove --force "$T/wt/b4"
ex4 "$L4" "$P4/.claude/rules/house.md"
check "main, once its settings exclude them, gets the merged main-session rule they state" 1 "$(CTX4 "$P4" | grep -cxF -- "$M1")"
run "$P4" uninstall.sh >/dev/null 2>&1

# A duplicate is the same text once case and spacing are set aside, nothing more (main's ruling): a path, a code
# span, a flag or a sign changes what a rule says, so a near-match keeps the plugin's rule.
MR=$PLUGIN/scripts/merge-rules.py
A=$(awk '/^THE CLEAR LINE/{p=1} /^## Details/{exit} p' "$PLUGIN/templates/main-session.md" | sed 's|~/.claude/checkpoints/|./.claude/checkpoints/|g')
check "an owner's rule naming ./.claude/checkpoints/ leaves in the plugin's ~/.claude/checkpoints/ rule" 0 \
  "$(python3 "$MR" "$PLUGIN/templates/main-session.md" --against <(printf '%s\n' "$A") --report | grep -c '^  already in')"
n=0
while IFS='|' read -r mine theirs want; do
  n=$((n + 1))
  check "a plugin rule against a near-match ($n) is kept once, or left out when only case and spacing differ" "$want" \
    "$(python3 "$MR" <(printf -- '- %s\n' "$mine") --against <(printf -- '- %s\n' "$theirs") | grep -cxF -- "- $mine")"
done <<'EOF'
Save a checkpoint in ~/.claude/checkpoints/ first.|Save a checkpoint in ./.claude/checkpoints/ first.|1
Run `make test` before you push.|Run make test before you push.|1
Call setup.sh --plan first.|Call setup.sh plan first.|1
Keep the limit at -1.|Keep the limit at 1.|1
Run  MAKE before you push.|run make before   you push.|0
EOF

[ "$FAIL" = 0 ] || { echo "--- last output"; tail -15 "$T/out"; }
done_tests
