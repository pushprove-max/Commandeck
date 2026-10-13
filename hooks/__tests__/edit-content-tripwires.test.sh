#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
# Self-test for edit-content-tripwires.sh. Run directly.
#
# Three claims beyond the rules themselves:
#   - the toll is on what an edit ADDS. The pattern must occur more times in
#     what the edit writes than in what it replaces, so carrying an existing
#     cast along is free and adding a second one beside it is not.
#   - each edit is judged by ITS OWN path, so an exempt path in one hunk of a
#     MultiEdit cannot carry a violation in another hunk.
#   - the rules are scoped by file type, not by one project's directory names.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/edit-content-tripwires.sh"
ROOT=$(git rev-parse --show-toplevel)
PASS=0 FAIL=0

run_hook() { echo "$1" | "$HOOK" >/dev/null 2>&1; echo $?; }
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
json() { jq -cn --arg fp "$1" --arg new "$2" '{tool_input:{file_path:$fp, new_string:$new}}'; }
json_edit() { jq -cn --arg fp "$1" --arg old "$2" --arg new "$3" '{tool_input:{file_path:$fp, old_string:$old, new_string:$new}}'; }
json_multi() { jq -cn --arg fp "$1" --arg old "$2" --arg new "$3" '{tool_input:{file_path:$fp, edits:[{old_string:$old, new_string:$new}]}}'; }

# --- the annotation is the pass, and needs a reason ---------------------------
check "annotated cast passes with a reason" 0 \
  "$(run_hook "$(json "$ROOT/scripts/some-fix.ts" 'const x = y as any; // cast-ok: the fixture is untyped JSON, checked on the next line')")"
check "reasonless annotation still blocks" 2 \
  "$(run_hook "$(json "$ROOT/scripts/some-fix.ts" 'const x = y as any; // cast-ok:')")"
# The refusal names the pass the hook already honours, so a reviewed use clears
# in one retry.
ERR=$(json "$ROOT/scripts/some-fix.ts" 'const x = y as any;' | "$HOOK" 2>&1 >/dev/null)
check "the refusal names the annotation that passes" 1 \
  "$(grep -qF 'If this use is deliberate, annotate it in the same edit: // cast-ok: <reason>' <<<"$ERR" && echo 1 || echo 0)"

# --- cast rule ---------------------------------------------------------------
check "as never in src blocks" 2 \
  "$(run_hook "$(json "$ROOT/src/services/some-service.ts" 'const ring = name as never;')")"
check "as any in scripts blocks" 2 \
  "$(run_hook "$(json "$ROOT/scripts/tool.ts" 'const x = value as any;')")"
# A pure deletion removes the cast; an empty new text must not shift the
# removed text into the written column (hook_edit_triples' empty field).
check "deleting a cast passes" 0 \
  "$(run_hook "$(json_edit "$ROOT/scripts/tool.ts" 'const x = value as any;' '')")"
check "as unknown as blocks" 2 \
  "$(run_hook "$(json "$ROOT/src/routes/r.ts" 'const t = row as unknown as Tuning;')")"
check "annotated cast passes" 0 \
  "$(run_hook "$(json "$ROOT/src/services/some-service.ts" 'const t = row as unknown as Tuning; // cast-ok: repository rows are untyped Records; validated by normalizeDraft on the next line')")"
check "cast in web/src blocks" 2 \
  "$(run_hook "$(json "$ROOT/web/src/pages/x.tsx" 'const x = y as any;')")"
check "cast in shared blocks" 2 \
  "$(run_hook "$(json "$ROOT/shared/taxonomy/t.ts" 'const x = y as unknown as T;')")"
# A cast in a test lets a fake drift from the real symbol, so tests pay the toll too.
check "cast in a .spec.ts blocks" 2 \
  "$(run_hook "$(json "$ROOT/src/routes/r.spec.ts" 'const repo = fake as unknown as Repo;')")"
check "cast in a .test.ts blocks" 2 \
  "$(run_hook "$(json "$ROOT/scripts/__tests__/tool.test.ts" 'const repo = fake as unknown as Repo;')")"
check "cast in a non-test file blocks" 2 \
  "$(run_hook "$(json "$ROOT/src/routes/r.ts" 'const repo = fake as unknown as Repo;')")"
check "cast in any directory blocks: the rule is scoped by file type" 2 \
  "$(run_hook "$(json "$ROOT/tools/x.ts" 'const x = y as any;')")"
check "the same text in a file that is not TypeScript passes" 0 \
  "$(run_hook "$(json "$ROOT/tools/x.py" 'const x = y as any;')")"
check "ordinary as-cast to a type passes" 0 \
  "$(run_hook "$(json "$ROOT/src/services/some-service.ts" 'const r = value as RingAlias;')")"

# --- stringify-equality rule -------------------------------------------------
check "stringify equality in scripts blocks" 2 \
  "$(run_hook "$(json "$ROOT/scripts/tool.ts" 'if (JSON.stringify(a) === JSON.stringify(b)) return;')")"
check "stringify inequality blocks" 2 \
  "$(run_hook "$(json "$ROOT/src/services/config-thing.ts" 'const changed = JSON.stringify(x) !== JSON.stringify(y);')")"
check "annotated stringify equality passes" 0 \
  "$(run_hook "$(json "$ROOT/scripts/tool.ts" 'if (JSON.stringify(a) === JSON.stringify(b)) return; // stringify-compare-ok: both sides serialized by this same function two lines up')")"
