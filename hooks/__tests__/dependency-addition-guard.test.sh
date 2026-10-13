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
# The command tier is unchanged and pinned here so the manifest cases are not
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

# --- the command tier, unchanged ---------------------------------------------
check "installing a package blocks"             2 "$(run "$(bash_p "$INSTALL lodash")")"
check "yarn add blocks"                         2 "$(run "$(bash_p "$ADD lodash")")"
check "a lockfile-driven install passes"        0 "$(run "$(bash_p "npm ci")")"
# A bare install names no package: what follows a separator is the next command.
check "npm install && git status passes"        0 "$(run "$(bash_p "npm install && git status")")"
check "npm install; ls passes"                  0 "$(run "$(bash_p "npm install; ls")")"
check "npm install | tee log passes"            0 "$(run "$(bash_p "npm install | tee log")")"
check "a named package before a separator blocks" 2 "$(run "$(bash_p "npm install left-pad && git status")")"
check "an approved install passes"              0 \
  "$(run "$(bash_p "COMMANDECK_DEP_APPROVED=1 $INSTALL lodash")")"
check "a second install after an approved one blocks" 2 \
  "$(run "$(bash_p "COMMANDECK_DEP_APPROVED=1 $INSTALL lodash && $INSTALL sneaky")")"

# --- the manifest tier: the maps, not the line shapes -------------------------
DEPS_OLD='"dependencies": {
    "zod": "^3.22.0"'
