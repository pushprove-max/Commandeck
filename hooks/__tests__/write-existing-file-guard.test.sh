#!/usr/bin/env bash
# Self-test for write-existing-file-guard.sh.
#
# Restatements and unchecked style analysis produce actionable warnings without
# blocking the tool call; genuine rewrites remain silent. The Codex adapter
# reaches the same rule by mapping apply_patch Update File payloads to Edit.
set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/write-existing-file-guard.sh"
SETTINGS="$HOOKS_DIR/hooks.json"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0 FAIL=0

check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
run()     { bash "$HOOK" >/dev/null 2>&1 <<<"$1"; echo $?; }
run_err() { bash "$HOOK" 2>&1 >/dev/null <<<"$1"; }

lines() { seq 1 "$1" | sed 's/^/const x/;s/$/ = 1;/'; }
# The same file with the first $1 lines given a different value.
changed() { lines "$2" | sed "1,${1}s/ = 1;/ = 2;/"; }

write() { jq -cn --arg fp "$1" --arg s "$2" '{tool_name:"Write", tool_input:{file_path:$fp, content:$s}}'; }
edit()  { jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" \
  '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$o, new_string:$n}}'; }
# The restate is the SECOND hunk: a hook that reads only edits[0] returns 0 here.
multi() { jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" \
  '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[
     {old_string:"const a = 1;", new_string:"const a = 2;"},
     {old_string:$o, new_string:$n}]}}'; }
# The path lives inside edits[], not at tool_input.file_path -- the shape
# lib/edit-payload.sh gives precedence to.
multi_per_edit() { jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" \
  '{tool_name:"MultiEdit", tool_input:{edits:[
     {file_path:$fp, old_string:$o, new_string:$n}]}}'; }

SIXTY="$TMP/sixty.ts"; lines 60 > "$SIXTY"
FORTY="$TMP/forty.ts"; lines 40 > "$FORTY"
TEN="$TMP/ten.ts"; lines 10 > "$TEN"
EMPTY="$TMP/empty.ts"; : > "$EMPTY"

# --- allowed: nothing worth a warning ----------------------------------------
check "a Write to a file not on disk passes"  0 "$(run "$(write "$TMP/new.ts" "$(lines 60)")")"
check "a Write over a 10-line file passes"    0 "$(run "$(write "$TEN" "$(changed 1 10)")")"
check "a Write over an empty file passes"     0 "$(run "$(write "$EMPTY" "$(lines 60)")")"
check "a Write over a 10-line file is SILENT" "" "$(run_err "$(write "$TEN" "$(changed 1 10)")")"

# --- the rule: a restate warns, a rewrite stays silent ------------------------
check "a 60-line Write changing 2 lines warns and passes" 0 "$(run "$(write "$SIXTY" "$(changed 2 60)")")"
check "the warning names the restated and changed counts" 0 \
  "$(run_err "$(write "$SIXTY" "$(changed 2 60)")" \
     | grep -qF "WARNING: Write would restate 60 lines of $SIXTY; only 2 change. Use Edit (or serena replace_symbol_body / replace_content) for the changed lines." \
     && echo 0 || echo 1)"
check "a 60-line Write changing 40 lines passes" 0 "$(run "$(write "$SIXTY" "$(changed 40 60)")")"
check "a 60-line Write changing 40 lines is SILENT" "" "$(run_err "$(write "$SIXTY" "$(changed 40 60)")")"
# Unrelated content shares no lines with the file, so it is a rewrite by any reading.
check "a Write of unrelated content passes"   0 \
  "$(run "$(write "$SIXTY" "$(seq 1 60 | sed 's/^/export function f/;s/$/() { return 0; }/')")")"

# --- the denominator is the file being REPLACED, not the longer side ----------
# A real Write ends in a newline. Counting it as a line put the restated count
# one over the file's own length.
check "a trailing newline does not inflate the restated count" 0 \
  "$(run_err "$(write "$SIXTY" "$(changed 2 60)"$'\n')" \
     | grep -qF "WARNING: Write would restate 60 lines of $SIXTY; only 2 change." \
     && echo 0 || echo 1)"
