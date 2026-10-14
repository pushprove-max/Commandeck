#!/usr/bin/env bash
# timeout: 300 -- about 130s run alone on the Mac (2026-10-13), over the 120s default
# setup.test.sh -- setup is the one command between "plugin installed" and a
# working project. What this pins: it takes every answer in one pass and asks
# nothing itself; a failed preflight changes nothing; the manifest names every
# path setup changed, with what was there before; another tool's entries in
# the files it merges into are left exactly as they were; the config carries a
# version and an unknown one is refused, with no migration; a second run adds
# nothing twice; and update re-points a moved plugin.
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
# --- workflows: switched on for the project, and /test-audit is the project's own copy ---
# The setting goes into the project's settings file at either scope, never the
# machine's: Claude Code hides the Workflow tool without it. The script sees no
# disk, so setup writes this machine's two paths into the project's copy.
WF=$PROJ/.claude/workflows/test-audit.js
check "workflows are switched on in the project's settings, not the machine's" 'true null' "$(jq .enableWorkflows "$PROJ/.claude/settings.json" "$HOME/.claude/settings.json" | paste -sd' ' -)"
check "the project's /test-audit names the plugin's prompt file and the project's scratch folder" \
  "const PROMPT = \"$PLUGIN/templates/test-audit-prompt.md\"|const OUT_ROOT = \"$HOME/.commandeck/scratch/$(printf %s "$PROJ" | tr -c 'A-Za-z0-9' '-')\"" \
  "$(grep -E '^const (PROMPT|OUT_ROOT) = ' "$WF" | paste -sd'|' -)"
check "and is the plugin's script but for those two lines" 0 "$(diff <(grep -vE '^const (PROMPT|OUT_ROOT) = ' "$WF") <(grep -vE '^const (PROMPT|OUT_ROOT) = ' "$PLUGIN/templates/test-audit.js") >/dev/null; echo $?)"
check "git does not see the copy: it holds this machine's paths" "" "$(git -C "$PROJ" status --short -- .claude/workflows)"
check "the manifest records the copy as the plugin's own" own "$(jq -r --arg p "$WF" '.entries[$p].kind' "$(mf "$PROJ")")"
check "the project's instruction file keeps its text and gains the plugin's block" '1:1' \
  "$(grep -c '^Keep it short\.$' "$PROJ/AGENTS.md"):$(grep -c '^<!-- commandeck:begin -->$' "$PROJ/AGENTS.md")"
check "the session files are in the project's exclude list, after its own lines" '*.swp .claude/settings.local.json' \
  "$(sed -n '2p;3p' "$PROJ/.git/info/exclude" | tr '\n' ' ' | sed 's/ $//')"
# builder-launch.sh --model appends the pick to .claude/routing-log: running state, never committed.
check "the routing log a Builder launch writes is hidden from git too" 1 "$(grep -cx '\.claude/routing-log' "$PROJ/.git/info/exclude")"

