#!/usr/bin/env bash
# timeout: 300 -- about 95s run alone on the Mac (2026-10-13); over 120s beside other slow files
# doctor.test.sh -- the doctor is what the owner runs when something does not
# work, so a break it cannot name is a break the owner hunts by hand. What this
# pins: a fresh setup is all ok and exits 0; each single break is a FAIL line
# that names the broken part and exits 1; and the Claude-only profile is not
# failed for Codex parts it never installed. And the main checkout stays clean:
# after setup no writer of the plugin leaves a line in `git status`, and the
# doctor names running state that git tracks.
set -uo pipefail
. "$(dirname "$0")/install-fixture.sh"
doctor() { run "${1:-$PROJ}" doctor.sh >"$T/out" 2>&1; }
fails() { grep -c "^FAIL $1" "$T/out"; }
# broken <label> <FAIL line start> -- the doctor exits 1 and names it.
broken() { doctor; check "$1: exit 1" 1 $?; check "$1: named" 1 "$(fails "$2")"; }

doctor; check "a project that was never set up: exit 1" 1 $?
check "and the doctor says to run setup" 1 "$(grep -c '^FAIL project.*setup' "$T/out")"

run "$PROJ" setup.sh "${ANSWERS[@]}" >/dev/null 2>&1 || echo "FAIL fixture: setup did not run"
doctor; check "after setup the doctor exits 0" 0 $?
check "with no FAIL line" 0 "$(grep -c '^FAIL' "$T/out")"
check "it names the plugin version" 1 "$(grep -c "^ok  *plugin.*$(jq -r .version "$PLUGIN/.claude-plugin/plugin.json")" "$T/out")"
check "it measured what the hooks put into a session" 1 "$(grep -c '^ok  *hook output' "$T/out")"
check "it checked Codex's five entries" 1 "$(grep -c '^ok  *codex hooks' "$T/out")"

# --- one break at a time, each put back ---
cp "$HOME/.codex/hooks.json" "$T/keep"
sed "s|$PLUGIN/hooks|/old/place/hooks|g" "$T/keep" > "$HOME/.codex/hooks.json"
broken "Codex's entries point at a folder the plugin has left" 'codex hooks'
check "and the fix is named" 1 "$(grep -c '^FAIL codex hooks.*update.sh' "$T/out")"
cp "$T/keep" "$HOME/.codex/hooks.json"

cp "$HOME/.codex/config.toml" "$T/keep"
sed 's/sha256:[0-9a-f]\{64\}/sha256:1111/' "$T/keep" > "$HOME/.codex/config.toml"
broken "a Codex entry that is not trusted" 'codex trust'
grep -v '^notify' "$T/keep" > "$HOME/.codex/config.toml"
doctor; check "no notify line is a warning, not a failure" '0:1' "$?:$(grep -c '^warn codex notify' "$T/out")"
cp "$T/keep" "$HOME/.codex/config.toml"

cp "$PROJ/.claude/commandeck.json" "$T/keep"
jq '.version = 99' "$T/keep" > "$PROJ/.claude/commandeck.json"
broken "a config version the plugin does not know" 'config'
cp "$T/keep" "$PROJ/.claude/commandeck.json"

touch "$T/orca-down"; broken "Orca does not answer" 'orca'; rm "$T/orca-down"
rm "$T/jobs-up"; doctor; check "stopped jobs: exit 1" 1 $?
check "both jobs are named" 2 "$(grep -c '^FAIL \(dashboard job\|main-watch\)' "$T/out")"
touch "$T/jobs-up"

run "$PROJ" dashboard.sh --unregister "$PROJ" >/dev/null 2>&1
broken "the project is not on the dashboard" 'dashboard registry'
run "$PROJ" dashboard.sh --register "$PROJ" >/dev/null 2>&1

chmod -x "$PLUGIN/hooks/git-safety.sh"; broken "a hook file that cannot run" 'hooks'; chmod +x "$PLUGIN/hooks/git-safety.sh"
touch "$T/signed-out"; broken "the review pass cannot run" 'review pass'; rm "$T/signed-out"