check "lone stringify call passes" 0 \
  "$(run_hook "$(json "$ROOT/scripts/tool.ts" 'logger.info(JSON.stringify(payload));')")"
check "stringify equality outside JavaScript and TypeScript passes" 0 \
  "$(run_hook "$(json "$ROOT/tools/handler.py" 'if (JSON.stringify(a) === JSON.stringify(b)) return;')")"

# --- comment/string stripping (Codex r1 P2) ----------------------------------
check "cast in a comment passes" 0 \
  "$(run_hook "$(json "$ROOT/src/services/s.ts" '// the old code did `value as never` and that hid the bug')")"
check "URL string does not swallow a real cast on the same line" 2 \
  "$(run_hook "$(json "$ROOT/src/services/s.ts" 'const u = "http://a.b"; const v = w as any;')")"

# --- retained pre-existing occurrences (Claude r1 P2) ------------------------
check "edit RETAINING an existing cast passes" 0 \
  "$(run_hook "$(json_edit "$ROOT/src/services/s.ts" 'const facts = build(x as never);' 'const gateFacts = build(x as never);')")"
check "edit ADDING a cast to a clean line still blocks" 2 \
  "$(run_hook "$(json_edit "$ROOT/src/services/s.ts" 'const facts = build(x);' 'const facts = build(x as never);')")"
# A deletion has no new text. Read by a whitespace separator, the empty field
# vanished and the removed cast was judged as the text being written.
check "a MultiEdit that deletes a cast beside another edit passes" 0 \
  "$(run_hook "$(jq -cn --arg fp "$ROOT/src/services/s.ts" '{tool_input:{file_path:$fp, edits:[{old_string:"const a = p as any;", new_string:""}, {old_string:"x", new_string:"y"}]}}')")"
# The toll is per cast, not per line that has one.
check "a second cast added on the same line blocks" 2 \
  "$(run_hook "$(json_edit "$ROOT/src/services/s.ts" 'f(a as any);' 'f(a as any, b as any);')")"

# --- MultiEdit edits[] payloads (Codex r4 P2: batch edits bypassed everything)
check "MultiEdit adding a cast blocks" 2 \
  "$(run_hook "$(json_multi "$ROOT/src/services/s.ts" 'const facts = build(x);' 'const facts = build(x as never);')")"
check "MultiEdit retaining a cast passes" 0 \
  "$(run_hook "$(json_multi "$ROOT/src/services/s.ts" 'const a = p as any;' 'const b = p as any;')")"

# --- reviewer names in comments ----------------------------------------------
check "reviewer name + P-level in a comment blocks" 2 \
  "$(run_hook "$(json "$ROOT/src/services/s.ts" '// Codex P1: guard the concurrent operator case')")"
check "jsdoc star line with a name + P0 blocks" 2 \
  "$(run_hook "$(json "$ROOT/src/routes/r.ts" ' * Codex P0 said this needed a fence')")"
check "reviewer name + round number blocks" 2 \
  "$(run_hook "$(json "$ROOT/scripts/tool.ts" '// Claude round 3 asked for this branch')")"
check "literal phrase 'Codex flagged' blocks" 2 \
  "$(run_hook "$(json "$ROOT/shared/x.ts" '// Codex flagged this with two concurrent writers')")"
check "'per review' in a comment blocks" 2 \
  "$(run_hook "$(json "$ROOT/lambdas/api/h.ts" '// widened per review')")"
check "reviewer name in a STRING LITERAL passes" 0 \
  "$(run_hook "$(json "$ROOT/src/services/s.ts" 'const help = "Ask Claude about P1 incidents";')")"
check "plain behavioural comment passes" 0 \
  "$(run_hook "$(json "$ROOT/src/services/s.ts" '// Rejects a token with no bound recipient.')")"
check "a name without a severity or round passes" 0 \
  "$(run_hook "$(json "$ROOT/src/services/s.ts" '// Claude Code hooks run before the write lands.')")"
check "web/src is in scope and blocks" 2 \
  "$(run_hook "$(json "$ROOT/web/src/pages/P.tsx" '// Opus P2: memoise this selector')")"
check "docs/ is out of scope" 0 \
  "$(run_hook "$(json "$ROOT/docs/reference/thing.txt" '// Luna P1 filed this')")"
check "a test file is out of scope" 0 \
  "$(run_hook "$(json "$ROOT/src/services/__tests__/s.test.ts" '// Luna P1 filed this')")"
check "infra outside lib/ is out of scope" 0 \
  "$(run_hook "$(json "$ROOT/infra/bin/app.ts" '// Sol P1 flagged this stack')")"
check "an edit CARRYING an existing reviewer comment passes" 0 \
  "$(run_hook "$(json_edit "$ROOT/src/services/s.ts" '// Luna P1: guard this' '// Luna P1: guard this')")"
check "a .test.ts file is exempt" 0 \
  "$(run_hook "$(json "$ROOT/src/services/s.test.ts" '// Luna P1: pins the case Luna filed')")"
check "a .spec.tsx file is exempt" 0 \
  "$(run_hook "$(json "$ROOT/web/src/pages/P.spec.tsx" '// Sol P0: pins the regression')")"
check "a file under /__tests__/ is exempt" 0 \
  "$(run_hook "$(json "$ROOT/shared/__tests__/x.ts" '// Codex round 2 asked for this case')")"