# --- the Builder's model and advisor are a set-up choice (the owner: "Sonnet with /advisor Opus") ---
# With no choice the Builder launches as the plugin's routing says; the choice
# changes the Builder's command and no other role's, and a name routing does
# not know never reaches a launch.
cmd() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_ROUTING bash -c '. "$0" && pp_route "$1" && echo "$RT_CMD"' "$PLUGIN/scripts/paths.sh" "$1" 2>&1); }
OTHERS="$(cmd orchestrator)|$(cmd design-coauthor)"
check "with no choice the Builder's command is the plugin's own" "claude --model opus --advisor fable" "$(cmd builder)"
KEEP=$(snap)
run "$PROJ" setup.sh --builder-model gpt-9 >"$T/out" 2>&1; check "a model routing does not know is refused" 1 $?
check "the refusal names the ones it knows" 1 "$(grep -c 'fable, opus, sonnet' "$T/out")"
run "$PROJ" setup.sh --builder-advisor 'opus --dangerously-skip-permissions' >"$T/out" 2>&1; check "so is an advisor that is not one" 1 $?
check "and nothing was written" "$KEEP" "$(snap)"
run "$PROJ" setup.sh --builder-model sonnet --builder-advisor opus >"$T/out" 2>&1; check "Sonnet advised by Opus is accepted" 0 $?
check "the Builder's command has the Sonnet model and the Opus advisor" "claude --model sonnet --advisor opus" "$(cmd builder)"
check "another role's command is unchanged by the choice" "$OTHERS" "$(cmd orchestrator)|$(cmd design-coauthor)"
jq '.builder.model = "gpt-9"' "$CFG" > "$T/keep" && cp "$CFG" "$T/cfg" && cp "$T/keep" "$CFG"
check "a name put into the config by hand stops the launch: no command comes out" "2:0" "$(cmd builder >"$T/out" 2>&1; echo "$?:$(grep -c -- '--model' "$T/out")")"
cp "$T/cfg" "$CFG"

# --- no advisor is a choice of its own, and a model may advise itself ---
# An empty answer means "the plugin's own", so "none" is the one word for a
# Builder that launches with no --advisor at all.
run "$PROJ" setup.sh --builder-advisor none >"$T/out" 2>&1; check "no advisor is accepted" 0 $?
check "the config stores it" '{"model":"sonnet","advisor":"none"}' "$(jq -c .builder "$CFG")"
check "and the Builder's command carries no advisor flag" "claude --model sonnet" "$(cmd builder)"
run "$PROJ" setup.sh --builder-model none >"$T/out" 2>&1; check "a Builder with no model is refused" 1 $?
run "$PROJ" setup.sh --builder-model opus --builder-advisor opus >"$T/out" 2>&1; check "Opus advised by Opus is accepted" 0 $?
check "and reaches the Builder's command" "claude --model opus --advisor opus" "$(cmd builder)"
run "$PROJ" setup.sh --builder-model '' --builder-advisor '' >"$T/out" 2>&1
check "an empty answer for both is still the plugin's own" "claude --model opus --advisor fable|null" "$(cmd builder)|$(jq -c .builder "$CFG")"
run "$PROJ" setup.sh --builder-model sonnet --builder-advisor opus >"$T/out" 2>&1

# --- a second run adds nothing twice and keeps the first run's record ---
run "$PROJ" setup.sh "${ANSWERS[@]}" --name Grace >"$T/out" 2>&1; check "a second setup succeeds" 0 $?
check "the new answer is taken" Grace "$(jq -r '.chiefOfStaff.name' "$CFG")"
check "and the Builder choice, not given again, is kept" "claude --model sonnet --advisor opus" "$(cmd builder)"
check "still five Codex entries" 5 "$(ours)"
check "still one block in the instruction file" 1 "$(grep -c '^<!-- commandeck:begin -->$' "$PROJ/AGENTS.md")"
check "the manifest still records what was there before the first run" 'did not exist' "$(jq -r --arg p "$CFG" '.entries[$p].prior' "$(mf "$PROJ")")"

# --- update: a moved plugin is re-pointed; an unknown config version is refused, not migrated ---
cp -R "$PLUGIN" "$T/plugin-2"
PLUGIN_DIR=$T/plugin-2 run "$PROJ" update.sh >"$T/out" 2>&1; check "update from the plugin's new folder succeeds" 0 $?
check "update keeps the Builder choice" '{"model":"sonnet","advisor":"opus"}' "$(jq -c .builder "$CFG")"
check "update re-points the project's /test-audit at the new folder's prompt file" 1 "$(grep -c "^const PROMPT = \"$T/plugin-2/templates/test-audit-prompt.md\"$" "$WF")"
check "Codex's entries point at the new folder" 5 "$(jq --arg p "$T/plugin-2/hooks/codex-dispatch.sh" '[.hooks[][].hooks[] | select(.command | contains($p))] | length' "$HOME/.codex/hooks.json")"
check "and none at the old one" 0 "$(grep -c "$PLUGIN/hooks/codex-dispatch.sh" "$HOME/.codex/hooks.json")"
check "the jobs run the new folder's scripts" 2 "$(grep -l "^ExecStart=\"[^\"]*\" \"$T/plugin-2/scripts/" "$HOME/.config/systemd/user"/commandeck-*.service | wc -l | tr -d ' ')"
check "update prints the version it moved to and its changelog" '1:1' \
  "$(grep -c "^commandeck $(jq -r .version "$PLUGIN/.claude-plugin/plugin.json") at $T/plugin-2 " "$T/out"):$(grep -c '^## ' "$T/out")"
