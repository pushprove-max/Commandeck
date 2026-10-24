#!/usr/bin/env bash
# covers: scripts/context-overhead.sh
# context-overhead.test.sh -- issue 327: main's context grows by what the harness attaches around it, and Bash hook
# output was the largest share a plugin can control. context-overhead.sh replays one scripted main session through the
# plugin's hooks and counts the bytes that reach the model. Pinned: the session attaches less than it did at 3537ac2;
# a Bash call with nothing to act on attaches nothing from any hook hooks.json wires (a new Bash hook is covered by
# the loop in the script); the measurement itself counts a hook that talks; and a hook still prints when one applies.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT

# The total at 3537ac2, measured the same way: `git worktree add <dir> 3537ac2; bash scripts/context-overhead.sh <dir>`
# (the batching nag repeated every third lone look: 8 nudges in this session). CI has no base worktree to measure.
BASE_TOTAL=16417
bash "$REAL/scripts/context-overhead.sh" "$REAL" > "$T/session" 2>&1
TIP=$(sed -n 's/^total //p' "$T/session")
check "the scripted main session attaches less than at 3537ac2" yes "$([ "${TIP:-$BASE_TOTAL}" -lt "$BASE_TOTAL" ] && echo yes)"
check "each hook still prints when one applies: the first streak of lone looks nudges, once, and the startup context prints" "1:1" \
  "$(grep -c '^[0-9]* PostToolUse Read batch-independent-looks.sh$' "$T/session"):$(grep -c '^[0-9]* SessionStart - agent-startup-context.sh$' "$T/session")"
check "the batching nudge is said once in the whole session, not again for the Bash calls after the Reads" 0 \
  "$(grep -c 'PostToolUse Bash batch-independent-looks.sh' "$T/session")"

check "every Bash hook in hooks.json given a call with nothing to act on attaches 0 bytes" "total 0" \
  "$(bash "$REAL/scripts/context-overhead.sh" "$REAL" --one-bash 'git status' 2>&1)"

# The measurement counts a hook that talks on every Bash call, so the case above can fail.
mkdir -p "$T/fake/hooks"
cat > "$T/fake/hooks/hooks.json" <<'EOF'
{"hooks": {"PostToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/talk.sh\""}]}]}}
EOF
printf '#!/usr/bin/env bash\ncat >/dev/null; echo "{\\"hookSpecificOutput\\":{\\"hookEventName\\":\\"PostToolUse\\",\\"additionalContext\\":\\"twelve bytes\\"}}"\n' > "$T/fake/hooks/talk.sh"
check "a Bash hook that prints on a call with nothing to act on is counted" "12 PostToolUse Bash talk.sh:total 12" \
  "$(bash "$REAL/scripts/context-overhead.sh" "$T/fake" --one-bash 'git status' 2>&1 | paste -sd: -)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
