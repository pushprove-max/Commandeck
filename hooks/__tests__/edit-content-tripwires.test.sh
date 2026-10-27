#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
# Self-test for edit-content-tripwires.sh. Run directly.
#
# Each rule: a case it must block and one it must let through. The toll is on
# what an edit ADDS, so carrying an existing cast along is free.
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

# --- cast rule ---------------------------------------------------------------
check "as never in src blocks" 2 \
  "$(run_hook "$(json "$ROOT/src/services/some-service.ts" 'const ring = name as never;')")"

# --- retained pre-existing occurrences (Claude r1 P2) ------------------------
check "edit RETAINING an existing cast passes" 0 \
  "$(run_hook "$(json_edit "$ROOT/src/services/s.ts" 'const facts = build(x as never);' 'const gateFacts = build(x as never);')")"
check "edit ADDING a cast to a clean line still blocks" 2 \
  "$(run_hook "$(json_edit "$ROOT/src/services/s.ts" 'const facts = build(x);' 'const facts = build(x as never);')")"

# --- reviewer names in comments ----------------------------------------------
check "reviewer name + P-level in a comment blocks" 2 \
  "$(run_hook "$(json "$ROOT/src/services/s.ts" '// Codex P1: guard the concurrent operator case')")"
check "plain behavioural comment passes" 0 \
  "$(run_hook "$(json "$ROOT/src/services/s.ts" '// Rejects a token with no bound recipient.')")"

TMP=$(mktemp -d); HK=$(mktemp -d); trap 'rm -rf "$TMP" "$HK"' EXIT
t_edit()  { jq -cn --arg fp "$1" --arg s "$2" '{tool_name:"Edit",  tool_input:{file_path:$fp, old_string:"", new_string:$s}}'; }
t_write() { jq -cn --arg fp "$1" --arg s "$2" '{tool_name:"Write", tool_input:{file_path:$fp, content:$s}}'; }

# --- CRLF ---------------------------------------------------------------------
CR=$'\r'
CRLF="const a = 1;${CR}
const b = 2;"
LONE_CR="const a = 1;${CR}const b = 2;"
CLEAN_TXT="const a = 1;
const b = 2;"
CLEAN_FILE="$TMP/clean.ts"; printf 'const x = 1;\n' > "$CLEAN_FILE"
CR_FILE="$TMP/legacy.md";   printf 'old text\r\nsecond line\r\n' > "$CR_FILE"
check "a Write carrying CRLF blocks"              2 "$(run_hook "$(t_write "$TMP/new.ts" "$CRLF")")"
check "clean LF content passes"                   0 "$(run_hook "$(t_write "$TMP/new.ts" "$CLEAN_TXT")")"
check "editing a file that already has CR passes" 0 "$(run_hook "$(t_edit  "$CR_FILE" "$CRLF")")"

# --- localhost ----------------------------------------------------------------
APP="src/services/api-client.ts"
BAD_FETCH="const r = await fetch('http://localhost:3000/health');"
BAD_LOOPBACK="const base = 'http://127.0.0.1:4000';"
BAD_AXIOS="const r = await axios.get('http://localhost:8080/v1/rooms');"
GOOD_URL="const r = await fetch(\`\${process.env.API_BASE_URL}/health\`);"
check "Edit content with a localhost fetch blocks"  2 "$(run_hook "$(t_edit  "$APP" "$BAD_FETCH")")"
check "an env-var base URL passes"                  0 "$(run_hook "$(t_edit  "$APP" "$GOOD_URL")")"

# --- ownerless deferred-work markers ------------------------------------------
SRC="$ROOT/src/services/a.ts"
check "TODO with an issue ref passes"            0 "$(run_hook "$(t_edit "$SRC" '// TODO(#12): drop the shim once #99 lands')")"
check "a bare TODO blocks"                       2 "$(run_hook "$(t_edit "$SRC" '// TODO: fix this later')")"

# --- type/lint suppression ----------------------------------------------------
check "@ts-nocheck in src blocks"                2 "$(run_hook "$(t_edit "$ROOT/src/services/s.ts" '// @ts-nocheck')")"
check "outside src/ a suppression passes"        0 "$(run_hook "$(t_edit "$ROOT/scripts/tool.ts" '// @ts-ignore')")"