check "a file under /test/ is exempt" 0 \
  "$(run_hook "$(json "$ROOT/scripts/test/helper.ts" '// Opus P1 flagged this helper')")"
check "a file under /tests/ is exempt" 0 \
  "$(run_hook "$(json "$ROOT/scripts/tests/helper.ts" '// Opus P1 flagged this helper')")"

# --- global exemptions -------------------------------------------------------
check "test file passes every rule but the cast rule" 0 \
  "$(run_hook "$(json "$ROOT/src/services/__tests__/x.test.ts" 'if (JSON.stringify(a) === JSON.stringify(b)) return;')")"
check "a test file's cast still pays the toll" 2 \
  "$(run_hook "$(json "$ROOT/src/services/__tests__/x.test.ts" 'const y = x as any;')")"

# --- the toll is on ADDITIONS -------------------------------------------------
CAST='const t = row as unknown as Tuning;'
check "carrying an existing cast along passes" 0 \
  "$(run_hook "$(json_edit "$ROOT/src/routes/r.ts" "$CAST" "$CAST
const other = 1;")")"
check "carrying one along is SILENT" "" \
  "$(echo "$(json_edit "$ROOT/src/routes/r.ts" "$CAST" "$CAST
const other = 1;")" | "$HOOK" 2>&1)"
check "a SECOND cast beside a retained one blocks" 2 \
  "$(run_hook "$(json_edit "$ROOT/src/routes/r.ts" "$CAST" "$CAST
const u = other as any;")")"
check "removing a cast passes" 0 \
  "$(run_hook "$(json_edit "$ROOT/src/routes/r.ts" "$CAST" 'const t: Tuning = row;')")"
check "a new file (no old side) still pays" 2 \
  "$(run_hook "$(jq -cn --arg fp "$ROOT/src/routes/r.ts" --arg c "$CAST" '{tool_name:"Write", tool_input:{file_path:$fp, content:$c}}')")"

# --- each edit is judged by its own path --------------------------------------
check "an exempt hunk does not carry a violating one" 2 \
  "$(run_hook "$(jq -cn --arg fp "$ROOT/src/routes/r.ts" '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[
    {file_path:"'"$ROOT"'/src/routes/__tests__/r.test.ts", old_string:"a", new_string:"const f = x as any;"},
    {file_path:"'"$ROOT"'/src/routes/r.ts", old_string:"b", new_string:"const g = y as any;"}]}}')")"
# Every check that reads the payload's one path reads the FIRST edit's: a
# batch over several files is screened file by file.
check "an exempt first file does not carry a second file's cast" 2 \
  "$(run_hook "$(jq -cn --arg r "$ROOT" '{tool_name:"MultiEdit", tool_input:{file_path:($r + "/docs/notes.md"), edits:[
    {file_path:($r + "/docs/notes.md"), old_string:"a", new_string:"a note"},
    {file_path:($r + "/src/routes/r.ts"), old_string:"b", new_string:"const g = y as any;"}]}}')")"
check "nor a second file's type suppression" 2 \
  "$(run_hook "$(jq -cn --arg r "$ROOT" '{tool_name:"MultiEdit", tool_input:{file_path:($r + "/src/routes/r.test.ts"), edits:[
    {file_path:($r + "/src/routes/r.test.ts"), old_string:"a", new_string:"const ok = 1;"},
    {file_path:($r + "/src/routes/r.ts"), old_string:"b", new_string:"// @ts-ignore\nrun();"}]}}')")"
check "a clean batch over two files passes" 0 \
  "$(run_hook "$(jq -cn --arg r "$ROOT" '{tool_name:"MultiEdit", tool_input:{file_path:($r + "/docs/notes.md"), edits:[
    {file_path:($r + "/docs/notes.md"), old_string:"a", new_string:"a note"},
    {file_path:($r + "/src/routes/r.ts"), old_string:"b", new_string:"const g = 1;"}]}}')")"
check "a retained cast in one hunk does not excuse another" 2 \
  "$(run_hook "$(jq -cn --arg fp "$ROOT/src/routes/r.ts" --arg cast "$CAST" '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[
    {old_string:$cast, new_string:$cast},
    {old_string:"b", new_string:"const g = y as any;"}]}}')")"
check "unrelated edit passes" 0 \
  "$(run_hook "$(json "$ROOT/scripts/some-fix.ts" 'const x = 1;')")"

# =============================================================================
# The four checks merged in from their own hooks. Each section is the retired
# hook's own self-test, repointed at this file -- the rule did not change, only
# which process runs it.
# =============================================================================

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
SETTINGS="$(cd "$(dirname "$0")/.." && pwd)/hooks.json"

t_edit()  { jq -cn --arg fp "$1" --arg s "$2" '{tool_name:"Edit",  tool_input:{file_path:$fp, old_string:"", new_string:$s}}'; }
t_write() { jq -cn --arg fp "$1" --arg s "$2" '{tool_name:"Write", tool_input:{file_path:$fp, content:$s}}'; }
t_multi() { jq -cn --arg fp "$1" --arg s "$2" '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[
  {old_string:"a", new_string:"const ok = 1;"},{old_string:"b", new_string:$s}]}}'; }
