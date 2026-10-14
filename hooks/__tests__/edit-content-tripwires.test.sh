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

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