check "adding a dependency blocks"              2 \
  "$(run "$(edit "$MANIFEST" "$DEPS_OLD" '"dependencies": {
    "lodash": "^4.17.21",
    "zod": "^3.22.0"')")"
check "the block names the package"             0 \
  "$(err "$(edit "$MANIFEST" "$DEPS_OLD" '"dependencies": {
    "lodash": "^4.17.21",
    "zod": "^3.22.0"')" | grep -qF "'lodash'" && echo 0 || echo 1)"
check "adding a devDependency blocks"           2 \
  "$(run "$(edit "$MANIFEST" '"typescript": "^5.4.0"' '"typescript": "^5.4.0",
    "vitest": "^2.0.0"')")"
check "bumping an existing dependency passes"   0 \
  "$(run "$(edit "$MANIFEST" '"zod": "^3.22.0"' '"zod": "^3.25.0"')")"
check "a version bump is SILENT"                "" \
  "$(bash "$HOOK" 2>&1 <<<"$(edit "$MANIFEST" '"zod": "^3.22.0"' '"zod": "^3.25.0"')")"
check "removing a dependency passes"            0 \
  "$(run "$(edit "$MANIFEST" '  "devDependencies": {
    "typescript": "^5.4.0"
  }
' '')")"

# The false-positive class the line-shape scan produced: any `"key": "value"`
# pair outside a dependency map read as a package.
check "a new script is not a package"           0 \
  "$(run "$(edit "$MANIFEST" '"build": "tsc"' '"build": "tsc",
    "lint": "eslint"')")"
check "a new engines entry is not a package"    0 \
  "$(run "$(edit "$MANIFEST" '"node": ">=24"' '"node": ">=24",
    "npm": ">=10"')")"
check "a new top-level field is not a package"  0 \
  "$(run "$(edit "$MANIFEST" '"name": "fixture"' '"name": "fixture",
  "license": "UNLICENSED"')")"
check "a script addition is SILENT"             "" \
  "$(bash "$HOOK" 2>&1 <<<"$(edit "$MANIFEST" '"build": "tsc"' '"build": "tsc",
    "lint": "eslint"')")"

# --- approval, expressible without an install ---------------------------------
ADD_LODASH=$(edit "$MANIFEST" "$DEPS_OLD" '"dependencies": {
    "lodash": "^4.17.21",
    "zod": "^3.22.0"')
check "an approved package may be written in"   0 \
  "$(run_env COMMANDECK_DEP_APPROVED=lodash "$ADD_LODASH")"
check "an approved write is SILENT"             "" \
  "$(env COMMANDECK_DEP_APPROVED=lodash bash "$HOOK" 2>&1 <<<"$ADD_LODASH")"
check "approval is exact, not a prefix"         2 \
  "$(run_env COMMANDECK_DEP_APPROVED=lodas "$ADD_LODASH")"
check "approving a different package does not help" 2 \
  "$(run_env COMMANDECK_DEP_APPROVED=ramda "$ADD_LODASH")"
check "several approvals are comma-separated"   0 \
  "$(run_env COMMANDECK_DEP_APPROVED=ramda,lodash "$ADD_LODASH")"
check "an unapproved package alongside an approved one blocks" 2 \
  "$(run_env COMMANDECK_DEP_APPROVED=lodash "$(edit "$MANIFEST" "$DEPS_OLD" '"dependencies": {
    "lodash": "^4.17.21",
    "sneaky": "^1.0.0",
    "zod": "^3.22.0"')")"
check "the block names the env form"            0 \
  "$(err "$ADD_LODASH" | grep -qF 'COMMANDECK_DEP_APPROVED=lodash' && echo 0 || echo 1)"

# --- the other payload shapes -------------------------------------------------
FULL=$(cat "$MANIFEST")
check "a full-file Write of the same manifest passes" 0 "$(run "$(write "$MANIFEST" "$FULL")")"
check "a Write that adds a dependency blocks"   2 \
  "$(run "$(write "$MANIFEST" "${FULL/\"zod\": \"^3.22.0\"/\"lodash\": \"^4.17.21\",
    \"zod\": \"^3.22.0\"}")")"
check "a MultiEdit adding a dep in a later hunk blocks" 2 \
  "$(run "$(jq -cn --arg fp "$MANIFEST" '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[
    {old_string:"\"build\": \"tsc\"", new_string:"\"build\": \"tsc --noEmit\""},
    {old_string:"\"zod\": \"^3.22.0\"", new_string:"\"lodash\": \"^4.17.21\",\n    \"zod\": \"^3.22.0\""}]}}')")"

# A brand-new manifest is a new dependency surface in itself.
check "a NEW package.json with a dependency blocks" 2 \
  "$(run "$(write "$TMP/sub/package.json" '{"name":"sub","dependencies":{"lodash":"^4.17.21"}}')")"
check "a NEW package.json with no dependency passes" 0 \
  "$(run "$(write "$TMP/sub/package.json" '{"name":"sub","scripts":{"build":"tsc"}}')")"
check "an approved package in a NEW package.json passes" 0 \
  "$(run_env COMMANDECK_DEP_APPROVED=lodash "$(write "$TMP/sub/package.json" '{"name":"sub","dependencies":{"lodash":"^4.17.21"}}')")"

# --- Python manifests and installers -----------------------------------
ROOT=$(git rev-parse --show-toplevel)
PIP="pip ""install"; PIP3="pip3 ""install"; UVADD="uv ""add"
check "pip install blocks"                      2 "$(run "$(bash_p "$PIP requests")")"
check "pip3 install blocks"                     2 "$(run "$(bash_p "$PIP3 requests")")"
check "uv add blocks"                           2 "$(run "$(bash_p "$UVADD requests")")"
check "a pip install after && blocks"           2 "$(run "$(bash_p "cd ml && $PIP -U requests")")"
check "pip install -r <requirements> passes"    0 "$(run "$(bash_p "$PIP -r ml/requirements.txt")")"
check "pip install -r <requirements> && pytest passes" 0 "$(run "$(bash_p "$PIP -r ml/requirements.txt && pytest")")"
check "pip install -r plus a package blocks"   2 "$(run "$(bash_p "$PIP -r requirements.txt requests")")"
check "an approved pip install passes"          0 "$(run "$(bash_p "COMMANDECK_DEP_APPROVED=1 $PIP requests")")"
for m in svc/barcode/requirements.txt ml/requirements.txt; do
  check "a new line in $m blocks"               2 "$(run "$(edit "$ROOT/$m" '' $'\nzz-not-a-dep==2.0\n')")"
done
check "a new pyproject dependency blocks"       2 \
  "$(run "$(edit "$PYP" 'dependencies = ["httpx>=0.25.0"]' 'dependencies = ["httpx>=0.25.0", "requests>=2"]')")"
check "the pyproject block names the package"   0 \
  "$(err "$(edit "$PYP" 'dependencies = ["httpx>=0.25.0"]' 'dependencies = ["httpx>=0.25.0", "requests>=2"]')" | grep -qF "'requests'" && echo 0 || echo 1)"
check "bumping a pyproject dependency passes"   0 \
  "$(run "$(edit "$PYP" 'httpx>=0.25.0' 'httpx>=0.27.0')")"
check "a pyproject metadata edit passes"        0 \
  "$(run "$(edit "$PYP" 'version = "0.1.0"' 'version = "0.2.0"')")"
REQ="$TMP/requirements-dev.txt"
printf '# tools\nnumpy==1.26.0\nPillow>=10\n' > "$REQ"
check "bumping a requirement passes"            0 "$(run "$(edit "$REQ" 'numpy==1.26.0' 'numpy==2.0.0')")"
check "a comment line in requirements passes"   0 "$(run "$(edit "$REQ" '# tools' $'# tools\n# pinned for the box')")"
check "a requirement differing only in case passes" 0 "$(run "$(edit "$REQ" 'Pillow>=10' 'pillow>=11')")"
check "a new requirement blocks"                2 "$(run "$(edit "$REQ" 'Pillow>=10' $'Pillow>=10\nrequests==2.0')")"
check "an approved requirement passes"          0 \
  "$(run_env COMMANDECK_DEP_APPROVED=requests "$(edit "$REQ" 'Pillow>=10' $'Pillow>=10\nrequests==2.0')")"
check "a NEW requirements file with a package blocks" 2 "$(run "$(write "$TMP/py/requirements.txt" 'requests==2.0')")"

check "a file that is not a manifest passes"    0 "$(run "$(edit "$TMP/notes.md" 'a' '"lodash": "^4.17.21"')")"
check "malformed JSON passes rather than wedging" 0 "$(run 'not json')"

# --- npm ci through a worker's shared node_modules link -----------------------
# A worker worktree's node_modules is a symlink to the main checkout's copy;
# npm ci there replaced the link and wiped the shared tree for every worktree.
WTX=$TMP/wt
mkdir -p "$TMP/shared/root-modules" "$TMP/shared/web-modules" "$WTX/web" "$WTX/infra/node_modules" "$TMP/broken"
ln -s "$TMP/shared/root-modules" "$WTX/node_modules"
ln -s "$TMP/shared/web-modules" "$WTX/web/node_modules"
ln -s "$TMP/shared/gone" "$TMP/broken/node_modules"
check "npm ci through a linked node_modules blocks" 2 "$(run "$(bash_p "npm ci" "$WTX")")"
check "approval cannot carry npm ci through a link" 2 "$(run "$(bash_p "COMMANDECK_DEP_APPROVED=1 npm ci" "$WTX")")"
check "cd web && npm ci through web's link blocks" 2 "$(run "$(bash_p "cd web && npm ci" "$WTX")")"
check "npm --prefix web ci blocks" 2 "$(run "$(bash_p "npm --prefix web ci" "$WTX")")"
check "npm ci --prefix web blocks" 2 "$(run "$(bash_p "npm ci --prefix web" "$WTX")")"
# A quoted folder is the same folder.
check "cd \"web\" && npm ci blocks" 2 "$(run "$(bash_p 'cd "web" && npm ci' "$WTX")")"
check "npm ci --prefix 'web' blocks" 2 "$(run "$(bash_p "npm ci --prefix 'web'" "$WTX")")"
# A folder with a space in its name is one folder, quoted or escaped.
mkdir -p "$WTX/my apps"; ln -s "$TMP/shared/web-modules" "$WTX/my apps/node_modules"
check "npm --prefix \"my apps\" ci blocks" 2 "$(run "$(bash_p 'npm --prefix "my apps" ci' "$WTX")")"
check "npm ci --prefix='my apps' blocks" 2 "$(run "$(bash_p "npm ci --prefix='my apps'" "$WTX")")"
check "cd my\\ apps && npm ci blocks" 2 "$(run "$(bash_p 'cd my\ apps && npm ci' "$WTX")")"
check "cd \"my apps\" && npm ci blocks" 2 "$(run "$(bash_p 'cd "my apps" && npm ci' "$WTX")")"
check "npm ci from inside web blocks" 2 "$(run "$(bash_p "npm ci" "$WTX/web")")"
check "npm ci onto a broken link blocks" 2 "$(run "$(bash_p "npm ci" "$TMP/broken")")"
check "npm ci into infra's real node_modules passes from inside infra" 0 "$(run "$(bash_p "npm ci" "$WTX/infra")")"
# One command line may install twice: each npm ci is checked in its own folder,
# not only the one a --prefix names.
check "npm ci && npm --prefix infra ci blocks on the first" 2 "$(run "$(bash_p "npm ci && npm --prefix infra ci" "$WTX")")"
check "npm --prefix infra ci; npm ci blocks on the second" 2 "$(run "$(bash_p "npm --prefix infra ci; npm ci" "$WTX")")"
check "cd infra && npm ci && npm --prefix ../web ci blocks on the second" 2 "$(run "$(bash_p "cd infra && npm ci && npm --prefix ../web ci" "$WTX")")"
check "two installs into real folders pass" 0 "$(run "$(bash_p "npm --prefix infra ci && npm --prefix infra ci" "$WTX")")"
check "npm --prefix infra ci passes" 0 "$(run "$(bash_p "npm --prefix infra ci" "$WTX")")"
check "the refusal names the link's target" 1 "$(err "$(bash_p "npm ci" "$WTX")" | grep -c "$TMP/shared/root-modules")"
check "a refused command leaves the link in place" "$TMP/shared/root-modules" "$(readlink "$WTX/node_modules")"
check "npm ci into infra's real node_modules passes from inside infra" 0 "$(run "$(bash_p "npm ci" "$WTX/infra")")"
# Every npm ci on the line is checked in ITS OWN folder. One
# folder was taken for the whole line, so a first `npm ci` at the linked root
# ran behind a second one aimed at a real folder; a quoted folder was looked up
# with its quotes on.
ci_blocks() { for C in "$@"; do check "npm ci blocks: $C" 2 "$(run "$(bash_p "$C" "$WTX")")"; done; }
ci_passes() { for C in "$@"; do check "npm ci passes: $C" 0 "$(run "$(bash_p "$C" "$WTX")")"; done; }
ci_blocks 'npm ci && npm --prefix infra ci' 'npm --prefix infra ci && npm ci' 'npm --prefix infra ci; npm ci' \
  'cd "web" && npm ci' "cd 'web' && npm ci" 'npm --prefix "web" ci' 'npm --prefix=web ci' \
  'cd infra && npm ci && cd ../web && npm ci' 'cd infra && npm ci; cd .. && npm ci' '(cd infra && npm ci) && npm ci' \
  'cd infra || npm ci' 'cd infra & npm ci' 'cd infra | npm ci' 'cd web; npm ci' 'pushd web && npm ci' \
  'cd infra && npm --prefix ../web ci' 'cd infra && npm --prefix .. ci' "$(printf 'cd infra\nnpm ci\ncd ..\nnpm ci')" \
  'echo "$(cd web && npm ci)"' 'FOO=1 npm ci' \
  'cd no-such-folder; npm ci' "$(printf 'cd no-such-folder\nnpm ci')" 'cd infra; cd no-such-folder; npm --prefix .. ci'
# The guard does not follow the shell's folder moves (ruling 8): which `cd` took
# effect depends on `&&`, `||`, `;`, subshells and exit codes, and each shape it
# guessed wrong let an install through at the linked root. An npm ci is judged in
# EVERY folder the line could be in, the starting one and each cd/pushd target
# that exists, and passes only when none of them holds a link.
ci_blocks 'cd no-such-folder && echo skipped; npm ci' 'cd no-such-folder || npm ci' '(cd infra); npm ci' \
  'cd infra && false; npm ci' 'if true; then cd web; fi; npm --prefix . ci' 'cd no-such-folder && npm ci' \
  'cd infra && npm ci' 'cd "infra" && npm ci' "cd 'infra' && npm ci" 'cd web && cd ../infra && npm ci' 'cd infra; npm ci' '(cd infra && npm ci) && git status' "$(printf 'cd infra\nnpm ci')"
# A folder the guard cannot read could be the linked one, so it blocks.
ci_blocks 'cd "$SOMEWHERE" && npm ci' 'cd "$(git rev-parse --show-toplevel)" && npm ci' 'npm --prefix "$SOMEWHERE" ci' 'cd `pwd`/infra && npm ci'
check "the refusal for a move it cannot follow says the way out" 1 \
  "$(err "$(bash_p "cd infra && npm ci" "$WTX")" | grep -c 'Run it from the folder itself, or name the folder: npm --prefix <folder> ci')"
ci_passes 'npm --prefix infra ci' 'npm --prefix "infra" ci && git status' 'cd web && npm --prefix ../infra ci' \
  "npm --prefix '$WTX/infra' ci" 'cd web && git status && npm --version' 'cd web && npm run build'
# Run from the folder itself, every folder on the line is a real one.
mkdir -p "$WTX/infra/sub/node_modules"
for C in 'npm ci' 'cd sub && npm ci' 'cd sub || npm ci' '(cd sub && npm ci); npm ci' "cd 'sub' && npm ci"; do
  check "npm ci passes from inside infra: $C" 0 "$(run "$(bash_p "$C" "$WTX/infra")")"
done
# Where `cd -` and `popd` go was set by an earlier command, and an option or a
# pattern is not a folder name the guard can look up: each blocks, even from a
# folder whose own modules are real.
for C in 'cd - && npm ci' 'popd && npm ci' 'pushd +1 && npm ci' 'cd -P sub && npm ci' 'cd su* && npm ci' 'cd {sub,..} && npm ci' 'npm --prefix su? ci'; do
  check "npm ci blocks from inside infra: $C" 2 "$(run "$(bash_p "$C" "$WTX/infra")")"
done

# A replace-all edit is applied to EVERY occurrence. Applied to the first
# only, the rename below changed the script name and left the dependency map as
# it was, so the new package it writes there was never seen.
mkdir -p "$TMP/ra"; RA="$TMP/ra/package.json"
printf '{\n  "scripts": {\n    "jest": "jest"\n  },\n  "devDependencies": {\n    "jest": "^29.0.0",\n    "ts-jest": "^29.0.0"\n  }\n}\n' > "$RA"
edit_all() { jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$o, new_string:$n, replace_all:true}}'; }
check "a replace-all rename of a repeated key into a new package blocks" 2 "$(run "$(edit_all "$RA" '"jest":' '"vitest":')")"
check "the refusal names the package the rename adds" 1 "$(bash "$HOOK" 2>&1 >/dev/null <<<"$(edit_all "$RA" '"jest":' '"vitest":')" | grep -c "'vitest'")"
check "a replace-all edit that adds no name passes" 0 "$(run "$(edit_all "$RA" '"^29.0.0"' '"^30.0.0"')")"
# Old text that is in the file twice cannot be placed: a Codex hunk goes where
# its anchor says, which this hook never sees, so reading it as the FIRST match
# passed a rename that really landed in the dependency map. Claude's own Edit
# refuses such an edit anyway.
check "a rename whose old text is in the file twice blocks without replace-all" 2 "$(run "$(edit "$RA" '"jest":' '"vitest":')")"
check "and the refusal says the text is there more than once" 1 "$(bash "$HOOK" 2>&1 >/dev/null <<<"$(edit "$RA" '"jest":' '"vitest":')" | grep -c 'more than once')"
check "the same rename with enough of its line to be the only match passes" 0 "$(run "$(edit "$RA" '"jest": "jest"' '"vitest": "jest"')")"
# The shape a two-hunk Codex patch arrives in: the second hunk's text is in the
# script map and the dependency map alike.
mkdir -p "$TMP/tw"; printf '{\n  "name": "a",\n  "scripts": {\n    "left-pad": "1.3.0"\n  },\n  "dependencies": {\n    "left-pad": "1.3.0"\n  }\n}\n' > "$TMP/tw/package.json"
check "a two-edit change whose second edit could land in either map blocks" 2 "$(run "$(jq -cn --arg fp "$TMP/tw/package.json" \
  '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[{old_string:"\"name\": \"a\"", new_string:"\"name\": \"b\""}, {old_string:"\"left-pad\": \"1.3.0\"", new_string:"\"is-odd\": \"1.3.0\""}]}}')")"
printf '# was flask==1.0 before\nflask==1.0\nrequests==2.0\n' > "$TMP/requirements-twice.txt"
check "a requirements edit whose old text is in the file twice blocks" 2 "$(run "$(edit "$TMP/requirements-twice.txt" 'flask==1.0' 'requests==2.0')")"

# A bare URL requirement counts whole, as an option line does. Every one
# read as the name `https`, so a second URL to a different package was not new.
URLREQ="$TMP/requirements-url.txt"
printf 'https://a.example/one-1.0-py3-none-any.whl\nrequests==2.0\n' > "$URLREQ"
check "a second URL requirement blocks" 2 \
  "$(run "$(edit "$URLREQ" 'requests==2.0' $'requests==2.0\nhttps://b.example/two-2.0-py3-none-any.whl')")"
check "a VCS URL requirement blocks" 2 \
  "$(run "$(edit "$URLREQ" 'requests==2.0' $'requests==2.0\ngit+https://b.example/two.git@v2')")"
check "the refusal names the URL" 1 \
  "$(bash "$HOOK" 2>&1 >/dev/null <<<"$(edit "$URLREQ" 'requests==2.0' $'requests==2.0\nhttps://b.example/two-2.0-py3-none-any.whl')" | grep -c "('https://b.example/two-2.0-py3-none-any.whl'")"
check "another line of a manifest that holds a URL requirement still edits" 0 "$(run "$(edit "$URLREQ" 'requests==2.0' 'requests==2.1')")"
check "a named URL requirement is still read by its name" 0 \
  "$(run "$(edit "$URLREQ" 'requests==2.0' 'requests @ https://a.example/requests-2.1.whl')")"

# A bare install is lockfile-driven whatever follows it, and a flag's
# value is not a package. `npm install && git status` and `npm install --prefix
# web` blocked; `npm --prefix web i lodash` ran.
for C in "$INSTALL && git status" "$INSTALL; git status" "$INSTALL | tee /tmp/log" "$INSTALL || true" "($INSTALL)" \
  "$INSTALL --prefix web" "$INSTALL --prefix=web" "npm --prefix web install" "npm i --prefix web && npm run build" \
  "$INSTALL --workspace web" "$INSTALL -w web" "$INSTALL --loglevel error" "$INSTALL --registry https://r.example --prefix web" \
  "$INSTALL 2>&1 | tail -5" "$INSTALL > /tmp/log 2>&1" "$INSTALL >/tmp/log" "pip install -r requirements.txt 2>&1 | tail -5"; do
  check "passes: $C" 0 "$(run "$(bash_p "$C")")"
done
for C in "npm --prefix web i lodash" "$INSTALL --prefix web lodash" "$INSTALL lodash --prefix web" "npm --prefix web install lodash" \
  "$INSTALL --workspace web lodash" "$INSTALL && $INSTALL lodash" "$INSTALL --prefix web; $ADD lodash" "yarn --cwd web add lodash" \
  "$INSTALL lodash 2>&1" "$INSTALL > /tmp/log lodash" "pnpm add -w lodash" "pip install requests 2>&1"; do
  check "blocks: $C" 2 "$(run "$(bash_p "$C")")"
done

# Where a Codex hunk lands. Tried on Codex's own patch tool (0.162.1): a
# hunk with repeated context goes after its `@@` anchor, which this hook never
# sees, and a hunk with no context goes to the END of the file whatever its
# anchor says. So repeated context is refused, never guessed, and an edit with
# no old text is read at the end of the file.
PYT=$TMP/py; mkdir -p "$PYT"
printf '[project]\nname = "x"\ndependencies = [\n  "httpx>=0.25",\n]\n\n[tool.other]\nextras = [\n  "httpx>=0.25",\n]\n' > "$PYT/pyproject.toml"
check "a pyproject hunk whose context is under [project] and a later table blocks" 2 \
  "$(run "$(edit "$PYT/pyproject.toml" $'  "httpx>=0.25",\n]' $'  "httpx>=0.25",\n  "requests>=2",\n]')")"
check "and the refusal says the text is there more than once" 1 \
  "$(err "$(edit "$PYT/pyproject.toml" $'  "httpx>=0.25",\n]' $'  "httpx>=0.25",\n  "requests>=2",\n]')" | grep -c 'more than once')"
check "the same hunk with its table header, so it matches once, is read: a new name blocks" 1 \
  "$(err "$(edit "$PYT/pyproject.toml" $'dependencies = [\n  "httpx>=0.25",\n]' $'dependencies = [\n  "httpx>=0.25",\n  "requests>=2",\n]')" | grep -c "'requests'")"
check "a hunk with no context is read at the end of the file: a list item there is no manifest, and blocks" 2 \
  "$(run "$(edit "$PYT/pyproject.toml" '' $'  "requests>=2",\n')")"
check "a key added with no context lands in the last table, as Codex writes it, and is no dependency" 0 \
  "$(run "$(edit "$PYT/pyproject.toml" '' $'note = "x"\n')")"
check "a new table of dependencies added with no context blocks" 2 \
  "$(run "$(edit "$PYT/pyproject.toml" '' $'\n[dependency-groups]\ndev = ["requests>=2"]\n')")"

# The quoted text of a sender (gh, orca, orca-ide, git, echo, printf,
# cat) is a message, not a command, when every command on the line is one. A
# send and an issue body that DESCRIBED an install were blocked. Run from the
# linked root, so the npm ci each one names would block if it were read.
for C in "orca-ide orchestration send --type question --body \"blocked on: cd web && npm ci, then $INSTALL lodash\"" \
  "gh issue create --title t --body \"the guard refuses bash -c 'cd web && $INSTALL lodash' and sh -c 'npm ci'\"" \
  "git commit -m '$INSTALL lodash is refused; so is pip install requests'" \
  "gh issue create --body \"$(printf 'first line\n%s lodash\nnpm ci\n%s lodash' "$INSTALL" "$ADD")\"" \
  "$(printf "gh issue create --body-file - <<'EOF'\n%s lodash\ncd web && npm ci\nEOF" "$INSTALL")" \
  "echo 'pnpm add lodash' && git status"; do
  check "a message that names an install passes: $C" 0 "$(run "$(bash_p "$C" "$WTX")")"
done
# Any command that is no sender has the whole line read as code: a shell's -c
# string, eval, a shell's standard input, a remote command, a variable or
# substitution run as the command, and anything in backticks. An install after
# the message still counts.
for C in "bash -c '$INSTALL lodash'" "sh -c \"cd web && $INSTALL lodash\"" "/bin/zsh -c '$ADD lodash'" "sudo sh -c '$INSTALL lodash'" \
  "\"bash\" -c '$INSTALL lodash'" "eval \"$INSTALL lodash\"" "$(printf 'bash <<EOF\n%s lodash\nEOF' "$INSTALL")" "bash <<< \"$INSTALL lodash\"" \
  "echo \"$INSTALL lodash\" | sh" "echo lodash | xargs -I{} sh -c \"$INSTALL {}\"" "echo \"$INSTALL lodash\" | xargs -I{} {}" \
  "ssh box \"$INSTALL lodash\"" "C=\"$INSTALL lodash\"; \$C" "echo \"\$($INSTALL lodash)\"" "echo \"\`$INSTALL lodash\`\"" \
  "\"npm\" install lodash" "npm 'install' 'lodash'" "$INSTALL \"lodash\"" "pip install \"requests>=2,<3\"" "$INSTALL \"lodash express\"" \
  "gh issue create --body \"about npm ci\" && $INSTALL lodash" "git commit -m 'note' ; $ADD lodash"; do
  check "a real install still blocks: $C" 2 "$(run "$(bash_p "$C")")"
done
ci_blocks "bash -c 'cd web && npm ci'" "sh -c 'npm ci'" "echo 'cd web && npm ci' | bash" "git commit -m 'npm ci note' && npm ci" '"npm" ci'
# A sender piped or chained to anything that is no sender is read whole: the
# text may be fed to it, and nobody has to list how.
for C in "echo '$INSTALL lodash' | bash" "echo '$INSTALL lodash' | sh" "printf '%s\\n' '$INSTALL lodash' | sudo bash" \
  "echo '$INSTALL lodash' ; make" "echo '$INSTALL lodash' && ./run.sh" "$(printf "echo '%s lodash'\nmake" "$INSTALL")" \
  "echo '$INSTALL lodash' > /tmp/x.sh; bash /tmp/x.sh" "echo '$INSTALL lodash' > >(bash)" "A=1 echo '$INSTALL lodash'" \
  "gh issue create --body '$INSTALL lodash' | tee /tmp/out" "git rebase --exec '$INSTALL lodash' main" \
  "/usr/bin/echo '$INSTALL lodash'" "if true; then echo '$INSTALL lodash'; fi"; do
  check "a sender beside a command that is no sender is read whole: $C" 2 "$(run "$(bash_p "$C")")"
done
ci_blocks "echo 'npm ci' | bash" "echo 'npm ci' ; make" "$(printf "echo 'npm ci'\nmake")"
# A word that is only the NAME of a shell or of eval, given as an argument, runs nothing.
for C in "gh issue create --title bash --body '$INSTALL lodash is refused'" "gh issue create --title sh --body 'cd web && npm ci'" \
  "gh issue create --title eval --body '$INSTALL lodash'" "gh issue create --label ssh --body '$ADD lodash'" \
  "git commit -m '$INSTALL lodash' --author zsh" "gh issue create --title 'xargs and source' --body '$INSTALL lodash'" \
  "$(printf "cat > /tmp/note.md <<'EOF'\n\$(%s lodash)\n\$(cd web && npm ci)\nEOF" "$INSTALL")" \
  "$(printf 'cat > /tmp/note.md <<"EOF"\n$(%s lodash)\nEOF' "$INSTALL")" \
  "$(printf "cat >> /tmp/note.md <<'EOF'\nthe guard refused \`%s lodash\` and \`npm ci\`\nEOF" "$INSTALL")" \
  "$(printf "cat <<-'EOF'\n\t\`npm ci\`\n\tEOF\ngit status")"; do
  check "a message that names an install passes: $C" 0 "$(run "$(bash_p "$C" "$WTX")")"
done
# Every way round the first design that review found, and its neighbours: a
# shell reached through another command or given joined flags, and a
# here-document whose end word is not quoted, a word or a number.
for C in "env A=1 sh -c '$INSTALL lodash'" "timeout 5 bash -c '$INSTALL lodash'" "find . -name x -exec sh -c '$INSTALL lodash' \\;" \
  "bash --norc -c '$INSTALL lodash'" "bash -lc '$INSTALL lodash'" "bash -ce '$INSTALL lodash'" "sh -ec '$INSTALL lodash'" "bash -xce '$INSTALL lodash'" \
  "$(printf 'cat <<123\n$(%s lodash)\n123' "$INSTALL")" "$(printf 'cat <<-9\n\t$(%s lodash)\n\t9' "$INSTALL")" "$(printf 'cat <<E-1\n$(%s lodash)\nE-1' "$INSTALL")" \
  "$(printf 'gh issue create --body-file - <<EOF\n$(%s lodash)\nEOF' "$INSTALL")" "command eval \"$INSTALL lodash\"" "true && eval '$INSTALL lodash'" \
  "A=1 eval '$INSTALL lodash'" ". <(echo '$INSTALL lodash')" "echo '$INSTALL lodash' | sudo bash" \
  "$(printf 'cat <<EOF\n$(%s lodash)\nEOF' "$INSTALL")" "$(printf 'cat <<-EOF\n\t$(%s lodash)\n\tEOF' "$INSTALL")" \
  "$(printf 'cat << EOF > /tmp/x\nnote $(%s lodash)\nEOF' "$INSTALL")" "$(printf 'cat <<EOF\n`%s lodash`\nEOF' "$INSTALL")" \
  "$(printf "cat <<'EOF'\nnote\nEOF\necho \`%s lodash\`" "$INSTALL")"; do
  check "a real install still blocks: $C" 2 "$(run "$(bash_p "$C")")"
done
# Text that only looks like a note's start, in a comment or a quoted string, hides no line after it.
for C in "$(printf "# see cat <<'EOF' for the shape\necho \`%s lodash\`" "$INSTALL")" "$(printf "echo \"cat <<'EOF'\"\necho \`%s lodash\`" "$INSTALL")" \
  "$(printf "echo 'cat <<\"EOF\"'\necho \`%s lodash\`" "$INSTALL")" "$(printf "git commit -m \"cat <<'EOF'\"\necho \"\`%s lodash\`\"" "$INSTALL")" \
  "$(printf "echo hi # cat <<'EOF'\necho \`%s lodash\`\nEOF" "$INSTALL")" "$(printf "echo \$((1<<2))\necho \`%s lodash\`\n2" "$INSTALL")" \
  "$(printf "# cat <<'EOF'\ncat <<'EOF'\nnote\nEOF\necho \`%s lodash\`" "$INSTALL")" \
  "$(printf "echo \"\$((1<<2))\"\n%s lodash\n2" "$INSTALL")" "$(printf "X=\"a \$((1<<2)) b\"\n%s lodash" "$INSTALL")"; do
  check "an install after text that looks like a note's start still blocks: $C" 2 "$(run "$(bash_p "$C")")"
done
for C in "$(printf "# cat <<'EOF'\ncat > /tmp/note.md <<'EOF'\nthe guard refused \`%s lodash\`\nEOF" "$INSTALL")" \
  "$(printf "echo \"cat <<'EOF'\"\ngit commit -m '%s lodash is refused'" "$INSTALL")"; do
  check "a message after text that looks like a note's start still passes: $C" 0 "$(run "$(bash_p "$C" "$WTX")")"
done
# A note's end word ends the note: a command on a later line is a command.
for C in "$(printf "cat <<'EOF'\nnote\nEOF\n%s lodash" "$INSTALL")" "$(printf "cat > /tmp/n <<'EOF'\nnote\nEOF\n%s lodash" "$INSTALL")" \
  "$(printf "gh issue create --body-file - <<'EOF'\nnote\nEOF\n%s lodash" "$INSTALL")" "$(printf 'cat <<"EOF"\nnote\nEOF\n%s lodash' "$INSTALL")" \
  "$(printf 'cat <<\\EOF\nnote\nEOF\n%s lodash' "$INSTALL")" "$(printf "cat <<-'EOF'\n\tnote\n\tEOF\n%s lodash" "$INSTALL")" \
  "$(printf "cat <<'EOF'\nnote\nEOF\ncat <<'EOF'\nnote\nEOF\n%s lodash" "$INSTALL")" \
  "$(printf "echo hi; cat <<'EOF'\nnote\nEOF\necho done && %s lodash" "$INSTALL")"; do
  check "an install after a note still blocks: $C" 2 "$(run "$(bash_p "$C")")"
done
# A command with an end word that is not plain is read whole, as code: the
# hook that refuses one outright is strict-tier only. Every form that hid an
# install after the note:
for E in "<<'END NOTE'" "<<E'OF'" "<<'E'OF" '<<"E""OF"' "<<E\\OF" "<<'END'\\ NOTE" '<<"E\"OF"'; do
  check "an install after a note with the end word $E is refused" 2 \
    "$(run "$(bash_p "$(printf 'cat %s\nnote\nEOF\n%s lodash' "$E" "$INSTALL")")")"
done
ci_blocks "$(printf "cat <<'EOF'\nnote\nEOF\ncd web && npm ci")" "$(printf "cat <<'EOF'\nnote\nEOF\nnpm ci")" \
  "$(printf "gh issue create --body-file - <<'EOF'\nnote\nEOF\nnpm ci")"
ci_blocks "$(printf 'cat <<EOF\n$(cd web && npm ci)\nEOF')" "$(printf 'cat <<EOF\n$(npm ci)\nEOF')" "env A=1 sh -c 'npm ci'" \
  "bash -ce 'cd web && npm ci'" "sh -ec 'npm ci'" "$(printf 'cat <<123\n$(cd web && npm ci)\n123')" "$(printf 'cat <<123\n$(npm ci)\n123')"
# A quoted folder with a space, inside a string a shell runs: read whole or refused, never cut at the space.
mkdir -p "$TMP/work tree/web" "$TMP/work"; ln -s "$TMP/shared/web-modules" "$TMP/work tree/web/node_modules"
for C in "bash -c 'npm --prefix \"$TMP/work tree/web\" ci'" "bash -c \"npm --prefix '$TMP/work tree/web' ci\"" \
  "bash -c 'cd \"$TMP/work tree/web\" && npm ci'" "bash -c \"cd \\\"$TMP/work tree/web\\\" && npm ci\"" "sh -c 'npm --prefix=\"$TMP/work tree/web\" ci'" \
  "bash -c 'npm -C \"$TMP/work tree/web\" ci'" "bash -c \"npm -C '$TMP/work tree/web' ci\"" "bash -c 'pushd \"$TMP/work tree/web\" && npm ci'" "bash -ce 'npm -C \"$TMP/work tree/web\" ci'"; do
  check "npm ci in a quoted folder with a space, run by a shell, blocks: $C" 2 "$(run "$(bash_p "$C" "$TMP")")"
done
# Without its quoted-span reader the guard reads every line whole: installs still block, and so does a message that names one.
mkdir -p "$TMP/nolib"; cp "$HOOK" "$TMP/nolib/"
check "with its quoted-span reader missing the guard refuses a plain install" 2 "$(bash "$TMP/nolib/dependency-addition-guard.sh" >/dev/null 2>&1 <<<"$(bash_p "$INSTALL lodash")"; echo $?)"
check "and refuses npm ci at a linked root" 2 "$(bash "$TMP/nolib/dependency-addition-guard.sh" >/dev/null 2>&1 <<<"$(bash_p "npm ci" "$WTX")"; echo $?)"
check "and blocks a message that names an install, never passes one unread" 2 "$(bash "$TMP/nolib/dependency-addition-guard.sh" >/dev/null 2>&1 <<<"$(bash_p "gh issue create --body 'bash -c \"$INSTALL lodash\"'")"; echo $?)"
check "the senders are one named list in the hook" 1 "$(grep -c '^SENDERS=' "$HOOK")"

# A Codex patch says where its hunk lands (`@@ [project]`); codex-dispatch.sh
# passes that on as `anchors`. The same line may also sit in a table that
# declares no dependency, and an edit read as landing there adds nothing.
mkdir -p "$TMP/anch"
printf '[tool.thing]\nextras = [\n    "requests>=2",\n]\n\n[project]\nname = "x"\ndependencies = [\n    "requests>=2",\n]\n' > "$TMP/anch/pyproject.toml"
anch() { edit "$1" "$2" "$3" | jq -c --arg a "$4" '.tool_input.anchors = [$a]'; }
check "a dependency added after the patch's [project] anchor blocks" 2 \
  "$(run "$(anch "$TMP/anch/pyproject.toml" '    "requests>=2",' '    "requests>=2",
    "leftpad",' '[project]')")"
check "the same lines added to the table that declares none pass" 0 \
  "$(run "$(anch "$TMP/anch/pyproject.toml" '    "requests>=2",' '    "requests>=2",
    "leftpad",' '[tool.thing]')")"
check "an anchor the file does not hold blocks: the edit cannot be placed" 2 \
  "$(run "$(anch "$TMP/anch/pyproject.toml" '    "requests>=2",' '    "requests>=2",' '[gone]')")"
printf '{\n  "name": "x",\n  "overrides": {\n    "a": "1"\n  },\n  "dependencies": {\n    "a": "1"\n  }\n}\n' > "$TMP/anch/package.json"
check "a package.json dependency added after the patch's anchor blocks" 2 \
  "$(run "$(anch "$TMP/anch/package.json" '    "a": "1"' '    "a": "1",
    "leftpad": "1"' '"dependencies": {')")"

# An option that takes a value sits anywhere in the command. Its value is not
# a package, and it must not hide the subcommand from the matcher.
for c in 'npm --prefix web i lodash' 'npm -w web i lodash' 'pnpm --filter web add lodash' 'pnpm -C web add lodash' \
         'yarn --cwd web add left-pad' 'npm install --registry https://r.example lodash' 'npm install --prefix=web lodash'; do
  check "$c blocks" 2 "$(run "$(bash_p "$c")")"
done
for c in 'npm install --prefix web' 'npm --prefix web install' 'npm install -w web' 'npm i --loglevel silent' 'pnpm --dir web install'; do
  check "$c passes: it restores what the manifest lists" 0 "$(run "$(bash_p "$c")")"
done
# A hunk that only adds lines has no old text to find: where it lands is the
# anchor. Read as appended to the file, a dependency list written under
# [project] would sit in the last table instead, and declare nothing.
printf '[project]\nname = "x"\n\n[tool.thing]\nk = 1\n' > "$TMP/anch/pyproject.toml"
check "lines only added under the [project] anchor declare a dependency: blocks" 2 \
  "$(run "$(anch "$TMP/anch/pyproject.toml" '' 'dependencies = ["leftpad"]
' '[project]')")"
check "the same lines added under a table that declares none pass" 0 \
  "$(run "$(anch "$TMP/anch/pyproject.toml" '' 'dependencies = ["leftpad"]
' '[tool.thing]')")"
check "a package.json line only added under the dependencies anchor blocks" 2 \
  "$(run "$(anch "$TMP/anch/package.json" '' '    "leftpad": "1",
' '"dependencies": {')")"
# Appended to the file such a line is not JSON, and the line-shape screen that
# then reads it knows only some spec shapes: `catalog:` is not one.
check "and blocks whatever shape its version has" 2 \
  "$(run "$(anch "$TMP/anch/package.json" '' '    "leftpad": "catalog:",
' '"dependencies": {')")"
check "the same line only added under a map that is no dependency map passes" 0 \
  "$(run "$(anch "$TMP/anch/package.json" '' '    "leftpad": "catalog:",
' '"overrides": {')")"
# replace_all renames every occurrence, so the edit is read that way: the
# first "a" sits in a map that declares nothing, the second is a dependency.
printf '{\n  "name": "x",\n  "overrides": {\n    "a": "1"\n  },\n  "dependencies": {\n    "a": "1"\n  }\n}\n' > "$TMP/anch/package.json"
check "a replace_all that renames a dependency key further down blocks" 2 \
  "$(run "$(edit "$TMP/anch/package.json" '"a"' '"leftpad"' | jq -c '.tool_input.replace_all = true')")"
check "without replace_all only the first is renamed, in a map that declares nothing: blocks, as old text that is there twice" 2 \
  "$(run "$(edit "$TMP/anch/package.json" '"a"' '"leftpad"')")"

# A requirement given as a URL or a path has no name before it: read by its
# first word, every https wheel was the package "https" and a second one was not new.
printf 'https://files.example/a-1.0-py3-none-any.whl\n./vendor/local\n' > "$TMP/requirements-url.txt"
RU=$TMP/requirements-url.txt
check "a second wheel URL in requirements blocks" 2 \
  "$(run "$(edit "$RU" './vendor/local' $'./vendor/local\nhttps://files.example/b-2.0-py3-none-any.whl')")"
check "a second local path in requirements blocks" 2 \
  "$(run "$(edit "$RU" './vendor/local' $'./vendor/local\n./vendor/other')")"
check "a comment beside the URLs passes" 0 "$(run "$(edit "$RU" './vendor/local' $'./vendor/local\n# pinned')")"

# A Codex patch that renames a manifest names the file its text comes from
# (codex-dispatch.sh, source_path): the new name is not on disk yet, and read
# as an empty file every rename of a manifest blocked.
printf 'requests==2.0\nflask==3.0\n' > "$TMP/requirements-old.txt"
mv_edit() { edit "$TMP/requirements-new.txt" "$1" "$2" | jq -c --arg s "$TMP/${3:-requirements-old.txt}" '.tool_input.source_path = $s'; }
check "a renamed requirements file with a version bump passes" 0 "$(run "$(mv_edit 'flask==3.0' 'flask==3.1')")"
check "a renamed requirements file with a new package blocks" 2 "$(run "$(mv_edit 'flask==3.0' $'flask==3.0\nleftpad==1.0')")"
printf 'requests==2.0\n' > "$TMP/notes.txt"
check "a file that was no manifest is no baseline: its packages are new" 2 "$(run "$(mv_edit 'requests==2.0' 'requests==2.1' notes.txt)")"
mkdir -p "$TMP/mv/a"; echo '{"dependencies":{"left":"1.0.0"}}' > "$TMP/mv/a/package.json"
pj() { edit "$TMP/mv/b/package.json" "$1" "$2" | jq -c --arg s "$TMP/mv/a/package.json" '.tool_input.source_path = $s'; }
check "a moved package.json that renames a dependency key blocks" 2 "$(run "$(pj '"left"' '"pad"')")"
check "a moved package.json with a version bump passes" 0 "$(run "$(pj '"left":"1.0.0"' '"left":"1.0.1"')")"

# One Codex patch may change a manifest in several hunks, and only all of them
# together leave valid JSON. codex-dispatch.sh passes every hunk of the file on
# as `file_edits`; read one at a time, the file's own "name" looked like a new
# dependency.
mkdir -p "$TMP/hunks"
printf '{\n  "name": "x",\n  "dependencies": {\n    "a": "1"\n  },\n  "scripts": {\n    "t": "x"\n  }\n}\n' > "$TMP/hunks/package.json"
H1O='  "name": "x",
  "dependencies": {
    "a": "1"
  },'
H1N='  "name": "x",
  "dependencies": {
    "a": "1"
  }'
H2O='  "scripts": {
    "t": "x"
  }
}'
hunks() { edit "$TMP/hunks/package.json" "$H1O" "$1" | jq -c --arg o1 "$H1O" --arg n1 "$1" --arg o2 "$H2O" '.tool_input.file_edits = [{old_string: $o1, new_string: $n1}, {old_string: $o2, new_string: "}"}]'; }
check "a patch whose hunks only together leave valid JSON, adding no dependency, passes" 0 "$(run "$(hunks "$H1N")")"
check "the same patch adding a dependency still blocks" 2 "$(run "$(hunks '  "name": "x",
  "dependencies": {
    "a": "1",
    "leftpad": "1"
  }')")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
