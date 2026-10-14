#!/usr/bin/env bash
# codex-dispatch.test.sh -- Codex reads no hooks.json of ours, so without the
# dispatcher every guard is prose for Codex and enforcement for Claude. What
# this pins: a set-up, trusted project gets the plugin's hooks for the five
# events, chosen by the same matcher rule Claude Code uses; a project that is
# not set up or not trusted runs none of them; a patch reaches the Write and
# Edit hooks one file at a time; a warning is relayed, not swallowed; and a
# dispatcher that could not run says so instead of reading as a clean turn.
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

# A plugin root with the real dispatcher and a fixture hooks.json. rec.sh
# records each call and acts on its first argument.
P=$T/plugin; mkdir -p "$P/hooks/lib"
cp "$SOURCE/hooks/codex-dispatch.sh" "$P/hooks/" 2>/dev/null
cp "$SOURCE/hooks/lib/hook-fire-log.sh" "$SOURCE/hooks/lib/project.sh" "$SOURCE/hooks/lib/run-hook.sh" "$P/hooks/lib/"
cat > "$P/hooks/rec.sh" <<'REC'
#!/usr/bin/env bash
IN=$(cat)
printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$(jq -r '.tool_name // "-"' <<<"$IN")" "$(jq -r '.tool_input.file_path // "-"' <<<"$IN")" \
  "${AGENT_KIND:-}" "$(jq -r '.tool_input | .content // .new_string // "-"' <<<"$IN" | head -1)" >> "$REC_LOG"
jq -c '.tool_input.anchors // empty' <<<"$IN" >> "$REC_LOG.anchors"
jq -c '.tool_input.file_edits // empty | map([.old_string, .new_string, ((.anchors // []) | join(","))] | join(">"))' <<<"$IN" >> "$REC_LOG.hunks"
jq -r '.tool_input | select(.source_path != null) | "\(.source_path) > \(.file_path)"' <<<"$IN" >> "$REC_LOG.source"
jq -c '.tool_input.batch_paths // empty | map(sub(".*/"; ""))' <<<"$IN" >> "$REC_LOG.batch"
case $1 in
  deny) echo "BLOCKED: fixture denial" >&2; exit 2 ;;
  warn) echo "WARNING: fixture warning" >&2 ;;
  context) echo "fixture context" ;;
  json-deny) jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "fixture json denial"}}' ;;
  json-allow) jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: "fixture allow"}}' ;;
  advise) jq -n --arg m "advice from $1" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}' ;;
  json-block) jq -n '{decision: "block", reason: "fixture stop refusal"}' ;;
  crash) echo "fixture crash" >&2; exit 1 ;;