# The doctor finds a break after the re-point: every file goes back, and update fails.
touch "$T/orca-down"; KEEP=$(snap)
run "$PROJ" update.sh >"$T/out" 2>&1; check "an update the doctor fails exits 1" 1 $?
check "and every file is as it was before that update" "$KEEP" "$(snap)"
check "it says so" 1 "$(grep -c '^update: FAILED.*back as it was' "$T/out")"
# A file the owner keeps read-only goes back too, still read-only: a copy onto
# it was refused, and the way back stopped there with the rest half updated.
RO=$(jq -r '.entries | to_entries[] | select(.value.kind != "dir") | .key' "$(mf "$PROJ")" | head -1); chmod a-w "$RO"; KEEP=$(snap)
PLUGIN_DIR=$T/plugin-2 run "$PROJ" update.sh >"$T/out" 2>&1; check "an update the doctor fails, over a read-only file, exits 1" 1 $?
check "every file is as it was, the read-only one too" "$KEEP|no" "$(snap)|$([ -w "$RO" ] && echo yes || echo no)"
check "and it says so" 1 "$(grep -c '^update: FAILED.*back as it was' "$T/out")"
chmod u+w "$RO"
rm "$T/orca-down"
# setup copies the dashboard's view (index.html, app.css, app.js) beside the
# data and adds the project to the list; neither is in a manifest. Left behind
# after the way back, a new view would run against the old configuration.
cp -R "$PLUGIN" "$T/plugin-3"; echo '// a newer view' >> "$T/plugin-3/dashboard/app.js"
# Its doctor fails after setup has finished, so the view was copied by then.
printf '#!/usr/bin/env bash\necho "FAIL a break only this doctor sees"; exit 1\n' > "$T/plugin-3/scripts/doctor.sh"
KEEP=$(snap)
PLUGIN_DIR=$T/plugin-3 run "$PROJ" update.sh >"$T/out" 2>&1; check "an update to a newer view that the doctor fails exits 1" 1 $?
check "it failed at the doctor, after setup" "update: FAILED (the doctor found a break, above)" "$(grep -o '^update:[^.]*' "$T/out" | tail -1)"
check "and the view is the one from before that update, with every other file" "$KEEP" "$(snap)"
rm -rf "$T/plugin-3"
# --- the plugin in a folder with a space in its name ---
# The Codex entry quotes the path (install-lib.sh il_shq), so setup takes it.
cp -R "$PLUGIN" "$T/plug in"
PLUGIN_DIR="$T/plug in" run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "setup with Codex from a folder with a space succeeds" 0 $?
check "Codex's entries point at it, quoted" 5 "$(jq --arg p "'$T/plug in'/hooks/codex-dispatch.sh" '[.hooks[][].hooks[] | select(.command | contains($p))] | length' "$HOME/.codex/hooks.json")"
# A quote or a backslash in the path is data in Codex's config, not syntax: the
# file must still parse and name the folder exactly.
ODD="$T/pl\"u\\g"; cp -R "$PLUGIN" "$ODD"
PLUGIN_DIR="$ODD" run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "setup from a folder with a quote and a backslash in its name succeeds" 0 $?
check "Codex's config parses and names that folder" "$ODD/hooks/codex-notify.sh" \
  "$(python3 -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["notify"][0])' "$HOME/.codex/config.toml" 2>&1)"