doctor; check "everything put back: exit 0 again" 0 $?
# Whether Codex goes through a proxy decides where its model list comes from (#42): said plainly.
check "it says Codex goes direct" 1 "$(grep -c '^ok  *codex route: Codex goes direct to its provider' "$T/out")"
cp "$HOME/.codex/config.toml" "$T/toml"; printf '#!/usr/bin/env bash\nexit 7\n' > "$BIN/curl"; chmod +x "$BIN/curl"
{ printf 'model_provider = "copilot"\n'; cat "$T/toml"; printf '[model_providers.copilot]\nbase_url = "http://localhost:4141/v1"\n'; } > "$HOME/.codex/config.toml"
doctor; check "and names the proxy it goes through" '0 1' "$? $(grep -c '^ok  *codex route: Codex goes through the proxy http://localhost:4141/v1' "$T/out")"
cp "$T/toml" "$HOME/.codex/config.toml"; rm "$BIN/curl"

# --- the main checkout stays clean while the plugin runs ---
# A project whose main checkout is never clean cannot tell its own work from
# the plugin's, and a merge onto it trips over files nobody meant to change.
# Setup hides the running state from git and names the config it wrote, which
# the owner commits: a unit's worktree has that config only from git.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1
check "setup names the config git does not hold yet, and the command that commits it" 1 \
  "$(grep -c "^not committed yet: .claude/commandeck.json .claude/settings.json AGENTS.md\. .*: git -C $PROJ add -f -- " "$T/out")"
eval "$(sed -n 's/^not committed yet: .* has them: //p' "$T/out")" >/dev/null 2>&1
check "with that commit made, git has nothing to report" "" "$(git -C "$PROJ" status --porcelain)"
run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1
check "a second setup has nothing left to name" 0 "$(grep -c '^not committed yet' "$T/out")"
check "and the exclude list is the project's own lines, then each running-state path once" \
  "# local excludes *.swp $(bash -c '. "$0/scripts/paths.sh"; . "$0/scripts/install-lib.sh"; echo "${IL_STATE[*]}"' "$PLUGIN" 2>/dev/null)" \
  "$(paste -sd' ' "$PROJ/.git/info/exclude")"
# Each writer once: a decision, a seat event, a subagent usage row, a Builder event, a build's papers, a line in the to-do.
run "$PROJ" decision.sh add d1 "Ship it?" yes test >/dev/null 2>&1
run "$PROJ" seat-event.sh unit builder task1 "$(date +%s)" >/dev/null 2>&1
SUB=$HOME/.claude/projects/$(printf %s "$PROJ" | tr -c 'A-Za-z0-9' '-')/s1/subagents; mkdir -p "$SUB"
echo '{"type":"assistant","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}}' > "$SUB/agent-a1.jsonl"
touch -d '-20 minutes' "$SUB/agent-a1.jsonl"
run "$PROJ" subagent-usage.sh >/dev/null 2>&1
echo '{"hook_event_name":"SubagentStart","agent_id":"a1","agent_type":"Explore"}' | (cd "$PROJ" && CLAUDE_PROJECT_DIR=$PROJ bash "$PLUGIN/hooks/builder-event-log.sh") >/dev/null 2>&1
mkdir -p "$PROJ/todo" "$PROJ/.claude/briefs"; echo "- next" >> "$PROJ/todo/main-todo.md"; echo notes > "$PROJ/.claude/briefs/u-evidence.md"
check "each writer left its row" "1 1 1 1" "$(cd "$PROJ/.claude" && cat metrics/decisions.jsonl | wc -l | tr -d ' ') $(wc -l < "$PROJ/.claude/metrics/seat-events.jsonl" | tr -d ' ') $(wc -l < "$PROJ/.claude/metrics/subagent-usage.jsonl" | tr -d ' ') $(wc -l < "$PROJ/.claude/builder-events.jsonl" | tr -d ' ')"
check "and git still has nothing to report in the main checkout" "" "$(git -C "$PROJ" status --porcelain)"
# A shared template (_*.md) is batch work the project tracks on purpose; the pass script commits edits to it.
echo template > "$PROJ/.claude/briefs/_shared.md"; git -C "$PROJ" add -f .claude/briefs/_shared.md
doctor; check "the doctor is quiet about running state none of which is tracked, a tracked shared template aside" "0:0" "$?:$(grep -c 'running state' "$T/out")"
git -C "$PROJ" add -f .claude/metrics/decisions.jsonl .claude/briefs/u-evidence.md
doctor; check "running state that git tracks is a warning: the workflow runs, the checkout is never clean" 0 $?
check "each tracked path is named, with the command that untracks it" 1 \
  "$(grep -c "^warn running state: git tracks .claude/metrics/decisions.jsonl .claude/briefs/, .*: git -C $PROJ rm -r --cached -- .claude/metrics/decisions.jsonl .claude/briefs/ ':(exclude).claude/briefs/_\*'$" "$T/out")"