# Truncating to nothing, or to one line, is not a restate: it states no line
# the file already had.
check "an empty Write over the 60-line file passes" 0 "$(run "$(write "$SIXTY" "")")"
check "an empty Write over the 60-line file is SILENT" "" "$(run_err "$(write "$SIXTY" "")")"
check "a one-line Write over the 60-line file passes" 0 "$(run "$(write "$SIXTY" $'x\n')")"
# A shrink keeping 3 of 60 lines: the Edit that does it would restate the 57
# it deletes, so Write is the cheaper call and must not be blocked.
check "a Write shrinking 60 lines to 5 passes" 0 "$(run "$(write "$SIXTY" "$(changed 2 5)")")"
# Growing the file does not buy back the restate: the 60 old lines are stated
# again either way, so the denominator stays the 60 being replaced.
check "a Write appending 40 lines to the 60 warns and passes" 0 \
  "$(run "$(write "$SIXTY" "$(lines 100)")")"
check "the append warning counts the stated and changed lines" 0 \
  "$(run_err "$(write "$SIXTY" "$(lines 100)")" \
     | grep -qF "WARNING: Write would restate 100 lines of $SIXTY; only 40 change." \
     && echo 0 || echo 1)"

# --- the same rule on an Edit and on each MultiEdit hunk ----------------------
# A 60-line old_string with 2 changed lines is the same waste as the Write, and
# it is how a Codex `Update File` arrives.
check "an Edit whose old_string restates 58 of 60 lines warns and passes" 0 \
  "$(run "$(edit "$SIXTY" "$(lines 60)" "$(changed 2 60)")")"
check "the Edit warning names the unchanged and total lines" 0 \
  "$(run_err "$(edit "$SIXTY" "$(lines 60)" "$(changed 2 60)")" \
     | grep -qF "WARNING: Edit old_string restates 58 of its 60 lines of $SIXTY" \
     && echo 0 || echo 1)"
check "an Edit rewriting 40 of its 60 lines passes" 0 \
  "$(run "$(edit "$SIXTY" "$(lines 60)" "$(changed 40 60)")")"
# Deleting a block states none of it back.
check "an Edit deleting a 60-line block passes" 0 \
  "$(run "$(edit "$SIXTY" "$(lines 60)" "")")"
# 20 lines is the floor; below it the restate is not worth a warning.
check "a 19-line old_string with 1 changed passes" 0 \
  "$(run "$(edit "$SIXTY" "$(lines 19)" "$(changed 1 19)")")"
# An old_string under half the file is context, not a rewrite: it can be the
# shortest anchor that makes the one changed line unique.
check "a 20-line old_string over the 60-line file passes" 0 \
  "$(run "$(edit "$SIXTY" "$(lines 20)" "$(changed 1 20)")")"
check "a 20-line old_string over a 40-line file warns and passes" 0 \
  "$(run "$(edit "$FORTY" "$(lines 20)" "$(changed 1 20)")")"
check "a 29-line old_string with 2 changed over the 60-line file passes" 0 \
  "$(run "$(edit "$SIXTY" "$(lines 29)" "$(changed 2 29)")")"
check "a 30-line old_string with 2 changed over the 60-line file warns and passes" 0 \
  "$(run "$(edit "$SIXTY" "$(lines 30)" "$(changed 2 30)")")"
check "that warning names the unchanged and total lines" 0 \
  "$(run_err "$(edit "$SIXTY" "$(lines 30)" "$(changed 2 30)")" \
     | grep -qF "restates 28 of its 30 lines" && echo 0 || echo 1)"
check "an Edit on a path not on disk passes" 0 \
  "$(run "$(edit "$TMP/gone.ts" "$(lines 60)" "$(changed 2 60)")")"
check "a MultiEdit whose SECOND hunk restates warns and passes" 0 \
  "$(run "$(multi "$SIXTY" "$(lines 60)" "$(changed 2 60)")")"
check "the MultiEdit warning names the tool" 0 \
  "$(run_err "$(multi "$SIXTY" "$(lines 60)" "$(changed 2 60)")" \
     | grep -qF "WARNING: MultiEdit old_string restates 58 of its 60 lines of $SIXTY" \
     && echo 0 || echo 1)"
check "a MultiEdit whose only path is inside edits[] passes on a small hunk" 0 \
  "$(run "$(multi_per_edit "$SIXTY" "const a = 1;" "const a = 2;")")"
check "a MultiEdit whose only path is inside edits[] warns and passes" 0 \
  "$(run "$(multi_per_edit "$SIXTY" "$(lines 60)" "$(changed 2 60)")")"