t_multi_peredit() { jq -cn --arg fp "$1" --arg s "$2" '{tool_name:"MultiEdit", tool_input:{edits:[{file_path:$fp, old_string:"y", new_string:$s}]}}'; }
t_multi_mixed() { jq -cn --arg fp1 "$1" --arg s1 "$2" --arg fp2 "$3" --arg s2 "$4" \
  '{tool_name:"MultiEdit", tool_input:{edits:[{file_path:$fp1, old_string:"x", new_string:$s1},
                                              {file_path:$fp2, old_string:"y", new_string:$s2}]}}'; }
t_bash()  { jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }
t_err()   { bash "$HOOK" 2>&1 >/dev/null <<<"$1"; }
t_all()   { bash "$HOOK" 2>&1 <<<"$1"; }

# --- CRLF ---------------------------------------------------------------------
# The check that could not fire: `grep -qP '\r\n'` can never match, because grep
# works one line at a time with the terminating \n stripped. It matches a bare
# carriage return now, which is what the message always said it banned. A file
# that ALREADY carries CR is exempt -- five tracked files do, and matching a bare
# \r without the exemption would block the edit that cleans them up.
CR=$'\r'
CRLF="const a = 1;${CR}
const b = 2;"
LONE_CR="const a = 1;${CR}const b = 2;"
CLEAN_TXT="const a = 1;
const b = 2;"
CLEAN_FILE="$TMP/clean.ts"; printf 'const x = 1;\n' > "$CLEAN_FILE"
CR_FILE="$TMP/legacy.md";   printf 'old text\r\nsecond line\r\n' > "$CR_FILE"

check "a Write carrying CRLF blocks"              2 "$(run_hook "$(t_write "$TMP/new.ts" "$CRLF")")"
check "an Edit carrying CRLF blocks"              2 "$(run_hook "$(t_edit  "$CLEAN_FILE" "$CRLF")")"
check "a MultiEdit carrying CRLF blocks"          2 "$(run_hook "$(t_multi "$CLEAN_FILE" "$CRLF")")"
check "a lone CR blocks too"                      2 "$(run_hook "$(t_edit  "$CLEAN_FILE" "$LONE_CR")")"
check "the CR block says to remove it"            0 \
  "$(t_err "$(t_write "$TMP/new.ts" "$CRLF")" | grep -q 'LF only' && echo 0 || echo 1)"
check "clean LF content passes"                   0 "$(run_hook "$(t_write "$TMP/new.ts" "$CLEAN_TXT")")"
check "clean content is SILENT"                   "" "$(t_all "$(t_write "$TMP/new.ts" "$CLEAN_TXT")")"
check "a Bash payload carrying \r passes"         0 "$(run_hook "$(t_bash 'printf a\r\n')")"
check "editing a file that already has CR passes" 0 "$(run_hook "$(t_edit  "$CR_FILE" "$CRLF")")"
check "cleaning that file up is not blocked"      0 "$(run_hook "$(t_write "$CR_FILE" "$CLEAN_TXT")")"
check "a CLEAN file gets no CR exemption"         2 "$(run_hook "$(t_edit  "$CLEAN_FILE" "$CRLF")")"
check "a file not yet on disk gets no exemption"  2 "$(run_hook "$(t_write "$TMP/absent.ts" "$CRLF")")"

# --- localhost ----------------------------------------------------------------
APP="src/services/api-client.ts"
BAD_FETCH="const r = await fetch('http://localhost:3000/health');"
BAD_LOOPBACK="const base = 'http://127.0.0.1:4000';"
BAD_AXIOS="const r = await axios.get('http://localhost:8080/v1/rooms');"
GOOD_URL="const r = await fetch(\`\${process.env.API_BASE_URL}/health\`);"

check "Edit content with a localhost fetch blocks"  2 "$(run_hook "$(t_edit  "$APP" "$BAD_FETCH")")"
check "Write content with a localhost fetch blocks" 2 "$(run_hook "$(t_write "$APP" "$BAD_FETCH")")"
check "MultiEdit blocks on a NON-first edit"        2 "$(run_hook "$(t_multi "$APP" "$BAD_FETCH")")"
check "MultiEdit with a per-edit file_path blocks"  2 "$(run_hook "$(t_multi_peredit "$APP" "$BAD_FETCH")")"
check "a hardcoded 127.0.0.1 blocks"                2 "$(run_hook "$(t_edit  "$APP" "$BAD_LOOPBACK")")"
check "an axios call to localhost blocks"           2 "$(run_hook "$(t_edit  "$APP" "$BAD_AXIOS")")"
# The exemption is for the hook scripts that quote the form, not a project's own src/hooks.
check "application code in a folder named hooks blocks" 2 "$(run_hook "$(t_edit "$ROOT/src/hooks/useApi.ts" "$BAD_FETCH")")"
# Quoted in a comment: a hook must still parse as shell after the edit.
check "a hook script quoting the form passes"       0 "$(run_hook "$(t_edit "$ROOT/hooks/x-guard.sh" "# $BAD_FETCH")")"
# The exemption belongs to the EDIT, not the payload: pooling every edit's text
# and testing one path let an exempt first path carry a violation in a second.
check "an exempt edit does not cover a violation in a later edit" 2 \
  "$(run_hook "$(t_multi_mixed "src/a.test.ts" "const ok = 1;" "$APP" "$BAD_FETCH")")"
check "the block names the OFFENDING file, not the exempt one"    0 \
  "$(t_err "$(t_multi_mixed "src/a.test.ts" "const ok = 1;" "$APP" "$BAD_FETCH")" |
     grep -qF "local address in $APP" && echo 0 || echo 1)"
