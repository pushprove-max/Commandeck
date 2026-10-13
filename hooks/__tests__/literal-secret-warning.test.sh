#!/usr/bin/env bash
# Self-test for literal-secret-warning.sh. It never blocks by design, so
# "caught" means it SAID so on stderr and still exited 0 -- and it must say so
# for every edit of a MultiEdit, not only the first: the matcher routes batches
# here, and a screen that reads one hunk is decorative.
set -u
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
HOOK=$HOOKS/literal-secret-warning.sh
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected '$2', got '$3')"; fi }
write() { jq -cn --arg fp "$1" --arg s "$2" '{tool_name:"Write", tool_input:{file_path:$fp, content:$s}}'; }
multi() { jq -cn --arg fp "$1" --arg s "$2" '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[
  {old_string:"a", new_string:"const ok = 1;"},{old_string:"b", new_string:$s}]}}'; }
said() { bash "$HOOK" 2>&1 >/dev/null <<<"$1"; }
warned() { said "$1" | grep -qF 'Possible hardcoded secret' && echo 0 || echo 1; }
rc() { bash "$HOOK" >/dev/null 2>&1 <<<"$1"; echo $?; }

# The literal is assembled so this file does not carry one itself.
SECRET="const apiKey = \"hunter2$(printf hunter2)\";"

check "a Write of a hardcoded secret warns"             0 "$(warned "$(write /x/src/a.ts "$SECRET")")"
check "and still lets the write through"                0 "$(rc "$(write /x/src/a.ts "$SECRET")")"
check "a secret in the SECOND edit of a MultiEdit warns" 0 "$(warned "$(multi /x/src/a.ts "$SECRET")")"
# Reading one value from the environment says nothing about the line beside it.
check "an environment read elsewhere in the write hides no secret" 0 "$(warned "$(write /x/src/a.ts "const url = process.env.URL;"$'\n'"$SECRET")")"
check "a benign MultiEdit is SILENT"                    "" "$(said "$(multi /x/src/a.ts 'const x = getSetting("k");')")"
check "a test file is not screened"                     "" "$(said "$(write /x/src/a.test.ts "$SECRET")")"
check "markdown is text, not code"                      "" "$(said "$(write /x/docs/a.md "$SECRET")")"

# A guard that cannot read the payload must not pass the write unread.
mkdir -p "$TMP/hooks"; cp "$HOOK" "$TMP/hooks/"; cp -R "$HOOKS/lib" "$TMP/hooks/"; rm "$TMP/hooks/lib/edit-payload.sh"
check "a missing payload helper BLOCKS" 2 "$(bash "$TMP/hooks/literal-secret-warning.sh" >/dev/null 2>&1 <<<"$(write /x/src/a.ts 'const ok = 1;')"; echo $?)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
