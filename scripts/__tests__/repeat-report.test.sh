#!/usr/bin/env bash
# repeat-report.sh is what main reads at a checkpoint to pick the friction worth
# a fix. A wrong ORDER sends main after the wrong fix; a missed normalization
# splits one repeated command across worktree paths so it never tops the list;
# an empty section that prints nothing reads as a broken report, not a clean run.
set -uo pipefail

SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/repeat-report.XXXXXX")" && pwd -P)
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }

# This runner sets CLAUDE_CONFIG_DIR; the script must read the fake HOME's folder.
unset CLAUDE_CONFIG_DIR
export HOME=$T/home COMMANDECK_MAIN=$T/main COMMANDECK_WORKSPACES=$T/ws COMMANDECK_SCRATCH=$T/scratch COMMANDECK_RULING_LOG=$T/rulings.jsonl
PROJ=$HOME/.claude/projects/$(printf '%s' "$COMMANDECK_MAIN" | tr -c 'A-Za-z0-9' '-')
mkdir -p "$PROJ" "$COMMANDECK_SCRATCH"
run() { bash "$SOURCE/scripts/repeat-report.sh" "$@"; }

# 1. No traces at all: every section says "none".
OUT=$(run); RC=$?
# An empty section that prints nothing reads as a broken report.
check "an empty run exits 0" 0 "$RC"
check "an empty run prints none in all 4 sections" 4 "$(grep -c '^  none$' <<< "$OUT")"

NOW=$(date -u +%FT%TZ)
tool() { jq -cn --arg ts "$NOW" --arg n "$1" --arg k "$2" --arg v "$3" \
  '{type:"assistant", timestamp:$ts, message:{content:[{type:"tool_use", name:$n, input:{($k):$v}}]}}'; }
{
  # Four worktrees, one command: only normalization makes it the top one.
  for w in w1 w2 w3 w4; do tool Bash command "git -C /tmp/$w status"; done
  for i in 1 2 3; do tool Bash command "npm run lint"; done
  tool Bash command "ls"
  # Two scripts under one directory stay two rows, whatever their tail count.
  tool Bash command "bash .claude/scripts/a.sh | tail -30"; tool Bash command "bash .claude/scripts/a.sh | tail -8"
  tool Bash command "bash .claude/scripts/b.sh"; tool Bash command "bash .claude/scripts/b.sh"
  tool Read file_path /repo/a.md; tool Read file_path /repo/a.md
  tool Bash command "sed -n 1,20p /repo/a.md"
  tool Read file_path /repo/b.md; tool Bash command "cat /repo/b.md | wc -l"
  tool Read file_path /repo/once.md
  # One file read from main and from a worktree.
  tool Read file_path "$COMMANDECK_MAIN/docs/x.md"; tool Read file_path "$COMMANDECK_WORKSPACES/u1/docs/x.md"
} > "$PROJ/s1.jsonl"
# The block is a user-turn tool_result, echoed in toolUseResult; the plugin names a hook by its run-hook.sh argument.
block() { local e="$2 hook error: [\"\${CLAUDE_PLUGIN_ROOT}\"/hooks/run-hook.sh hooks/$3]: BLOCKED: $4"
  jq -cn --arg ts "$1" --arg e "$e" '{type:"user", timestamp:$ts, toolUseResult:("Error: " + $e),
    message:{role:"user", content:[{type:"tool_result", content:$e, is_error:true, tool_use_id:"t"}]}}'; }
{
  # Each hook blocks a different tool, so reading the tool instead of the hook name fails the block checks.
  for i in 1 2 3; do block "$NOW" PreToolUse:Bash bash-guardrails.sh "rg over an unbounded path. Name a directory.
Try: rg x src"; done
  block "$NOW" PreToolUse:Read symbols-before-read.sh "call serena first"
  block 2000-01-01T00:00:00Z PreToolUse:Bash old.sh "outside the window"
} > "$PROJ/s2.jsonl"
{
  # A damaged line between the two asks must not hide the second.
  for q in "Ship it now?" "ship it NOW?" "Other question?"; do jq -cn --arg u "$NOW" --arg q "$q" '{utc:$u, source:"ask", question:$q}'; echo '{"utc":"half a row{"'; done
  jq -cn --arg u "$NOW" '{utc:$u, source:"prompt", question:null, answer:"go"}'
} > "$COMMANDECK_RULING_LOG"