# --- issue 282: each exempt path passes, and the same text one path over still blocks ---
check "a suppression in a test file under src/ passes (a type test uses @ts-expect-error)" 0 \
  "$(run_hook "$(t_edit "$ROOT/src/services/s.test.ts" '// @ts-expect-error')")"
SH_FETCH="RE=\"fetch('http://localhost:3000/health')\""
check "a localhost fetch in the plugin's own hooks/*.sh passes (the hook quotes the form)" 0 \
  "$(run_hook "$(t_edit "$ROOT/hooks/probe.sh" "$SH_FETCH")")"
check "a localhost fetch in a project's src/hooks/*.ts still blocks" 2 \
  "$(run_hook "$(t_edit "$ROOT/src/hooks/useHealth.ts" "$BAD_FETCH")")"
CREDIT='Co-Authored''-By: Claude <noreply''@anthropic.com>'
check "a contributor credit in .claude/ passes (its rules quote the banned form)" 0 \
  "$(run_hook "$(t_edit "$ROOT/.claude/rules/credits.md" "$CREDIT")")"
check "the same credit in a doc outside .claude/ and .githooks/ blocks" 2 \
  "$(run_hook "$(t_edit "$ROOT/docs/credits.md" "$CREDIT")")"
check "a reviewer name in a test file passes (a test names the finding it pins)" 0 \
  "$(run_hook "$(json "$ROOT/src/services/__tests__/s.test.ts" '// Codex P1: guard the concurrent operator case')")"

# --- memory index cap ----------------------------------------------------------
# MEMORY.md loads into every session and is re-sent on every call, so a write
# that leaves it over 18,000 bytes is refused. Shrinking an over-cap index must
# still pass, or the cleanup edit itself is blocked.
MEMROOT=$(mktemp -d); mkdir -p "$MEMROOT/memory" "$MEMROOT/notes"
MEMF="$MEMROOT/memory/MEMORY.md"
bytes() { head -c "$1" /dev/zero | tr '\0' a; }
check "a Write of 18,001 bytes to memory/MEMORY.md blocks" 2 "$(run_hook "$(t_write "$MEMF" "$(bytes 18001)")")"
check "a Write of 18,000 bytes to memory/MEMORY.md passes" 0 "$(run_hook "$(t_write "$MEMF" "$(bytes 18000)")")"
rm -rf "$MEMROOT"

# --- a hook must still parse after the edit ------------------------------------
mkdir -p "$HK/.claude/hooks/lib" "$HK/.claude/scripts"
GOOD=$'#!/usr/bin/env bash\nLINE=$(jq -c \'{a: 1,\n  # a repeated call is visible\n  b: 2}\' <<<"$INPUT")\nexit 0\n'
printf '%s' "$GOOD" > "$HK/.claude/hooks/log.sh"
printf '%s' "$GOOD" > "$HK/.claude/hooks/lib/part.sh"
printf '%s' "$GOOD" > "$HK/.claude/scripts/tool.sh"
printf '%s' "${GOOD/a repeated call is/a repeated call\'s}" > "$HK/.claude/hooks/broken.sh"
json_write() { jq -cn --arg fp "$1" --arg c "$2" '{tool_input:{file_path:$fp, content:$c}}'; }
check "an edit that leaves a hook unparseable blocks" 2 \
  "$(run_hook "$(json_edit "$HK/.claude/hooks/log.sh" 'a repeated call is visible' "a repeated call's visible")")"
check "an edit that keeps a hook parseable passes" 0 \
  "$(run_hook "$(json_edit "$HK/.claude/hooks/log.sh" 'a repeated call is visible' 'a repeated call shows')")"
check "the edit that repairs a broken hook passes" 0 \
  "$(run_hook "$(json_edit "$HK/.claude/hooks/broken.sh" "a repeated call's" 'a repeated call is')")"