eval "$(sed -n 's/^warn running state: .* keep the files: //p' "$T/out")" >/dev/null 2>&1
doctor; check "that command clears it, keeps the files and leaves the template tracked" "0:d1:notes:A  .claude/briefs/_shared.md" \
  "$?:$(jq -r .id "$PROJ/.claude/metrics/decisions.jsonl" 2>/dev/null | sort -u):$(cat "$PROJ/.claude/briefs/u-evidence.md" 2>/dev/null):$(git -C "$PROJ" status --porcelain)"
git -C "$PROJ" rm -q --cached .claude/briefs/_shared.md
# The merge check runs on a copy that links main's node_modules: a check that installs rewrites main's packages.
cp "$PROJ/.claude/commandeck.json" "$T/keep"
jq '.testCommand = "npm ci && npm test"' "$T/keep" > "$PROJ/.claude/commandeck.json"
doctor; check "a check command that installs packages is a warning, not a failure" '0:1' "$?:$(grep -c '^warn check command: it installs packages' "$T/out")"
jq '.testCommand = "yarn test && npm run install-check"' "$T/keep" > "$PROJ/.claude/commandeck.json"
doctor; check "a check command that only runs tests is not warned about" 0 "$(grep -c '^warn check command' "$T/out")"
cp "$T/keep" "$PROJ/.claude/commandeck.json"

# --- the Claude-only profile has no Codex parts to fail ---
project "$T/proj2"
run "$T/proj2" setup.sh --profile claude >/dev/null 2>&1
touch "$T/signed-out"
# --- the add-on servers the owner may have installed: reported, never installed ---
doctor; check "with no add-on server each is reported as not installed" 2 "$(grep -c '^ok  *add-on server \(serena\|codebase-memory\): not installed' "$T/out")"
printf '{"mcpServers": {"serena": {"command": "uvx"}}, "projects": {"%s": {"mcpServers": {"codebase-memory": {"command": "cbm"}}}}}\n' "$PROJ" > "$HOME/.claude.json"
cp "$HOME/.claude.json" "$T/keep"
doctor; check "a server for the whole machine and one for this project alone are both reported present" 2 "$(grep -c '^ok  *add-on server \(serena\|codebase-memory\): present' "$T/out")"
check "and the doctor leaves the server list as it was" 0 "$(cmp -s "$T/keep" "$HOME/.claude.json"; echo $?)"
rm -f "$HOME/.claude.json"

doctor "$T/proj2"; check "a Claude-only project passes with Codex signed out" 0 $?
check "and no Codex line is printed for it" 0 "$(grep -c 'codex' "$T/out")"

# Uninstall takes its exclude lines back out and leaves the project's own.
run "$PROJ" uninstall.sh >/dev/null 2>&1
check "after uninstall the exclude list is the project's own lines again" "# local excludes *.swp" "$(paste -sd' ' "$PROJ/.git/info/exclude")"

[ "$FAIL" = 0 ] || { echo "--- last output"; cat "$T/out"; }
done_tests
