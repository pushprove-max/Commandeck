#!/usr/bin/env bash
# Self-test for dependency-addition-guard.sh. Run directly.
#
# Two tiers, and the manifest tier is the one that changed.
#
#   - What the manifest will SAY after the edit is the question, so the edit is
#     applied to the file on disk and the RESULT's dependency maps are read.
#     Guessing at a fragment's line shapes answered a different question: an
#     engines entry, a script, or any `"key": "value"` in an unrelated section
#     read as a package.
#   - An approved package can now be written into the manifest directly. The
#     install form writes package.json itself, but node_modules in a linked
#     worktree is a symlink to the main checkout's copy, so there was no way to
#     express an approval the hook would accept. The token is an EXACT name, the
#     same shape flag-addition-guard uses.
#
# The command tier is pinned here so the manifest cases are not
# passing on a hook that stopped firing.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/dependency-addition-guard.sh"
PASS=0 FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# The Python manifest the pyproject cases edit: the hook reads the file on disk.
PYP=$TMP/sdk-python/pyproject.toml
mkdir -p "$TMP/sdk-python"
printf '[project]\nname = "sdk"\nversion = "0.1.0"\ndependencies = ["httpx>=0.25.0"]\n' > "$PYP"

MANIFEST="$TMP/package.json"
cat > "$MANIFEST" <<'JSON'
{
  "name": "fixture",
  "version": "1.0.0",
  "scripts": {
    "build": "tsc"
  },
  "engines": {
    "node": ">=24"
  },
  "dependencies": {
    "zod": "^3.22.0"
  },
  "devDependencies": {
    "typescript": "^5.4.0"
  }
}
JSON

check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
# The hook reads the command's directory from the payload's cwd; the fixture
# directory has no node_modules, so only the link cases below see one.
bash_p() { jq -cn --arg c "$1" --arg d "${2:-$TMP}" '{tool_name:"Bash", cwd:$d, tool_input:{command:$c}}'; }
edit()   { jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$o, new_string:$n}}'; }
write()  { jq -cn --arg fp "$1" --arg c "$2" '{tool_name:"Write", tool_input:{file_path:$fp, content:$c}}'; }
run()    { bash "$HOOK" >/dev/null 2>&1 <<<"$1"; echo $?; }
run_env() { env "$1" bash "$HOOK" >/dev/null 2>&1 <<<"$2"; echo $?; }
err()    { bash "$HOOK" 2>&1 >/dev/null <<<"$1"; }

INSTALL="npm ""install"
ADD="yarn ""add"

# --- the command tier ---------------------------------------------
check "installing a package blocks"             2 "$(run "$(bash_p "$INSTALL lodash")")"
check "yarn add blocks"                         2 "$(run "$(bash_p "$ADD lodash")")"
check "a lockfile-driven install passes"        0 "$(run "$(bash_p "npm ci")")"
check "npm install | tee log passes"            0 "$(run "$(bash_p "npm install | tee log")")"
check "a named package before a separator blocks" 2 "$(run "$(bash_p "npm install left-pad && git status")")"
check "an approved install passes"              0 \
  "$(run "$(bash_p "COMMANDECK_DEP_APPROVED=1 $INSTALL lodash")")"

# --- the manifest tier: the maps, not the line shapes -------------------------
DEPS_OLD='"dependencies": {
    "zod": "^3.22.0"'