check "a violation in the exempt file alone still passes"         0 \
  "$(run_hook "$(t_multi_mixed "src/a.test.ts" "$BAD_FETCH" "$APP" "const ok = 1;")")"
check "the localhost block names the fix"           0 \
  "$(t_err "$(t_edit "$APP" "$BAD_FETCH")" | grep -qF "environment variable" && echo 0 || echo 1)"
check "an env-var base URL passes"                  0 "$(run_hook "$(t_edit  "$APP" "$GOOD_URL")")"
check "a .test. file may use localhost"             0 "$(run_hook "$(t_edit "src/services/api-client.test.ts" "$BAD_FETCH")")"
check "a __tests__ file may use localhost"          0 "$(run_hook "$(t_edit "src/services/__tests__/api.ts" "$BAD_FETCH")")"
check "vite.config may use localhost"               0 "$(run_hook "$(t_edit "web/vite.config.ts" "$BAD_FETCH")")"
check "an e2e/ file may use localhost"              0 "$(run_hook "$(t_edit "web/e2e/room.spec.ts" "$BAD_FETCH")")"
check "a .env file may use localhost"               0 "$(run_hook "$(t_edit "web/.env.local" "$BAD_LOOPBACK")")"
# The guards QUOTE the pattern in order to ban it; without this carve-out the
# rule blocks every edit to the file that implements it.
check "a hook file may quote the pattern"           0 "$(run_hook "$(t_edit "hooks/x.sh" "# $BAD_FETCH")")"
check "a hook named by a relative path is still a hook: one that would not parse blocks" 2 "$(run_hook "$(t_edit "hooks/x.sh" "$BAD_FETCH")")"
# A `curl http://localhost:3000` is ordinary local development: this judges
# about-to-be-written file content, and a Bash payload carries none.
# The rules are about THIS tree: a memory note under ~/.claude or a file in an
# unrelated repo is not screened, and a new file in a new directory inside the
# checkout still is (the scope walks up to the nearest existing parent).
OUTSIDE=$(mktemp -d); git -C "$OUTSIDE" init -q
check "a file outside any project checkout passes"  0 "$(run_hook "$(t_edit "$OUTSIDE/notes/memory.md" "$BAD_LOOPBACK")")"
check "a file in an unrelated repo passes"            0 "$(run_hook "$(t_edit "$OUTSIDE/app.ts" "$BAD_FETCH")")"
check "a new file in a new directory in the tree blocks" 2 "$(run_hook "$(t_edit "$ROOT/src/services/brand-new-dir/client.ts" "$BAD_FETCH")")"
ln -s "$ROOT/scripts/board.sh" "$OUTSIDE/link.ts"
check "a symlink outside the tree that points into it blocks" 2 "$(run_hook "$(t_edit "$OUTSIDE/link.ts" "$BAD_FETCH")")"
# An installed plugin's hooks live in the plugin folder, never in the project:
# "this tree" is the project the session runs in, whatever files it carries.
check "a session in a project without the plugin's files is screened" 2 "$(cd "$OUTSIDE" && run_hook "$(t_edit "$OUTSIDE/app.ts" "$BAD_FETCH")")"
check "and from that session this repo is the unrelated one"          0 "$(cd "$OUTSIDE" && run_hook "$(t_edit "$ROOT/src/app.ts" "$BAD_FETCH")")"
git -C "$OUTSIDE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init && git -C "$OUTSIDE" worktree add -q "$OUTSIDE.wt" 2>/dev/null
check "a worktree of the session's project is the same project"      2 "$(cd "$OUTSIDE" && run_hook "$(t_edit "$OUTSIDE.wt/app.ts" "$BAD_FETCH")")"
rm -rf "$OUTSIDE.wt"
rm -rf "$OUTSIDE"
check "a Bash curl to localhost passes"             0 "$(run_hook "$(t_bash 'curl -s http://localhost:3000/health')")"
check "a Bash payload is SILENT"                    "" "$(t_all "$(t_bash 'curl -s http://localhost:3000/health')")"

# --- ownerless deferred-work markers ------------------------------------------
# The rule ALLOWS a TODO carrying an issue number and bans only
# the ownerless kind; the old hook rejected both, so the rule's own sanctioned
# form was unwritable.
SRC="$ROOT/src/services/a.ts"
check "TODO with an issue ref passes"            0 "$(run_hook "$(t_edit "$SRC" '// TODO(#12): drop the shim once #99 lands')")"
check "TODO with a long issue number passes"     0 "$(run_hook "$(t_edit "$SRC" '// TODO(#100234): revisit')")"
check "TODO with an issue ref passes in a batch" 0 "$(run_hook "$(t_multi "$SRC" '// TODO(#26): tighten the cap')")"
check "an allowed TODO is SILENT"                "" "$(t_all "$(t_edit "$SRC" '// TODO(#12): drop the shim')")"
check "a bare TODO blocks"                       2 "$(run_hook "$(t_edit "$SRC" '// TODO: fix this later')")"
check "TODO with no colon blocks"                2 "$(run_hook "$(t_edit "$SRC" '// TODO come back here')")"
check "TODO(#12) with NO colon blocks"           2 "$(run_hook "$(t_edit "$SRC" '// TODO(#12) no colon, not the sanctioned form')")"
check "TODO(no number) blocks"                   2 "$(run_hook "$(t_edit "$SRC" '// TODO(later): fix this')")"
check "FIXME blocks"                             2 "$(run_hook "$(t_edit "$SRC" '// FIXME: broken')")"
check "HACK blocks"                              2 "$(run_hook "$(t_edit "$SRC" '// HACK: works by luck')")"
check "XXX blocks"                               2 "$(run_hook "$(t_edit "$SRC" '// XXX revisit')")"
check "a block-comment TODO blocks"              2 "$(run_hook "$(t_edit "$SRC" '/* TODO: unfinished */')")"
check "a vague placeholder blocks"               2 "$(run_hook "$(t_edit "$SRC" '// placeholder for now')")"
check "an ownerless TODO in a batch blocks"      2 "$(run_hook "$(t_multi "$SRC" '// TODO: fix later')")"
# A patch carries the unchanged lines around its change in new_string: a marker
# already in the file is not this edit's, and must not block the edit beside it.
check "a TODO the edit only carries along passes" 0 \
  "$(run_hook "$(json_edit "$SRC" $'// TODO: fix later\nconst a = 1;' $'// TODO: fix later\nconst a = 2;')")"