check "that warning names MultiEdit and the per-edit target" 0 \
  "$(run_err "$(multi_per_edit "$SIXTY" "$(lines 60)" "$(changed 2 60)")" \
     | grep -qF "WARNING: MultiEdit old_string restates 58 of its 60 lines" \
     && echo 0 || echo 1)"
check "a MultiEdit with no file_path anywhere warns and passes" 0 \
  "$(run "$(jq -cn --arg o "$(lines 60)" --arg n "$(changed 2 60)" \
     '{tool_name:"MultiEdit", tool_input:{edits:[{old_string:$o, new_string:$n}]}}')")"
check "that warning says the MultiEdit was NOT checked" 0 \
  "$(run_err "$(jq -cn --arg o "$(lines 60)" --arg n "$(changed 2 60)" \
     '{tool_name:"MultiEdit", tool_input:{edits:[{old_string:$o, new_string:$n}]}}')" \
     | grep -q 'WARNING: write-existing-file-guard: .*this MultiEdit was NOT checked\.' && echo 0 || echo 1)"
check "an Edit payload with no new_string warns and passes" 0 \
  "$(run "$(jq -cn --arg fp "$SIXTY" --arg o "x" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$o}}')")"
check "the Edit warning says the Edit was NOT checked" 0 \
  "$(run_err "$(jq -cn --arg fp "$SIXTY" --arg o "x" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$o}}')" \
     | grep -q 'WARNING: write-existing-file-guard: .*this Edit was NOT checked\.' && echo 0 || echo 1)"

# --- unchecked style analysis warns and permits the tool call ------------------
check "a Write payload with no content warns and passes" 0 \
  "$(run "$(jq -cn --arg fp "$SIXTY" '{tool_name:"Write", tool_input:{file_path:$fp}}')")"
check "a Write payload with no file_path warns and passes" 0 \
  "$(run "$(jq -cn --arg s "x" '{tool_name:"Write", tool_input:{content:$s}}')")"
check "the warning says the Write was NOT checked" 0 \
  "$(run_err "$(jq -cn --arg fp "$SIXTY" '{tool_name:"Write", tool_input:{file_path:$fp}}')" \
     | grep -q 'WARNING: write-existing-file-guard: .* -- this Write was NOT checked\.' && echo 0 || echo 1)"

# python3 removed from PATH, jq and awk left in place: the hook still needs them
# to reach the point where it discovers it cannot compare.
BIN="$TMP/bin"; mkdir -p "$BIN"
for tool in bash cat jq awk sed seq grep; do ln -sf "$(command -v "$tool")" "$BIN/$tool"; done
check "python3 absent warns and passes" 0 \
  "$(PATH="$BIN" bash "$HOOK" >/dev/null 2>&1 <<<"$(write "$SIXTY" "$(changed 2 60)")"; echo $?)"
# ...and the same missing python3 proves the prefilter runs FIRST: an edit too
# too small to ever warn never reaches it, which is the point of counting newlines
# in the shell.
check "a small edit does not even reach python3" 0 \
  "$(PATH="$BIN" bash "$HOOK" >/dev/null 2>&1 <<<"$(edit "$SIXTY" "$(lines 3)" "$(changed 1 3)")"; echo $?)"
check "the python3 warning names python3 and says NOT checked" 0 \
  "$(PATH="$BIN" bash "$HOOK" 2>&1 >/dev/null <<<"$(write "$SIXTY" "$(changed 2 60)")" \
     | grep -q 'WARNING: write-existing-file-guard: python3.*NOT checked' && echo 0 || echo 1)"

# --- too small to judge, or not this hook's business --------------------------
check "a one-line Edit payload passes"  0 \
  "$(run "$(jq -cn --arg fp "$SIXTY" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"a", new_string:"b"}}')")"
check "a one-line MultiEdit payload passes" 0 \
  "$(run "$(jq -cn --arg fp "$SIXTY" '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:[{old_string:"a", new_string:"b"}]}}')")"
check "a Bash payload passes"   0 "$(run "$(jq -cn '{tool_name:"Bash",tool_input:{command:"ls"}}')")"
check "a non-JSON payload is not a Write and passes" 0 "$(run 'not json')"

