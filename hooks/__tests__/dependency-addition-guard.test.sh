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

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