check "a TODO added beside a carried one blocks"  2 \
  "$(run_hook "$(json_edit "$SRC" $'// TODO: fix later\nconst a = 1;' $'// TODO: fix later\n// TODO: and this\nconst a = 1;')")"
check "a carried @ts-ignore passes"               0 \
  "$(run_hook "$(json_edit "$SRC" $'// @ts-ignore\nrun(1);' $'// @ts-ignore\nrun(2);')")"
check "the block explains the allowed form"      0 \
  "$(t_err "$(t_edit "$SRC" '// TODO: fix')" | grep -qF 'TODO' && echo 0 || echo 1)"
check "an allowed TODO does not cover a bare one" 2 \
  "$(run_hook "$(t_edit "$SRC" '// TODO(#1): fine
// TODO: not fine')")"
check "an ordinary comment passes"               0 "$(run_hook "$(t_edit "$SRC" '// the pointer moves before the pin')")"
check "markdown is exempt from the marker rule"  0 "$(run_hook "$(t_edit "$ROOT/docs/x.md" '// TODO: fix')")"

# --- type/lint suppression ----------------------------------------------------
check "@ts-ignore in src blocks"                 2 "$(run_hook "$(t_edit "$ROOT/src/services/s.ts" '// @ts-ignore
const x = y.z;')")"
check "@ts-expect-error in src blocks"           2 "$(run_hook "$(t_edit "$ROOT/src/routes/r.ts" '// @ts-expect-error
foo();')")"
check "@ts-nocheck in src blocks"                2 "$(run_hook "$(t_edit "$ROOT/src/services/s.ts" '// @ts-nocheck')")"
check "eslint-disable in src blocks"             2 "$(run_hook "$(t_edit "$ROOT/src/services/s.ts" '/* eslint-disable no-console */')")"
check "the suppression block names the directive" 0 \
  "$(t_err "$(t_edit "$ROOT/src/services/s.ts" '// @ts-ignore')" | grep -qF '@ts-ignore' && echo 0 || echo 1)"
check "a src test file may use @ts-expect-error" 0 "$(run_hook "$(t_edit "$ROOT/src/services/__tests__/s.test.ts" '// @ts-expect-error')")"
check "a .d.ts may carry @ts-nocheck"            0 "$(run_hook "$(t_edit "$ROOT/src/types/x.d.ts" '// @ts-nocheck')")"
check "outside src/ a suppression passes"        0 "$(run_hook "$(t_edit "$ROOT/scripts/tool.ts" '// @ts-ignore')")"
check "the word in prose does not block"         0 "$(run_hook "$(t_edit "$ROOT/src/services/s.ts" '// never reach for ts ignore here')")"

# --- producer/consumer: registered where its fields exist ----------------------
# The localhost rule once read content/new_string while registered only under
# `Bash`, which never sends either, so it never fired. Assert the wiring.
check "registered under the Edit|Write|MultiEdit matcher" 0 \
  "$(jq -e '.hooks.PreToolUse[] | select(.matcher == "Edit|Write|MultiEdit") | .hooks[] | select(.command | endswith("edit-content-tripwires.sh\""))' "$SETTINGS" >/dev/null && echo 0 || echo 1)"
check "NOT registered under the Bash matcher"             0 \
  "$(jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | endswith("edit-content-tripwires.sh\""))' "$SETTINGS" >/dev/null && echo 1 || echo 0)"

