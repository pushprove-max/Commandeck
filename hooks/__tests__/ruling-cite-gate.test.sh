#!/usr/bin/env bash
# ruling-cite-gate.test.sh -- a memory or rule line that credits a ruling to the owner must cite
# ruling:r-<id>, and the id must be in the ruling log that ruling-log.sh writes. Only added lines are read.
# The hook goes through hooks/lib/run-hook.sh, as Claude Code starts it.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOOK=$ROOT/hooks/ruling-cite-gate.sh LAUNCH=$ROOT/hooks/lib/run-hook.sh
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export COMMANDECK_RULING_LOG=$T/log.jsonl
GOOD=r-19990101-120000-1-a1b2c3 VOID=r-19990101-120001-1-a1b2c4 NONE=r-19990101-120002-1-a1b2c5
printf '%s\n' "{\"id\":\"$GOOD\",\"pick\":\"option\"}" "{\"id\":\"$VOID\",\"void\":true}" > "$COMMANDECK_RULING_LOG"
MEM=$T/home/.claude/projects/p/memory RULES=$T/repo/.claude/rules PROFILE=$T/profile/home/projects/enc/memory
mkdir -p "$MEM" "$RULES" "$PROFILE" "$T/repo/src"
write() { jq -cn --arg f "$1" --arg c "$2" '{hook_event_name: "PreToolUse", tool_name: "Write", tool_input: {file_path: $f, content: $c}}'; }
edit() { jq -cn --arg f "$1" --arg o "$2" --arg n "$3" '{hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: {file_path: $f, old_string: $o, new_string: $n}}'; }
# multi <path> <new text> -- a MultiEdit whose path sits on its edit; a batch's first edit is outside the gate's scope
multi() { jq -cn --arg s "$T/repo/src/a.ts" --arg f "$1" --arg n "$2" '{hook_event_name: "PreToolUse", tool_name: "MultiEdit", tool_input: {edits: [{file_path: $s, old_string: "a", new_string: "b"}, {file_path: $f, old_string: "", new_string: $n}]}}'; }
# run <payload> -- the hook's status; its stderr is left in $T/err
run() { sh "$LAUNCH" "$HOOK" <<<"$1" 2>"$T/err" >/dev/null; echo $?; }
NOTE=$MEM/grip.md

# Catches: an invented ruling obeyed as the owner's, because nothing asked the line to point at what was said.
rc=$(run "$(write "$NOTE" "The owner ruling 2026-10-01: grip stays.")")
msg="$(grep -o 'grip stays\.' "$T/err" | head -1):$(grep -q '`jq' "$T/err"; echo $?)"
# the refusal names the line and gives a command; owner's ruling, owner ruled and a bare id are claims too; a MultiEdit
# whose path sits on the edit is screened like an Edit, and the text of its edit outside the gate's scope is not read as the note's.
check "a claim with no id is refused" "2|grip stays.:0|2 2 2 2 0" \
  "$rc|$msg|$(run "$(write "$NOTE" "The owner's ruling: grip stays.")") $(run "$(write "$NOTE" "The owner ruled: grip stays.")") $(run "$(write "$NOTE" "Grip stays, ruling:$NONE.")") $(run "$(multi "$NOTE" "The owner ruled: grip stays.")") $(run "$(multi "$NOTE" "Grip stays, no claim here.")")"

# Catches: a made-up id that has the right shape passing as a citation.
rc=$(run "$(write "$NOTE" "The owner ruling ruling:$NONE: grip stays.")")
check "an unlogged id is refused" "2|1" "$rc|$(grep -c 'not logged' "$T/err")"

# Catches: the gate refusing a real citation, which would push notes out of the memory.
rc=$(run "$(write "$NOTE" "The owner ruling ruling:$GOOD: grip stays.")")
check "a logged id passes" "0|" "$rc|$(cat "$T/err")"

# Catches: a voided answer (a stray Enter, an Orca nudge) cited as a ruling.
rc=$(run "$(write "$NOTE" "The owner ruling ruling:$VOID: grip stays.")")
check "a void id is refused" "2|1" "$rc|$(grep -c "void, or suspect.*$VOID" "$T/err")"

# Catches: old lines blocking every later edit of the file, and an edit of an old line's date slipping through.
OLD="The owner ruling 2026-09-10: clear line is 180K."
printf '%s\n' "$OLD" > "$NOTE"
# changing the date inside an old line makes it new
check "an old line passes" "0|2" "$(run "$(edit "$NOTE" "$OLD" "$OLD
A plain line.")")|$(run "$(edit "$NOTE" "2026-09-10" "2026-09-11")")"

# Catches: the screen looking for a .claude folder in a profile's memory path, which holds none.
# a rules file is screened too; a source file is not
check "a profile memory path is screened" "2|2|0" "$(run "$(write "$PROFILE/grip.md" "The owner ruling 2026-10-01: grip stays.")")|$(run "$(write "$RULES/a.md" "The owner ruling 2026-10-01: grip stays.")")|$(run "$(write "$T/repo/src/a.ts" "// The owner ruling 2026-10-01: grip stays.")")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