OUT=$(run); RC=$?
check "a run over traces exits 0" 0 "$RC"
section() { awk -v h="$1" '$0 == h { on = 1; next } /^[^ ]/ { on = 0 } on' <<< "$OUT"; }

# 2. Blocks: counted and ordered, the out-of-window row dropped.
B=$(section "hook blocks")
# A block counted under the wrong hook name sends main after the wrong fix.
check "the top block is bash-guardrails x3, reason cut at the first sentence" "  3 bash-guardrails.sh: rg over an unbounded path." "$(sed -n 1p <<< "$B")"
check "the second block is symbols-before-read" "  1 symbols-before-read.sh: call serena first" "$(sed -n 2p <<< "$B")"
# An old row counted, or toolUseResult counted twice, inflates the list.
check "two block rows: the old row dropped, toolUseResult not double-counted" 2 "$(wc -l <<< "$B" | tr -d ' ')"

# 3. Commands: the raw top is "npm run lint" (3); normalized, the git command (4) wins.
RAW_TOP=$(jq -r '.message.content[0] | select(.name == "Bash") | .input.command' "$PROJ/s1.jsonl" | sort | uniq -c | sort -rn | sed -n '1s/^ *[0-9]* //p')
# Without this the normalization checks could pass on a fixture that never needed normalizing.
check "the fixture's raw top command is npm run lint" "npm run lint" "$RAW_TOP"
C=$(section "repeated bash commands")
# A missed path normalization splits one command across worktrees.
check "the normalized top command is the git status x4" "  4 git -C <path> status" "$(sed -n 1p <<< "$C")"
check "the second command is npm run lint x3" "  3 npm run lint" "$(sed -n 2p <<< "$C")"
# A command run once listed as repeated pads the report.
check "a command run once is not repeated" 0 "$(grep -c ' ls$' <<< "$C")"
# A different tail count must not split one command.
check "tail counts merge" 1 "$(grep -cx '  2 bash .claude/scripts/a.sh | tail -N' <<< "$C")"
# Collapsing a relative script path merged every script into one row.
check "a relative script path stays distinct" 1 "$(grep -cx '  2 bash .claude/scripts/b.sh' <<< "$C")"

# 4. Re-reads: Read and sed/cat of one path count together; a single read is not listed.
R=$(section "re-read files")
# Read and sed of one file counted apart hide the re-read.
check "the top re-read is a.md x3 (Read twice, sed once)" "  3 /repo/a.md" "$(sed -n 1p <<< "$R")"
check "cat through a pipe counts" "  2 /repo/b.md" "$(sed -n 2p <<< "$R")"
check "a file read once is not re-read" 0 "$(grep -c once.md <<< "$R")"
# The same file from main and from a worktree is one file.
check "main and worktree copies of one file count together" 1 "$(grep -cx '  2 docs/x.md' <<< "$R")"

# 5. Rulings: only asked questions, case-folded, more than once.
Q=$(section "ruling topics asked more than once")
check "ruling topics: only asked questions, case-folded, twice" "  2 ship it now?" "$Q"

# 6. D42: the default log is the file hooks/ruling-log.sh writes, named for the project.
# A hardcoded log name would read nothing for every project but one.
unset COMMANDECK_RULING_LOG
mkdir -p "$T/myproj" "$HOME/.claude/rulings"
git init -q "$T/myproj"
jq -cn --arg u "$NOW" '{utc:$u, source:"ask", question:"Project log question?"}' > "$HOME/.claude/rulings/myproj.jsonl"
cp "$HOME/.claude/rulings/myproj.jsonl" "$T/dup.jsonl"; cat "$T/dup.jsonl" >> "$HOME/.claude/rulings/myproj.jsonl"
OUT=$(cd "$T/myproj" && run)
check "an unset log path reads the project's log" "  2 project log question?" "$(section "ruling topics asked more than once")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