# --- producer/consumer: registered where Writes actually arrive ----------------
check "registered under the Edit|Write|MultiEdit matcher" 0 \
  "$(jq -e '.hooks.PreToolUse[] | select(.matcher == "Edit|Write|MultiEdit") | .hooks[] | select(.command | endswith("write-existing-file-guard.sh\""))' "$SETTINGS" >/dev/null && echo 0 || echo 1)"

# --- Codex: an apply_patch `Add File` arrives here as a Write ------------------
# Its own project, plugin folder and Codex home, so the case cannot depend on
# this machine's trust table and cannot run the plugin's other hooks.
REPO=$(cd "$(mktemp -d)" && pwd -P); CODEX=$(mktemp -d)
trap 'rm -rf "$TMP" "$REPO" "$CODEX"' EXIT
git -C "$REPO" init -q
mkdir -p "$REPO/.claude"; echo '{"version": 1}' > "$REPO/.claude/commandeck.json"
CP=$TMP/codex-plugin; mkdir -p "$CP/hooks/lib"
cp "$HOOKS_DIR/codex-dispatch.sh" "$HOOK" "$CP/hooks/"; cp "$HOOKS_DIR"/lib/*.sh "$CP/hooks/lib/"
jq -n --arg h "${HOOK##*/}" '{hooks: {PreToolUse: [{matcher: "Edit|Write|MultiEdit",
  hooks: [{type: "command", command: ("${CLAUDE_PLUGIN_ROOT}/hooks/" + $h)}]}]}}' > "$CP/hooks/hooks.json"
printf '[projects."%s"]\ntrust_level = "trusted"\n' "$REPO" > "$CODEX/config.toml"
lines 60 > "$REPO/target.ts"

# The shape a Codex full-file rewrite really takes: every line of the file as a
# `-`, every line of the replacement as a `+`. The dispatcher hands that to the
# hook as an Edit, not a Write.
update_file_patch() {
  { echo '*** Begin Patch'; echo '*** Update File: target.ts'
    lines 60 | sed 's/^/-/'; "$@" | sed 's/^/+/'; echo '*** End Patch'; }
}
# Four scattered one-line fixes, 3 context lines each side -- the smallest
# patch Codex can emit for them. The dispatcher pools every hunk into ONE
# old_string, so this arrives as 28 lines against a 60-line file.
hunks_patch() {
  { echo '*** Begin Patch'; echo '*** Update File: target.ts'
    for n in 10 20 30 40; do
      echo '@@'
      for c in $((n-3)) $((n-2)) $((n-1)); do echo " const x$c = 1;"; done
      echo "-const x$n = 1;"
      echo "+const x$n = 2;"
      for c in $((n+1)) $((n+2)) $((n+3)); do echo " const x$c = 1;"; done
    done
    echo '*** End Patch'; }
}
add_file_patch() {
  { echo '*** Begin Patch'; echo '*** Add File: fresh.ts'; "$@" | sed 's/^/+/'; echo '*** End Patch'; }
}
dispatch() {
  jq -cn --arg cwd "$REPO" --arg p "$1" \
    '{cwd:$cwd, hook_event_name:"PreToolUse", tool_name:"apply_patch", tool_input:{command:$p}}' \
  | env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_PREFIX -u GIT_COMMON_DIR \
        CODEX_HOME="$CODEX" XDG_CACHE_HOME="$TMP/cache" bash "$CP/hooks/codex-dispatch.sh" 2>&1 >/dev/null
}

RESTATE=$(dispatch "$(update_file_patch changed 2 60)")
check "a Codex Update File that restates the file warns" 0 \
  "$(printf '%s' "$RESTATE" | grep -q 'WARNING: Edit old_string restates' && echo 0 || echo 1)"
check "a Codex Update File warning allows the dispatcher" 0 \
  "$(dispatch "$(update_file_patch changed 2 60)" >/dev/null; echo $?)"
REWRITE=$(dispatch "$(update_file_patch changed 40 60)")
check "a Codex Update File that rewrites the file is SILENT" "" "$REWRITE"
# Codex cannot shrink a hunk below its own 3 lines of context, so pooled
# minimal hunks must pass: blocking them would block a correct patch.
MINIMAL=$(dispatch "$(hunks_patch)")
check "four minimal Codex hunks in the 60-line file are SILENT" "" "$MINIMAL"
# An Add File to a path with nothing on disk states no line twice.
ADDED=$(dispatch "$(add_file_patch lines 60)")
check "a Codex Add File to a new path is SILENT" "" "$ADDED"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