# --- memory index cap ----------------------------------------------------------
# MEMORY.md loads into every session and is re-sent on every call, so a write
# that leaves it over 18,000 bytes is refused. Shrinking an over-cap index must
# still pass, or the cleanup edit itself is blocked.
MEMROOT=$(mktemp -d); mkdir -p "$MEMROOT/memory" "$MEMROOT/notes"
MEMF="$MEMROOT/memory/MEMORY.md"
bytes() { head -c "$1" /dev/zero | tr '\0' a; }
m_edit() { jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" --argjson ra "${4:-false}" \
  '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$o, new_string:$n, replace_all:$ra}}'; }
check "a Write of 18,001 bytes to memory/MEMORY.md blocks" 2 "$(run_hook "$(t_write "$MEMF" "$(bytes 18001)")")"
check "a Write of 18,000 bytes to memory/MEMORY.md passes" 0 "$(run_hook "$(t_write "$MEMF" "$(bytes 18000)")")"
check "the refusal names the size and ARCHIVE.md"          0 \
  "$(t_err "$(t_write "$MEMF" "$(bytes 18001)")" | grep -q '18001.*ARCHIVE.md\|ARCHIVE.md.*18001' && echo 0 || echo 1)"
{ bytes 17990; printf '\nTAIL\n'; } > "$MEMF"
check "an Edit that crosses the cap blocks"                2 "$(run_hook "$(m_edit "$MEMF" TAIL "TAIL $(bytes 20)")")"
check "an Edit that stays under the cap passes"            0 "$(run_hook "$(m_edit "$MEMF" TAIL "TAIL x")")"
{ printf 'x\n'; bytes 17990; printf '\nx\n'; } > "$MEMF"
check "a replace_all Edit is counted per occurrence"       2 "$(run_hook "$(m_edit "$MEMF" x "$(bytes 6)" true)")"
{ bytes 18400; printf '\nOLD LINE %s\n' "$(bytes 200)"; } > "$MEMF"
check "an Edit that shrinks an over-cap index passes"      0 "$(run_hook "$(m_edit "$MEMF" "OLD LINE $(bytes 200)" "OLD")")"
check "an Edit that grows an over-cap index blocks"        2 "$(run_hook "$(m_edit "$MEMF" "OLD LINE" "OLD LINE longer")")"
{ bytes 17990; printf 'X'; } > "$MEMF"
check "MultiEdit edits apply in order, not each to the original" 2 "$(run_hook "$(jq -cn --arg fp "$MEMF" \
  '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[{old_string:"X", new_string:"YYYYYYYYYY"},{old_string:"Y", new_string:"ZZ", replace_all:true}]}}')")"
check "a MEMORY.md outside a memory/ directory passes"     0 "$(run_hook "$(t_write "$MEMROOT/notes/MEMORY.md" "$(bytes 18001)")")"
rm -rf "$MEMROOT"

# An edit that DELETES text has an empty new-text column, and a tab-split
# `read` closed the gap, so the text it removed was judged as the text it wrote.
two_edits() { jq -cn --arg fp "$1" --arg o1 "$2" --arg n1 "$3" --arg o2 "$4" --arg n2 "$5" \
  '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[{old_string:$o1, new_string:$n1}, {old_string:$o2, new_string:$n2}]}}'; }
check "a MultiEdit that deletes a cast beside another edit passes" 0 \
  "$(run_hook "$(two_edits "$ROOT/src/services/s.ts" 'const a = x as any;' '' 'const b = 1;' 'const b = 2;')")"
check "a single edit that deletes a cast passes" 0 \
  "$(run_hook "$(json_edit "$ROOT/src/services/s.ts" 'const a = x as any;' '')")"
check "a MultiEdit that deletes a localhost fetch beside another edit passes" 0 \
  "$(run_hook "$(two_edits "$ROOT/src/services/s.ts" 'await fetch("http://localhost:3000/x");' '' 'const b = 1;' 'const b = 2;')")"
check "a MultiEdit that deletes one cast and adds another still blocks" 2 \
  "$(run_hook "$(two_edits "$ROOT/src/services/s.ts" 'const a = x as any;' '' 'const b = y;' 'const b = y as never;')")"

# A marker the edit only CARRIES is not one it writes. A Codex patch
# sends its context lines as old and new text alike, so a patch beside an old
# TODO line was refused for a marker it never touched.
KEPT=$'  // TODO tidy this up\n  const a = 1;'
check "an edit that keeps an existing TODO line passes" 0 \
  "$(run_hook "$(json_edit "$ROOT/src/services/s.ts" "$KEPT" $'  // TODO tidy this up\n  const a = 2;')")"
check "a MultiEdit that keeps one passes" 0 \
  "$(run_hook "$(json_multi "$ROOT/src/services/s.ts" "$KEPT" $'  // TODO tidy this up\n  const a = 2;')")"
check "an edit that keeps one and adds another still blocks" 2 \
  "$(run_hook "$(json_edit "$ROOT/src/services/s.ts" "$KEPT" $'  // TODO tidy this up\n  const a = 2; // FIXME later')")"
check "an edit that rewrites the marker's own line still blocks" 2 \
  "$(run_hook "$(json_edit "$ROOT/src/services/s.ts" "$KEPT" $'  // TODO tidy this up, and that\n  const a = 1;')")"
check "a kept vague placeholder passes" 0 \
  "$(run_hook "$(json_edit "$ROOT/src/services/s.ts" $'  // placeholder\n  const a = 1;' $'  // placeholder\n  const a = 2;')")"
check "a new file with a TODO still blocks" 2 "$(run_hook "$(json "$ROOT/src/services/s.ts" '// TODO write this')")"

# The toll is on casts added, and two on one line are two.
check "a second cast added on the line of a retained one blocks" 2 \
  "$(run_hook "$(json_edit "$ROOT/src/services/s.ts" 'const a = x as any;' 'const a = (x as any) + (y as any);')")"
check "two casts moved onto one line, none added, passes" 0 \
  "$(run_hook "$(json_edit "$ROOT/src/services/s.ts" $'const a = x as any;\nconst b = y as any;' 'const a = [x as any, y as any];')")"

# --- a hook must still parse after the edit ------------------------------------
# A hook that does not parse exits 2 on every call, and the harness reads 2 as
# a refusal: on 2026-10-13 an apostrophe in a single-quoted jq block locked a
# pane out of every Edit and Bash call, the repair included.
HK=$(mktemp -d); trap 'rm -rf "$HK"' EXIT
mkdir -p "$HK/.claude/hooks/lib" "$HK/.claude/scripts"
GOOD=$'#!/usr/bin/env bash\nLINE=$(jq -c \'{a: 1,\n  # a repeated call is visible\n  b: 2}\' <<<"$INPUT")\nexit 0\n'
printf '%s' "$GOOD" > "$HK/.claude/hooks/log.sh"
printf '%s' "$GOOD" > "$HK/.claude/hooks/lib/part.sh"
printf '%s' "$GOOD" > "$HK/.claude/scripts/tool.sh"
printf '%s' "${GOOD/a repeated call is/a repeated call\'s}" > "$HK/.claude/hooks/broken.sh"
json_write() { jq -cn --arg fp "$1" --arg c "$2" '{tool_input:{file_path:$fp, content:$c}}'; }
check "an edit that leaves a hook unparseable blocks" 2 \
  "$(run_hook "$(json_edit "$HK/.claude/hooks/log.sh" 'a repeated call is visible' "a repeated call's visible")")"
check "the same break as a MultiEdit blocks" 2 \
  "$(run_hook "$(json_multi "$HK/.claude/hooks/log.sh" 'a repeated call is visible' "a repeated call's visible")")"
check "the same break with replace_all blocks" 2 \
  "$(run_hook "$(json_edit "$HK/.claude/hooks/log.sh" ' is visible' "'s visible" | jq -c '.tool_input.replace_all = true')")"
# Each edit is judged by its own path: a MultiEdit may carry file_path on each
# edit, a document first and the hook second, or no top-level path at all.
per_edit() { jq -cn --arg a "$1" --arg b "$2" --arg top "${3:-}" --arg new "a repeated call's visible" '{tool_input: ({edits: [{file_path: $a, old_string: "x", new_string: "y"},
  {file_path: $b, old_string: "a repeated call is visible", new_string: $new}]} + (if $top == "" then {} else {file_path: $top} end))}'; }