# --- issues 392 and 398: placeholder copy in screen code -----------------------
# A project with screenPaths and three unit worktrees whose briefs name a plan committed on main. The hook runs
# from the worktree, as a Builder session does; the file is always an absolute path.
SP=$(cd "$TMP" && pwd -P)/screens; mkdir -p "$SP"
git init -q -b main "$SP/proj"; mkdir -p "$SP/proj/.claude/plans"
printf '{"version":1,"screenPaths":["web/src/"]}\n' > "$SP/proj/.claude/commandeck.json"
COPY='<p>Coming soon</p>'
printf 'Placeholder: web/src/X.tsx | %s | the tab ships in the next plan\n' "$COPY" > "$SP/proj/.claude/plans/u2.md"
printf 'Placeholder: web/src/X.tsx | Coming soon | why\n' > "$SP/proj/.claude/plans/u3.md"
git -C "$SP/proj" add -A; git -C "$SP/proj" -c user.name=t -c user.email=t@t commit -qm base
for u in u1 u2 u3; do
  git -C "$SP/proj" worktree add -q "$SP/ws/$u" -b "builder/$u"
  mkdir -p "$SP/ws/$u/.claude/briefs"; printf '## Plan\n.claude/plans/%s.md\n' "$u" > "$SP/ws/$u/.claude/briefs/$u.md"
done
run_in()  { (cd "$1" && printf '%s' "$2" | "$HOOK" >/dev/null 2>&1; echo $?); }
msg_in()  { (cd "$1" && printf '%s' "$2" | "$HOOK" 2>&1 >/dev/null); }
W1=$SP/ws/u1 W2=$SP/ws/u2 W3=$SP/ws/u3
check "placeholder copy in screen code is refused, naming the file and the line" "2 1" \
  "$(run_in "$W1" "$(t_edit "$W1/web/src/X.tsx" "$COPY")") $(msg_in "$W1" "$(t_edit "$W1/web/src/X.tsx" "$COPY")" | grep -cF "placeholder copy in $W1/web/src/X.tsx: \"$COPY\"")"
check "the same copy is allowed when the plan names its complete line on a Placeholder line" 0 \
  "$(run_in "$W2" "$(t_edit "$W2/web/src/X.tsx" "$COPY")")"
check "copy named only by a substring of its line is refused" 2 \
  "$(run_in "$W3" "$(t_edit "$W3/web/src/X.tsx" "$COPY")")"
check "placeholder copy outside screen code passes" 0 \
  "$(run_in "$W1" "$(t_edit "$W1/web/src/X.ts" 'const m = "Coming soon";')")"
# Issue 400: the host's phrase and comment rule. A comment-only line ships nothing to a screen; code after a leading
# comment that closes on the line does.
check "under construction copy in screen code is refused" 2 \
  "$(run_in "$W1" "$(t_edit "$W1/web/src/X.tsx" '<p>Under construction</p>')")"
check "a comment line in screen code is not placeholder copy" 0 \
  "$(run_in "$W1" "$(t_edit "$W1/web/src/X.tsx" '// Export lands under construction')")"
check "copy after a closed JSX comment is refused" 2 \
  "$(run_in "$W1" "$(t_edit "$W1/web/src/X.tsx" '{/* tab */} <p>Coming soon</p>')")"
check "a placeholder comment is still caught" 2 \
  "$(run_in "$W1" "$(t_edit "$W1/src/x.ts" '// placeholder until the API lands')")"
check "an absolute screen path is screened" 2 \
  "$(run_in "$W1" "$(t_edit "$W1/web/src/X.tsx" "$COPY")")"
mkdir -p "$W1/web"
check "a session started in a subdirectory still screens the file" "2 1" \
  "$(run_in "$W1/web" "$(t_edit "$W1/web/src/X.tsx" "$COPY")") $(msg_in "$W1/web" "$(t_edit "$W1/web/src/X.tsx" "$COPY")" | grep -cF "$W1/web/src/X.tsx")"
# The file's own checkout decides, never the session's: from u2, whose plan approves the copy, u1's file is refused.
check "a session in another checkout screens the file by the file's checkout" 2 \
  "$(run_in "$W2" "$(t_edit "$W1/web/src/X.tsx" "$COPY")")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
