#!/usr/bin/env bash
# setup-gate.test.sh -- installed for the user, the plugin's hooks are run by
# Claude Code in every project on the machine. A project setup never touched
# (no .claude/commandeck.json in its checkout or its main checkout) must run
# none of them: no block, no advice, no log row. Claude Code sets
# CLAUDE_PLUGIN_ROOT for a plugin's hook; a hook run without it (a self-test)
# is not gated.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
mkdir -p "$T/home" "$T/bare/src" "$T/plain" "$T/set/.claude"
for p in bare set; do git -C "$T/$p" init -q -b main && git -C "$T/$p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init; done
echo '{}' > "$T/set/.claude/commandeck.json"
git -C "$T/set" worktree add -q "$T/wt" -b unit >/dev/null 2>&1
payload() { jq -cn --arg d "$1" '{session_id: "s1", hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, prompt: "x",
  tool_input: {command: "npm install leftpad", file_path: ($d + "/src/a.js"), old_string: "a", new_string: "b", content: "b"}}'; }
# run <project dir> <plugin root or ""> <command> -- a clean environment: no
# variable of the session running this test reaches a hook.
run() {
  ( cd "$1" && payload "$1" | env -i PATH="$PATH" HOME="$T/home" COMMANDECK_HOST_OS=Linux COMMANDECK_HOOK_FIRE_LOG="$T/fire.jsonl" \
      CLAUDE_PROJECT_DIR="$1" ${2:+CLAUDE_PLUGIN_ROOT="$2"} bash -c "$3" )
}
rows() { [ -e "$T/fire.jsonl" ] && wc -l < "$T/fire.jsonl" | tr -d ' ' || echo 0; }

N=0 LOUD=
while IFS= read -r cmd; do
  N=$((N + 1))
  for p in bare plain; do
    OUT=$(run "$T/$p" "$ROOT" "$cmd" 2>&1); RC=$?
    [ "$RC" = 0 ] && [ -z "$OUT" ] || LOUD="$LOUD $p:${cmd##*/hooks/}=$RC"
  done
done < <(jq -r '.hooks[][].hooks[].command' "$ROOT/hooks/hooks.json")
check "every registered hook was run" 48 "$N"
check "in a project never set up, and in a folder that is no project, no hook blocks or prints" "" "$LOUD"
check "and none writes a log row" 0 "$(rows)"
check "or any file: the project, the folder and the home are as they were" "||" \
  "$(git -C "$T/bare" status --porcelain --untracked-files=all)|$(ls -A "$T/plain")|$(ls -A "$T/home")"

GUARD="\"\${CLAUDE_PLUGIN_ROOT}/hooks/main-edit-guard.sh\""
run "$T/set" "$ROOT" "$GUARD" >/dev/null 2>&1
check "in a project that was set up the hook runs" 1 "$(rows)"
run "$T/wt" "$ROOT" "$GUARD" >/dev/null 2>&1
check "a worktree of a set-up project counts as set up" 2 "$(rows)"
run "$T/bare" "" "bash '$ROOT/hooks/main-edit-guard.sh'" >/dev/null 2>&1
check "a hook run without CLAUDE_PLUGIN_ROOT is not gated" 3 "$(rows)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