check "a batch that edits a document first and breaks a hook second blocks" 2 \
  "$(run_hook "$(per_edit "$HK/notes.md" "$HK/.claude/hooks/log.sh" "$HK/notes.md")")"
check "a batch with a path on each edit and none at the top blocks" 2 \
  "$(run_hook "$(per_edit "$HK/notes.md" "$HK/.claude/hooks/log.sh")")"
check "a batch that breaks no hook passes" 0 \
  "$(run_hook "$(per_edit "$HK/notes.md" "$HK/.claude/scripts/tool.sh")")"
check "a new hook written unparseable blocks" 2 \
  "$(run_hook "$(json_write "$HK/.claude/hooks/new.sh" $'#!/usr/bin/env bash\nif true; then\n')")"
check "a file the hooks source is held to the same rule" 2 \
  "$(run_hook "$(json_edit "$HK/.claude/hooks/lib/part.sh" 'a repeated call is visible' "a repeated call's visible")")"
# A hook is known by where the file is, not by how the path is spelled: the
# Mac's disk opens HOOKS/log.sh as hooks/log.sh, and a link can name it anything.
[ ! -e "$HK/.claude/HOOKS/log.sh" ] || check "a hook reached by a path in another letter case blocks too" 2 \
  "$(run_hook "$(json_edit "$HK/.claude/HOOKS/log.sh" 'a repeated call is visible' "a repeated call's visible")")"
ln -s "$HK/.claude/hooks" "$HK/alias"
check "and a hook reached through a linked folder of another name" 2 \
  "$(run_hook "$(json_edit "$HK/alias/log.sh" 'a repeated call is visible' "a repeated call's visible")")"
mkdir -p "$HK/plugin/hooks"; printf '%s' "$GOOD" > "$HK/plugin/hooks/log.sh"
check "a plugin's own hooks folder is held to the same rule" 2 \
  "$(run_hook "$(json_edit "$HK/plugin/hooks/log.sh" 'a repeated call is visible' "a repeated call's visible")")"
check "the refusal names the hook and the parse error" 1 \
  "$(echo "$(json_edit "$HK/.claude/hooks/log.sh" 'a repeated call is visible' "a repeated call's visible")" | "$HOOK" 2>&1 >/dev/null | grep -c 'log.sh would no longer parse.*line')"
check "an edit that keeps a hook parseable passes" 0 \
  "$(run_hook "$(json_edit "$HK/.claude/hooks/log.sh" 'a repeated call is visible' 'a repeated call shows')")"
check "a new hook that parses passes" 0 \
  "$(run_hook "$(json_write "$HK/.claude/hooks/new.sh" $'#!/usr/bin/env bash\nexit 0\n')")"
# The repair is never the edit refused: a hook already broken on disk takes any edit.
check "the edit that repairs a broken hook passes" 0 \
  "$(run_hook "$(json_edit "$HK/.claude/hooks/broken.sh" "a repeated call's" 'a repeated call is')")"
check "a partial repair of a broken hook passes" 0 \
  "$(run_hook "$(json_edit "$HK/.claude/hooks/broken.sh" 'exit 0' 'exit 1')")"
check "a script that is not a hook is not held to it" 0 \
  "$(run_hook "$(json_edit "$HK/.claude/scripts/tool.sh" 'a repeated call is visible' "a repeated call's visible")")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