esac
exit 0
REC
printf '#!/usr/bin/env bash\n# codex: skip -- fixture: Claude-only\necho ran >> "$REC_LOG"\n' > "$P/hooks/skipped.sh"
chmod +x "$P/hooks/"*.sh
# As hooks.json spells them: through the launcher, the hook's path quoted, any
# argument after it. The hook is the second path: the skip marker and the
# read-only keep-list are read from it, never from the launcher.
h() { local a=${1#* }; [ "$a" != "$1" ] || a=; printf '{"type":"command","command":"\\"${CLAUDE_PLUGIN_ROOT}/hooks/lib/run-hook.sh\\" \\"${CLAUDE_PLUGIN_ROOT}/hooks/%s\\"%s"}' "${1%% *}" "${a:+ $a}"; }
cat > "$P/hooks/hooks.json" <<JSON
{"hooks": {
  "SessionStart": [{"matcher": "*", "hooks": [$(h "rec.sh context")]}],
  "Stop": [{"matcher": "*", "hooks": [$(h "rec.sh \$STOP_MODE")]}],
  "PreToolUse": [
    {"matcher": ".*", "hooks": [$(h "rec.sh pre-any"), $(h skipped.sh)]},
    {"matcher": "Bash", "hooks": [$(h "rec.sh \$BASH_MODE")]},
    {"matcher": "Edit|Write|MultiEdit", "hooks": [$(h "rec.sh pre-edit")]},
    {"matcher": "Write", "hooks": [$(h "rec.sh pre-write")]},
    {"matcher": "WebFetch", "hooks": [$(h "rec.sh pre-web")]}],
  "PostToolUse": [{"matcher": "Bash", "hooks": [$(h "rec.sh warn")]}]
}}
JSON

export HOME=$T/home CODEX_HOME=$T/codex REC_LOG=$T/rec.log COMMANDECK_HOOK_FIRE_LOG=$T/fire.jsonl XDG_CACHE_HOME=$T/cache
mkdir -p "$HOME" "$CODEX_HOME"
repo() { git init -q -b main "$T/$1" && git -C "$T/$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first; }
repo ours; repo not-set-up; repo untrusted
mkdir -p "$T/ours/.claude" "$T/untrusted/.claude" "$T/ours/src"
echo '{"version":1}' > "$T/ours/.claude/commandeck.json"; echo '{"version":1}' > "$T/untrusted/.claude/commandeck.json"
git -C "$T/ours" worktree add -q "$T/ours-wt" -b wt
printf '[projects."%s"]\ntrust_level = "trusted"\n[projects."%s"]\ntrust_level = "trusted"\n' "$T/ours" "$T/not-set-up" > "$CODEX_HOME/config.toml"

# run <cwd> <event> <tool> [tool_input json] -- sets RC, OUT (stdout), ERR (stderr); the record starts empty.
run() {
  : > "$REC_LOG"
  OUT=$(jq -cn --arg c "$1" --arg e "$2" --arg t "$3" --argjson i "${4:-null}" \
    '{session_id: "s1", cwd: $c, hook_event_name: $e} + (if $t == "" then {} else {tool_name: $t, tool_input: $i} end)' \
    | BASH_MODE=${BASH_MODE:-pre-bash} STOP_MODE=${STOP_MODE:-stop} bash "$P/hooks/codex-dispatch.sh" 2>"$T/err"); RC=$?
  ERR=$(cat "$T/err")
}
ran() { cut -f1 "$REC_LOG" | tr '\n' ' ' | sed 's/ $//'; }
CMD='{"command":"ls"}'

# --- which projects get the hooks ---
run "$T/ours" PreToolUse Bash "$CMD"
check "a set-up, trusted project runs the groups whose matcher fits, in file order" 'pre-any pre-bash' "$(ran)"
check "an allowed call exits 0" 0 "$RC"
check "the hooks see a Codex agent" 'codex' "$(sed -n 1p "$REC_LOG" | cut -f4)"
check "a hook marked codex: skip is not run" 0 "$(grep -c '^ran$' "$REC_LOG")"
check "and the skip is logged, so an absent rule is visible" 1 "$(grep -c 'skipped.sh.skipped$' "$XDG_CACHE_HOME/commandeck/codex-dispatch.log" 2>/dev/null)"
run "$T/ours-wt" PreToolUse Bash "$CMD"
check "a worktree of a trusted project runs them too" 'pre-any pre-bash' "$(ran)"
run "$T/not-set-up" PreToolUse Bash "$CMD"
check "a project the plugin was not set up in runs nothing" '0:' "$RC:$(ran)"
run "$T/untrusted" PreToolUse Bash "$CMD"
check "a project Codex does not trust runs nothing" '0:' "$RC:$(ran)"
run "$T" PreToolUse Bash "$CMD"
check "a folder that is no checkout runs nothing" '0:' "$RC:$(ran)"

# --- a denial, a warning and context reach Codex ---
BASH_MODE=deny run "$T/ours" PreToolUse Bash "$CMD"
check "a denial is relayed as exit 2" 2 "$RC"
check "with the hook's own message" 1 "$(grep -c 'BLOCKED: fixture denial' <<<"$ERR")"
# Claude Code also takes a refusal as JSON on stdout with exit 0, and the Stop
# hooks that hold a turn open speak only that way: dropped, Codex stops anyway.
BASH_MODE=json-deny run "$T/ours" PreToolUse Bash "$CMD"
check "a denial written as JSON on stdout is a denial" '2:1' "$RC:$(grep -c '^fixture json denial$' <<<"$ERR")"
check "and its JSON does not reach Codex as output" '' "$OUT"
BASH_MODE=json-allow run "$T/ours" PreToolUse Bash "$CMD"
check "an allow written as JSON is not a denial" 0 "$RC"
# A passing hook's advice is for the model: Codex reads it from one JSON object on stdout.
BASH_MODE=advise run "$T/ours" PreToolUse Bash "$CMD"
check "a hook's additionalContext reaches Codex, under the event's name" '0|PreToolUse|advice from advise' "$RC|$(jq -r '.hookSpecificOutput | "\(.hookEventName)|\(.additionalContext)"' <<<"$OUT" 2>/dev/null)"
check "as one line of JSON and nothing else" 1 "$(grep -c . <<<"$OUT")"
STOP_MODE=json-block run "$T/ours" Stop ''
check "a Stop hook's block on stdout holds the turn, with its reason" '2:1' "$RC:$(grep -c '^fixture stop refusal$' <<<"$ERR")"
# Claude Code runs the call when a hook exits with anything but 0 or 2, and so
# does this; what must not happen is that nobody is told the rule did not run.
BASH_MODE=crash run "$T/ours" PreToolUse Bash "$CMD"
check "a hook that breaks does not refuse the call" 0 "$RC"
check "but Codex is told which hook broke, beside the hook's own words" '1:1' "$(grep -c 'rec.sh exited 1' <<<"$ERR"):$(grep -c 'fixture crash' <<<"$ERR")"
check "and the break is logged" 1 "$(grep -c 'rec.sh.exit 1$' "$XDG_CACHE_HOME/commandeck/codex-dispatch.log" 2>/dev/null)"
run "$T/ours" PostToolUse Bash "$CMD"
check "the event decides: a post call runs the post group only" 'warn' "$(ran)"
check "a warning from a hook that exits 0 is relayed" '0:1' "$RC:$(grep -c 'WARNING: fixture warning' <<<"$ERR")"
run "$T/ours" SessionStart ''
check "session-start context comes back on stdout" 'fixture context' "$OUT"
run "$T/ours" Stop ''
check "Stop runs the Stop group" 'stop' "$(ran)"
run "$T/ours" SubagentStop ''
check "an event the dispatcher does not know runs nothing" '0:' "$RC:$(ran)"
run "$T/ours" PreToolUse WebFetch '{"url":"x"}'
check "a tool Codex does not have is not dispatched" '0:' "$RC:$(ran)"

# --- a patch reaches the Write and Edit hooks one file at a time ---
PATCH=$(printf '*** Begin Patch\n*** Add File: src/new.txt\n+first line\n*** Update File: src/old.txt\n@@\n-was\n+now\n*** Delete File: src/gone.txt\n*** End Patch\n' | jq -Rs '{command: .}')
run "$T/ours" PreToolUse apply_patch "$PATCH"
check "an added file is a Write: it reaches the Write-only group too" "pre-any pre-edit pre-write" "$(awk -F'\t' '$2 == "Write" {print $1}' "$REC_LOG" | tr '\n' ' ' | sed 's/ $//')"
check "an updated file is an Edit: the Write-only group does not see it" "pre-any pre-edit" "$(awk -F'\t' '$2 == "Edit" && $3 ~ /old.txt$/ {print $1}' "$REC_LOG" | tr '\n' ' ' | sed 's/ $//')"
check "each payload names the file's full path and its new text" "$T/ours/src/new.txt	first line" "$(awk -F'\t' '$1 == "pre-write" {print $3 "\t" $5}' "$REC_LOG")"
# A guard that decides by whose file it is (main-edit-guard) must see a
# deletion and the file a move takes away, not only where text lands.
check "a deleted file reaches the Edit hooks by its path, with no text" "pre-any pre-edit" \
  "$(awk -F'\t' -v p="$T/ours/src/gone.txt" '$2 == "Edit" && $3 == p && $5 == "" {print $1}' "$REC_LOG" | tr '\n' ' ' | sed 's/ $//')"
PATCH=$(printf '*** Begin Patch\n*** Update File: src/old.txt\n*** Move to: docs/old.md\n@@\n-was\n+now\n*** End Patch\n' | jq -Rs '{command: .}')
run "$T/ours" PreToolUse apply_patch "$PATCH"
check "a moved file is screened where it leaves and where it lands" "$T/ours/src/old.txt $T/ours/docs/old.md" \
  "$(awk -F'\t' '$1 == "pre-edit" {print $3}' "$REC_LOG" | tr '\n' ' ' | sed 's/ $//')"
# A hook that applies the edit to the file (a new dependency in a manifest)
# reads the text where it still is: the new name is not on disk yet.
check "a moved file's edit names the file its text comes from, and no other payload does" "$T/ours/src/old.txt > $T/ours/docs/old.md" "$(sort -u "$REC_LOG.source")"

# --- a dispatcher that could not run never reads as a clean turn ---
: > "$REC_LOG"
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash"}' | bash "$P/hooks/codex-dispatch.sh" 2>"$T/err"; RC=$?
check "a payload with no cwd is exit 1, naming the cause" '1:1' "$RC:$(grep -c 'no usable cwd' "$T/err")"

# Two hunks of one file are two edits. Joined into one text, lines far apart
# read as one change, and a guard that compares what an edit adds with what it
# removes (a new dependency in a manifest) saw a change nobody made.
PATCH=$(printf '*** Begin Patch\n*** Update File: src/old.txt\n@@\n-was1\n+now1\n@@\n-was2\n+now2\n*** End Patch\n' | jq -Rs '{command: .}')
run "$T/ours" PreToolUse apply_patch "$PATCH"
check "each hunk of a file is its own Edit" "now1 now2" "$(awk -F'\t' '$1 == "pre-edit" {print $5}' "$REC_LOG" | tr '\n' ' ' | sed 's/ $//')"

# A hunk's `@@ <line>` says where in the file it lands, and each hunk comes
# after the one before it. A guard that applies the edit to the file on disk
# needs both: the same lines may sit in a part of the file it does not screen.
PATCH=$(printf '*** Begin Patch\n*** Update File: src/old.txt\n@@ [project]\n-was1\n+now1\n@@\n-was2\n+now2\n*** End Patch\n' | jq -Rs '{command: .}')
: > "$REC_LOG.anchors"; : > "$REC_LOG.hunks"
run "$T/ours" PreToolUse apply_patch "$PATCH"
check "each Edit carries the lines its hunk comes after" '["[project]","was1"] ["[project]"]' "$(LC_ALL=C sort -u "$REC_LOG.anchors" | paste -sd' ' -)"
# A guard that reads a manifest must see all of a file's hunks at once: one
# alone may leave text that is not the file the patch makes.
check "each Edit of a file with several hunks carries them all" '["was1>now1>[project]","was2>now2>"]' "$(sort -u "$REC_LOG.hunks" 2>/dev/null)"

# A hook that caps how many files one change set touches sees a patch one file
# at a time, none written yet: each payload names every file the patch writes.
PATCH=$(printf '*** Begin Patch\n*** Add File: src/new.txt\n+first line\n*** Update File: src/old.txt\n@@\n-was\n+now\n*** Delete File: src/gone.txt\n*** End Patch\n' | jq -Rs '{command: .}')
: > "$REC_LOG.batch"
run "$T/ours" PreToolUse apply_patch "$PATCH"
check "each payload of a patch names the files it writes" '["new.txt","old.txt"]' "$(sort -u "$REC_LOG.batch" | paste -sd' ' -)"

# --- a guard marked onFailure: block refuses the call when it cannot run ---
# hooks.json marks the guards that way: a guard that broke, or is missing, has
# screened nothing, and Codex must not run the call as if it had.
cat > "$P/hooks/hooks.json" <<JSON
{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
  {"type": "command", "command": "\${CLAUDE_PLUGIN_ROOT}/hooks/rec.sh \$BASH_MODE", "onFailure": "block"},
  {"type": "command", "command": "\${CLAUDE_PLUGIN_ROOT}/hooks/\$SECOND", "onFailure": "block"}]}]}}