check "adding a dependency blocks"              2 \
  "$(run "$(edit "$MANIFEST" "$DEPS_OLD" '"dependencies": {
    "lodash": "^4.17.21",
    "zod": "^3.22.0"')")"
check "bumping an existing dependency passes"   0 \
  "$(run "$(edit "$MANIFEST" '"zod": "^3.22.0"' '"zod": "^3.25.0"')")"
check "a new script is not a package"           0 \
  "$(run "$(edit "$MANIFEST" '"build": "tsc"' '"build": "tsc",
    "lint": "eslint"')")"

# --- approval, expressible without an install ---------------------------------
ADD_LODASH=$(edit "$MANIFEST" "$DEPS_OLD" '"dependencies": {
    "lodash": "^4.17.21",
    "zod": "^3.22.0"')
check "an approved package may be written in"   0 \
  "$(run_env COMMANDECK_DEP_APPROVED=lodash "$ADD_LODASH")"
check "approval is exact, not a prefix"         2 \
  "$(run_env COMMANDECK_DEP_APPROVED=lodas "$ADD_LODASH")"

# --- the other payload shapes -------------------------------------------------
FULL=$(cat "$MANIFEST")
check "a full-file Write of the same manifest passes" 0 "$(run "$(write "$MANIFEST" "$FULL")")"
check "a Write that adds a dependency blocks"   2 \
  "$(run "$(write "$MANIFEST" "${FULL/\"zod\": \"^3.22.0\"/\"lodash\": \"^4.17.21\",
    \"zod\": \"^3.22.0\"}")")"

# --- Python manifests and installers -----------------------------------
ROOT=$(git rev-parse --show-toplevel)
PIP="pip ""install"; PIP3="pip3 ""install"; UVADD="uv ""add"
check "pip install blocks"                      2 "$(run "$(bash_p "$PIP requests")")"
check "pip install -r <requirements> passes"    0 "$(run "$(bash_p "$PIP -r ml/requirements.txt")")"
check "a new pyproject dependency blocks"       2 \
  "$(run "$(edit "$PYP" 'dependencies = ["httpx>=0.25.0"]' 'dependencies = ["httpx>=0.25.0", "requests>=2"]')")"
REQ="$TMP/requirements-dev.txt"
printf '# tools\nnumpy==1.26.0\nPillow>=10\n' > "$REQ"
check "a new requirement blocks"                2 "$(run "$(edit "$REQ" 'Pillow>=10' $'Pillow>=10\nrequests==2.0')")"

check "a file that is not a manifest passes"    0 "$(run "$(edit "$TMP/notes.md" 'a' '"lodash": "^4.17.21"')")"
check "malformed JSON passes rather than wedging" 0 "$(run 'not json')"


# --- npm ci through a worker's shared node_modules link -----------------------
# A worker worktree's node_modules is a symlink to the main checkout's copy;
# npm ci there replaced the link and wiped the shared tree for every worktree.
WTX=$TMP/wt
mkdir -p "$TMP/shared/root-modules" "$WTX"
ln -s "$TMP/shared/root-modules" "$WTX/node_modules"
check "npm ci through a linked node_modules blocks" 2 "$(run "$(bash_p "npm ci" "$WTX")")"
check "approval cannot carry npm ci through a link" 2 "$(run "$(bash_p "COMMANDECK_DEP_APPROVED=1 npm ci" "$WTX")")"

# Issue 206: setup.sh only saves its quoted answers (a test command such as 'npm test') and never runs them, so its
# own preview is a sender of its quoted text; setup's answers `add` and `install` had joined 'npm test' into an install.
SETUP=$(cd "$(dirname "$0")/../.." && pwd)/scripts/setup.sh
mkdir -p "$TMP/h"; ln -s "${SETUP%/scripts/setup.sh}" "$TMP/h/plug"
check "the plugin's own setup preview with --auto-mode add is not blocked" 0 \
  "$(run "$(bash_p "bash $SETUP --profile claude --test-command 'npm test' --auto-mode add --worker-cache-ttl 5m --plan")")"
check "the plugin's own setup preview with install answers, named through ~, is not blocked" 0 \
  "$(run_env HOME="$TMP/h" "$(bash_p "bash ~/plug/scripts/setup.sh --test-command 'npm test' --global-claude merge --global-rules install --rules merge --plan")")"
check "another setup.sh with the same flags still blocks" 2 \
  "$(run "$(bash_p "bash ./other/setup.sh --test-command 'npm test' --auto-mode add --worker-cache-ttl 5m --plan")")"
check "an install after the plugin's setup on the same line still blocks" 2 \
  "$(run "$(bash_p "bash $SETUP --test-command 'npm test' --plan && npm install lodash")")"
check "a quoted install run by bash -c beside the plugin's setup still blocks" 2 \
  "$(run "$(bash_p "bash $SETUP --plan; bash -c 'npm install lodash'")")"

# Issue 311: after a plugin update the hook that fires and the setup.sh on the line sit in two different version
# folders of the plugin cache, so the sibling-path check refused the owner's own preview and apply.
# Only the cache under the Claude config folder is trusted: a cache-shaped path anywhere else is screened.
PC=$TMP/home/.claude/plugins/cache/commandeck/commandeck EVIL=$TMP/evil/plugins/cache/commandeck/commandeck/0.25.3
mkdir -p "$PC/0.25.2" "$PC/0.25.3/scripts" "$EVIL/scripts" "$PC/0.25.3/x/scripts"
cp -R "${HOOK%/*}" "$PC/0.25.2/hooks"
# The cache copy is the plugin's own setup.sh, as an install writes it; the look-alikes run their first argument.
cp "$SETUP" "$PC/0.25.3/scripts/setup.sh"
for s in "$EVIL/scripts" "$PC/0.25.3/x/scripts"; do printf '#!/bin/sh\nsh -c "$1"\n' > "$s/setup.sh"; done
OLD_HOOK=$PC/0.25.2/hooks/dependency-addition-guard.sh
run_old() { env -u CLAUDE_CONFIG_DIR HOME="$TMP/home" ${2:+CLAUDE_CONFIG_DIR="$2"} bash "$OLD_HOOK" >/dev/null 2>&1 <<<"$1"; echo $?; }
ISSUE_ARGS="--profile claude-openai --scope machine --global-rules merge --global-claude merge --builder-model sonnet --builder-effort high --standard-context --builder-clear-line 140k --issue-sizing '' --plan-models opus,sonnet,sol,astra --plan-fast '' --name '' --persona '' --dashboard --bind 127.0.0.1 --hosts '' --test-command 'npm test' --full-suite off --no-strict --worker-cache-ttl 5m --auto-mode add --worker-skills-off '' --worker-plugins-off '' --max-rounds '' --closing-pass yes --small-build '' --max-review-min '' --max-test-percent '' --max-usd '' --no-codex-fast"
check "issue 311's preview, hook and setup.sh in two version folders, is not blocked" 0 \
  "$(run_old "$(bash_p "bash ~/.claude/plugins/cache/commandeck/commandeck/0.25.3/scripts/setup.sh $ISSUE_ARGS --plan")")"
check "issue 311's apply, hook and setup.sh in two version folders, is not blocked" 0 \
  "$(run_old "$(bash_p "bash ~/.claude/plugins/cache/commandeck/commandeck/0.25.3/scripts/setup.sh $ISSUE_ARGS")")"
check "an install after the cache setup.sh on the same line still blocks" 2 \
  "$(run_old "$(bash_p "bash ~/.claude/plugins/cache/commandeck/commandeck/0.25.3/scripts/setup.sh $ISSUE_ARGS --plan && $INSTALL lodash")")"
check "a cache-shaped setup.sh outside the Claude config folder still blocks" 2 \
  "$(run_old "$(bash_p "bash $EVIL/scripts/setup.sh 'npm install lodash'")")"
check "a setup.sh nested deeper than a version folder still blocks" 2 \
  "$(run_old "$(bash_p "bash ~/.claude/plugins/cache/commandeck/commandeck/0.25.3/x/scripts/setup.sh $ISSUE_ARGS --plan")")"
# The trusted cache follows CLAUDE_CONFIG_DIR, as Claude Code's own does; reached by a link it is the same folder.
ln -s "$TMP/home/.claude" "$TMP/cfg"
check "the preview passes when CLAUDE_CONFIG_DIR names the config folder by a link" 0 \
  "$(run_old "$(bash_p "bash $TMP/cfg/plugins/cache/commandeck/commandeck/0.25.3/scripts/setup.sh $ISSUE_ARGS --plan")" "$TMP/cfg")"
check "a cache outside CLAUDE_CONFIG_DIR still blocks" 2 \
  "$(run_old "$(bash_p "bash ~/.claude/plugins/cache/commandeck/commandeck/0.25.3/scripts/setup.sh $ISSUE_ARGS --plan")" "$TMP/evil")"
ln -s "$EVIL" "$PC/0.25.4"
check "a cache entry that links out of the cache still blocks" 2 \
  "$(run_old "$(bash_p "bash ~/.claude/plugins/cache/commandeck/commandeck/0.25.4/scripts/setup.sh $ISSUE_ARGS --plan")")"

# Issue 311, related: a here-document with a quoted end word is data whichever command shares the line.
HD=$'use npm install lodash and yarn add left-pad\n'
check "a heredoc body naming installs beside a cd is not blocked" 0 \
  "$(run "$(bash_p "cd $TMP && cat > b.md <<'EOF'"$'\n'"${HD}EOF"$'\n'"gh issue create --body-file b.md")")"
check "a dash heredoc body beside mkdir is not blocked" 0 \
  "$(run "$(bash_p "mkdir -p $TMP/d && cat > b.md <<-'EOF'"$'\n'"${HD}EOF"$'\n'"gh issue create --body-file b.md")")"
check "a real install after such a heredoc still blocks" 2 \
  "$(run "$(bash_p "cd $TMP && cat > b.md <<'EOF'"$'\n'"${HD}EOF"$'\n'"$INSTALL left-pad")")"
check "a << inside a quoted string hides no install after it" 2 \
  "$(run "$(bash_p "ls && echo \"x <<'EOF'\""$'\n'"$INSTALL left-pad"$'\n'"EOF")")"
# A body is data only when a sender reads it and sends it nowhere else: a shell, or a pipe on to one, runs it.
for H in "bash <<'EOF'" "sh <<'EOF'" "cd $TMP && sh -s <<-'EOF'" "cat <<'EOF' | bash" "cat <<'EOF' > >(sh)" "python3 - <<\\EOF" \
  "(bash; echo done) <<'EOF'" "(sh; printf done) <<'EOF'" "(bash; cat ) <<'EOF'" "bash -s -- \"report (cat adoption)\" <<'EOF'"; do
  check "a heredoc body run by: $H still blocks" 2 "$(run "$(bash_p "$H"$'\n'"$INSTALL lodash"$'\n'"EOF")")"
done

# Message cuts: a blocked package is no question for main; the worker records it and goes on. Both blocks say so.
DEFER='record it as a main-only deferred item (one line under ## Main-only (deferred) in the evidence file) and go on without it; do not ask main'
check "the new-dependency block tells the worker to record a main-only deferred item" 1 \
  "$(err "$(bash_p "$INSTALL lodash")" | grep -c -F "$DEFER")"
check "and so does the manifest block" 1 \
  "$(err "$(edit "$MANIFEST" "$DEPS_OLD" '"dependencies": {
    "left-pad": "^1.0.0",
    "zod": "^3.22.0"')" | grep -c -F "$DEFER")"

# --- a manifest that is not JSON, before or after the edit (host issue 3029) -----
# The line-shape screen read a metadata key as a package: the block named `check`, which the worker had only edited.
mkdir -p "$TMP/bad" "$TMP/ok"
BAD=$TMP/bad/package.json; OK=$TMP/ok/package.json
printf '{"scripts":{"build":"tsc",},"dependencies":{"zod":"^3.22.0"}}\n' > "$BAD"
printf '{"scripts":{"check":"old"}}\n' > "$OK"
check "an edit to an invalid package.json blocks, naming the file and not a package" "2:1:0" \
  "$(run "$(edit "$BAD" '"zod": "^3.22.0"' '"zod": "^3.22.0", "left-pad": "^1.0.0"')"):$(err "$(edit "$BAD" '"zod": "^3.22.0"' '"zod": "^3.22.0", "left-pad": "^1.0.0"')" | grep -c "$BAD is not valid JSON"):$(err "$(edit "$BAD" '"zod": "^3.22.0"' '"zod": "^3.22.0", "left-pad": "^1.0.0"')" | grep -c "left-pad")"
check "an edit to an invalid package.json that adds nothing to screen passes" 0 \
  "$(run "$(edit "$BAD" '"build"' '"compile"')")"
check "a Write of valid JSON over an invalid package.json is screened, not refused for the old file" "2:0" \
  "$(run "$(write "$BAD" '{"dependencies":{"left-pad":"^1.0.0"}}')"):$(err "$(write "$BAD" '{"dependencies":{"left-pad":"^1.0.0"}}')" | grep -c 'not valid JSON')"
EDIT_BREAK=$(edit "$OK" '"check":"old"' '"check":"new",')
check "an Edit that leaves the manifest as invalid JSON blocks as invalid and does not name the script as a package" "2:1:0" \
  "$(run "$EDIT_BREAK"):$(err "$EDIT_BREAK" | grep -c "leaves $OK as invalid JSON"):$(err "$EDIT_BREAK" | grep -c "adding a new dependency")"
check "a valid edit of a valid file is screened as before: a bump passes, an added package still blocks by name" "0:2:1" \
  "$(run "$(edit "$OK" '"check":"old"' '"check":"new"')"):$(run "$(edit "$OK" '"check":"old"' '"check":"old"},"dependencies":{"lodash":"^4.0.0"')"):$(err "$(edit "$OK" '"check":"old"' '"check":"old"},"dependencies":{"lodash":"^4.0.0"')" | grep -c "'lodash'")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