run "$PROJ" setup.sh "${ANSWERS[@]}" --standard-context >"$T/out" 2>&1; check "and setup from the first folder takes it back" 0 $?
check "with one notify line, the first folder's" "1 1" "$(grep -c '^notify' "$HOME/.codex/config.toml") $(grep -c "^notify = \[\"$PLUGIN/hooks/codex-notify.sh\"\]$" "$HOME/.codex/config.toml")"
# A stored "no" is an answer. jq's `false // empty` dropped it, so the next
# setup or update turned the setting back on, serena's guards with it.
echo '{"mcpServers": {"serena": {}}}' > "$HOME/.claude.json"
run "$PROJ" setup.sh --no-serena --no-strict --no-standard-context >"$T/out" 2>&1
run "$PROJ" setup.sh >"$T/out" 2>&1; check "a rerun with no answers succeeds" 0 $?
check "and keeps every stored no" '[false,false,false]' "$(jq -c '[.serena, .strictHooks, .standardContext]' "$CFG")"
# The watcher's job and the logs under ~/.claude are named for the project's
# folder name. A second project with the same name would share them, and
# uninstalling either would stop the other's watcher and delete its history.
mkdir -p "$T/elsewhere" && git init -q -b main "$T/elsewhere/${PROJ##*/}" && git -C "$T/elsewhere/${PROJ##*/}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
KEEP=$(snap)
run "$T/elsewhere/${PROJ##*/}" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "a second project with the same folder name is refused" 1 $?
check "it names the project that has the name" 1 "$(grep -c "another project named ${PROJ##*/} is set up at $PROJ" "$T/out")"
check "and changes nothing" "$KEEP" "$(snap)"
# The rule must match a script's name: `scripts/:*` asks for a word that ends
# at the slash, so every workflow command still stopped at a permission prompt.
check "the permission rule matches the plugin's scripts by name" 'Bash(bash R/scripts/*)' \
  "$(grep -rhoE 'Bash\(bash [^)]*/scripts/[^)]*\)' "$PROJ/.claude" | sort -u | sed 's|bash .*/scripts/|bash R/scripts/|')"
# An owner's own Codex hook that only mentions the dispatcher's path is the
# owner's: not rewritten into the plugin's command, and not trusted for them.
CX=$HOME/.codex; MINE='echo mine # not /p/hooks/codex-dispatch.sh'
jq --arg c "$MINE" '.hooks.PreToolUse += [{hooks: [{type: "command", command: $c}]}]' "$CX/hooks.json" > "$T/h.json" && cp "$T/h.json" "$CX/hooks.json"
run "$PROJ" setup.sh >"$T/out" 2>&1; check "setup beside an owner's hook that names the dispatcher succeeds" 0 $?
check "the owner's hook is left as written" 1 "$(jq --arg c "$MINE" '[.hooks.PreToolUse[].hooks[] | select(.command == $c)] | length' "$CX/hooks.json")"
check "and only the plugin's five entries are trusted" 5 "$(grep -c "^\[hooks.state.\"$HOME/.codex/hooks.json:" "$HOME/.codex/config.toml" | awk '{print $1 - 1}')"
# Codex's trust table is read with tomllib, which Python 3.10 lacks: every
# trusted project would read as untrusted and its Codex guards would not run.
REALPY=$(command -v python3)
printf '#!/usr/bin/env bash\n[[ "$*" == *tomllib* ]] && [ -e "%s/py310" ] && exit 1\nexec "%s" "$@"\n' "$T" "$REALPY" > "$BIN/python3"; chmod +x "$BIN/python3"
touch "$T/py310"; KEEP=$(snap)
run "$PROJ" setup.sh >"$T/out" 2>&1; check "a Python without tomllib stops setup" 1 $?
check "it says which Python is needed" 1 "$(grep -c 'Python 3.11 or newer' "$T/out")"
check "and changes nothing" "$KEEP" "$(snap)"
run "$PROJ" doctor.sh >"$T/out" 2>&1; check "the doctor fails on it too" "1 1" "$(grep -c '^FAIL tools: ' "$T/out") $(grep -c 'Python 3.11 or newer' "$T/out")"
rm "$T/py310" "$BIN/python3"
jq '.version = 99' "$CFG" > "$T/c.json" && cp "$T/c.json" "$CFG"; KEEP=$(snap)
PLUGIN_DIR=$T/plugin-2 run "$PROJ" update.sh >"$T/out" 2>&1; check "a config version update does not know is refused" 1 $?
check "it says so" 1 "$(grep -c 'version 99' "$T/out")"
check "and changes nothing" "$KEEP" "$(snap)"
run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "setup refuses it too" 1 $?

# --no-dashboard is an answer like the others: a rerun with no answers, which
# is what update does, must not bring the dashboard back for that project.
git init -q -b main "$T/quiet" && git -C "$T/quiet" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
run "$T/quiet" setup.sh "${ANSWERS[@]}" --no-dashboard >"$T/out" 2>&1; check "setup without the dashboard succeeds" 0 $?
run "$T/quiet" setup.sh >"$T/out" 2>&1; check "a rerun with no answers succeeds" 0 $?
check "the project is still not on the dashboard" 0 "$(grep -cxF "$T/quiet" "$HOME/.commandeck/dashboard/projects")"
# The doctor asks for what setup was asked to do: update runs it and rolls back on a FAIL.
run "$T/quiet" doctor.sh >"$T/out" 2>&1; check "the doctor does not fail a project for the dashboard it declined" 0 "$(grep -c '^FAIL dashboard' "$T/out")"
run "$T/quiet" update.sh >"$T/out" 2>&1; check "and an update of it succeeds" 0 $?
run "$T/quiet" setup.sh --dashboard >"$T/out" 2>&1; check "--dashboard takes the answer back" 0 $?
check "and the project is on the dashboard" 1 "$(grep -cxF "$T/quiet" "$HOME/.commandeck/dashboard/projects")"
run "$T/quiet" setup.sh --no-dashboard >"$T/out" 2>&1; check "declining it after it was on succeeds" 0 $?
check "and takes the project off the dashboard" 0 "$(grep -cxF "$T/quiet" "$HOME/.commandeck/dashboard/projects")"

# The install manifest and the scratch folder are named for the checkout's
# path with every odd character a dash, so s-b and s_b are one name: the
# second setup would write into the first one's manifest, and uninstalling
# either would take the other's config and watcher.
for n in s-b s_b; do git init -q -b main "$T/$n" && git -C "$T/$n" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first; done
run "$T/s-b" setup.sh "${ANSWERS[@]}" --no-dashboard >"$T/out" 2>&1; check "the first of two like-named paths sets up" 0 $?
KEEP=$(snap)
run "$T/s_b" setup.sh "${ANSWERS[@]}" --no-dashboard >"$T/out" 2>&1; check "a path that shares its install record with another project is refused" 1 $?
check "it names the project that holds the record" 1 "$(grep -c "is set up at $T/s-b" "$T/out")"
check "and changes nothing" "$KEEP" "$(snap)"
run "$T/s_b" uninstall.sh >"$T/out" 2>&1; check "uninstall from the path that does not hold the record is refused" 1 $?
check "and takes nothing of the other project's" "$KEEP" "$(snap)"

# The dashboard under another network name. The list of names it answers to is
# closed by default; --hosts adds names, a rerun keeps them, and a name that is
# not a host name is refused before anything changes.
JOB=$HOME/.config/systemd/user/commandeck-dashboard.service
project "$T/named"
run "$T/named" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1
check "by default the dashboard job is given no extra name" 0 "$(grep -c COMMANDECK_DASHBOARD_HOSTS "$JOB")"
BEFORE=$(snap)
run "$T/named" setup.sh --hosts 'box.example;touch x' >"$T/out" 2>&1; check "a name that is not a host name is refused" 2 $?
check "and nothing changed" "$BEFORE" "$(snap)"
run "$T/named" setup.sh --hosts box.tailnet.example,desk.lan >"$T/out" 2>&1; check "setup with extra dashboard names succeeds" 0 $?
check "the dashboard job carries the names" 1 "$(grep -c '^Environment="COMMANDECK_DASHBOARD_HOSTS=box.tailnet.example,desk.lan"$' "$JOB")"
run "$T/named" setup.sh >"$T/out" 2>&1
check "a rerun with no answers keeps the names" 1 "$(grep -c '^Environment="COMMANDECK_DASHBOARD_HOSTS=box.tailnet.example,desk.lan"$' "$JOB")"
run "$T/named" doctor.sh >"$T/out" 2>&1
check "the doctor lists the extra names and names the fix for a 403" 1 "$(grep -c '^ok  *dashboard names: .*box.tailnet.example,desk.lan.*setup.sh --hosts' "$T/out")"
run "$T/named" setup.sh --hosts '' >"$T/out" 2>&1
check "an empty answer closes the list again" 0 "$(grep -c COMMANDECK_DASHBOARD_HOSTS "$JOB")"

# Uninstall leaves no trace of the Builder choice: it lives in the config uninstall removes.
run "$PROJ" uninstall.sh >/dev/null 2>&1
check "after uninstall the Builder's command is the plugin's own again, and the config is gone" "claude --model opus --advisor fable|no" "$(cmd builder)|$([ -e "$CFG" ] && echo yes || echo no)"

check "uninstall takes /test-audit and the workflows setting back out of the project" "no|null" "$([ -e "$WF" ] && echo yes || echo no)|$(jq .enableWorkflows "$PROJ/.claude/settings.json")"
# An owner who switched workflows off keeps that answer, and at machine scope the
# setting still goes to the project's file: the machine's is every project's.
project "$T/mach"; project "$T/offp"
jq '.enableWorkflows = false' "$T/offp/.claude/settings.json" > "$T/s" && cp "$T/s" "$T/offp/.claude/settings.json"
run "$T/offp" setup.sh --profile claude --no-dashboard >"$T/out" 2>&1
check "an owner's own false is left, and setup says /test-audit needs it" "false|1" "$(jq .enableWorkflows "$T/offp/.claude/settings.json")|$(grep -c 'enableWorkflows.*false' "$T/out")"
run "$T/offp" uninstall.sh >/dev/null 2>&1
check "and is still there after uninstall" false "$(jq .enableWorkflows "$T/offp/.claude/settings.json")"
run "$T/mach" setup.sh --profile claude --scope machine --no-dashboard >"$T/out" 2>&1; check "setup at machine scope succeeds" 0 $?
check "machine scope: the setting is in the project's file, the rules in the machine's" 'true|null|true' \
  "$(jq .enableWorkflows "$T/mach/.claude/settings.json")|$(jq .enableWorkflows "$HOME/.claude/settings.json")|$(jq '.permissions.allow | any(contains("orca-ide"))' "$HOME/.claude/settings.json")"
run "$T/mach" uninstall.sh >/dev/null 2>&1
check "machine scope: uninstall puts the project's settings back as they were" 0 "$(diff <(jq -S . "$T/mach/.claude/settings.json") <(printf '{"permissions": {"allow": ["Bash(make:*)"]}, "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "./own-stop.sh"}]}]}}' | jq -S .) >/dev/null; echo $?)"

[ "$FAIL" = 0 ] || { echo "--- last output"; tail -15 "$T/out"; }
done_tests