JSON
SECOND='rec.sh pre-bash' BASH_MODE=crash run "$T/ours" PreToolUse Bash "$CMD"
check "a guard that breaks refuses the call, naming itself" '2:1' "$RC:$(grep -c 'rec.sh exited 1' <<<"$ERR")"
check "and the hooks after it do not run" 'crash' "$(ran)"
SECOND=gone.sh run "$T/ours" PreToolUse Bash "$CMD"
check "a guard that is missing refuses the call" '2:1' "$RC:$(grep -c 'BLOCKED: .* exited 127' <<<"$ERR")"
SECOND='rec.sh pre-bash' run "$T/ours" PreToolUse Bash "$CMD"
check "the same guards, working, allow it" '0:pre-bash pre-bash' "$RC:$(ran)"

# --- a read-only run keeps the guards on the keep-list and drops the rest ---
# The run is read-only when the session record Codex names says so in EVERY
# turn row, approvals off, and no sandboxed run could have written the record.
row() { printf '{"type":"turn_context","payload":{"approval_policy":"%s","sandbox_policy":%s}}\n' "$1" "$2"; }
SES=$HOME/.codex/sessions; mkdir -p "$SES" "$HOME/.codex-other/sessions"
row never '{"type":"read-only"}' > "$SES/ro.jsonl"
row never '{"type":"workspace-write"}' > "$SES/write.jsonl"
{ row never '{"type":"read-only"}'; row never '{"type":"workspace-write"}'; } > "$SES/was-write.jsonl"
row on-request '{"type":"read-only"}' > "$SES/asks.jsonl"
row never '{"type":"read-only","network_access":true}' > "$SES/extra.jsonl"
printf '{"type":"message","text":"{\\"type\\":\\"turn_context\\"}"}\n' > "$SES/no-turn.jsonl"
cp "$SES/ro.jsonl" "$HOME/.codex-other/sessions/ro.jsonl"; cp "$SES/ro.jsonl" "$T/ours/ro.jsonl"
ln -s "$T/ours/ro.jsonl" "$SES/link.jsonl"
ro() { # transcript path -> the exit code of a Bash call whose own guard denies it
  : > "$REC_LOG"
  jq -cn --arg c "$T/ours" --arg t "$1" '{session_id: "s1", cwd: $c, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "ls"}}
      + (if $t == "" then {} else {transcript_path: $t} end)' \
    | BASH_MODE=deny STOP_MODE=stop bash "$P/hooks/codex-dispatch.sh" >/dev/null 2>&1; echo $?
}
check "a guard off the keep-list is dropped on a read-only run" "0:" "$(ro "$SES/ro.jsonl"):$(ran)"
check "with no session record nothing is skipped" 2 "$(ro "")"
check "a record that is not there skips nothing" 2 "$(ro "$SES/none.jsonl")"
check "a write-capable run skips nothing" 2 "$(ro "$SES/write.jsonl")"
check "a run that was write-capable in one turn skips nothing" 2 "$(ro "$SES/was-write.jsonl")"
check "read-only but allowed to ask for more skips nothing" 2 "$(ro "$SES/asks.jsonl")"
check "a read-only policy carrying anything more skips nothing" 2 "$(ro "$SES/extra.jsonl")"
check "a record with no turn row skips nothing" 2 "$(ro "$SES/no-turn.jsonl")"
check "a record outside a real Codex home skips nothing" 2 "$(ro "$HOME/.codex-other/sessions/ro.jsonl")"
check "a record in the run's own folder skips nothing" 2 "$(ro "$T/ours/ro.jsonl")"
check "nor does a link from the sessions folder to one" 2 "$(ro "$SES/link.jsonl")"
check "READ_ONLY=1 in the environment skips nothing" 2 "$(READ_ONLY=1 ro "")"
# A guard on the keep-list runs whatever the run is.
cp "$P/hooks/rec.sh" "$P/hooks/suite-rerun-guard.sh"
printf '{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [%s]}]}}\n' "$(h "suite-rerun-guard.sh deny")" > "$P/hooks/hooks.json"
check "a guard on the keep-list still refuses in a read-only run" 2 "$(ro "$SES/ro.jsonl")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
