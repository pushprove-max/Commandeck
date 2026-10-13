#!/usr/bin/env bash
set -u
export COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1
ROOT=$(git rev-parse --show-toplevel); HOOK="$ROOT/hooks/pane-budget-gate.sh"; PASS=0; FAIL=0
check() { [ "$2" = "$3" ] && { PASS=$((PASS+1)); echo "ok   $1"; } || { FAIL=$((FAIL+1)); echo "FAIL $1"; }; }
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT; mkdir -p "$BOX/w/.claude/briefs" "$BOX/w/.claude/plans"; printf '{"context":10,"compactions":2}\n' > "$BOX/budget.json"; printf '{"transcript_path":"%s/log.jsonl","tool_name":"Edit"}\n' "$BOX" > "$BOX/input"; yes '{"type":"assistant"}' | head -3 > "$BOX/log.jsonl"
run() { CLAUDE_PROJECT_DIR="$BOX/w" PANE_BUDGET_CONFIG="$BOX/budget.json" "$HOOK" < "$BOX/input" 2>&1; }
OUT=$(run); RC=$?; check "over-budget edit blocks" 2 "$RC"; check "block names handoff" 0 "$(printf '%s' "$OUT" | grep -q 'w-handoff.md' && echo 0 || echo 1)"; check "block lists all four recovery options" 4 "$(printf '%s\n' "$OUT" | grep -oE 'simplify the unit|reset the pane|reassign to a fresh pane|escalate to a design pane' | wc -l)"; printf '## decisions\n## unresolved findings\n## current commit\n## test evidence\n' > "$BOX/w/.claude/briefs/w-handoff.md"; check "handoff permits edit" 0 "$(run >/dev/null; echo $?)"
rm "$BOX/w/.claude/briefs/w-handoff.md"
# Claude writes one transcript line per content block, so a reply that runs
# four tools is five lines; a turn is one message.id. The count is only
# reported now: no pane is refused for its turns.
{ echo '{"type":"assistant","message":{"id":"msg_1"}}'; yes '{"type":"assistant","message":{"id":"msg_2"}}' | head -4; } > "$BOX/log-blocks.jsonl"
printf '{"transcript_path":"%s/log-blocks.jsonl","tool_name":"Edit"}\n' "$BOX" > "$BOX/input-blocks"
check "one reply split over many lines is one turn in the block's summary" 1 "$(CLAUDE_PROJECT_DIR="$BOX/w" PANE_BUDGET_CONFIG="$BOX/budget.json" "$HOOK" < "$BOX/input-blocks" 2>&1 | grep -c 'turns=2 context=')"
# The shipped config has no compactions key (Codex rollouts carry no compaction
# event); a missing limit must not turn every Claude worker edit into a block.
printf '{"context":350000}\n' > "$BOX/budget-nocompact.json"
check "config with no compactions limit lets an under-budget edit through" 0 "$(CLAUDE_PROJECT_DIR="$BOX/w" PANE_BUDGET_CONFIG="$BOX/budget-nocompact.json" "$HOOK" < "$BOX/input" >/dev/null 2>&1; echo $?)"
printf '# Unit w\nPlan: `.claude/plans/measured.md`. Class:\nruntime.\n' > "$BOX/w/.claude/briefs/w.md"
printf '{"budget":{"runtime":{"turns":{"p90":99},"context":{"p90":10},"compactions":{"p90":2}}}}\n' > "$BOX/w/.claude/plans/measured.status.json"
printf '{"context":350000,"compactions":2}\n' > "$BOX/budget.json"
OUT=$(run); RC=$?; check "class threshold from status wins over fixed config" 2 "$RC"
# A plan's measured turns.p90 is a count plan-status.sh still writes; it
# refuses nobody, and neither does a turns key left in a config.
printf '{"budget":{"runtime":{"turns":{"p90":1},"context":{"p90":350000},"compactions":{"p90":2}}}}\n' > "$BOX/w/.claude/plans/measured.status.json"
check "a measured turns p90 below the pane's turns refuses nobody" 0 "$(run >/dev/null; echo $?)"
printf '{"turns":1,"context":350000,"compactions":2}\n' > "$BOX/budget-turns.json"
check "a turns key left in a config refuses nobody" 0 "$(CLAUDE_PROJECT_DIR="$BOX/w" PANE_BUDGET_PLAN=none PANE_BUDGET_CONFIG="$BOX/budget-turns.json" "$HOOK" < "$BOX/input" >/dev/null 2>&1; echo $?)"
# A measured p90 of zero compactions is a real budget: the first compaction is
# over it. Rejecting it fell back to the fixed config, which allows two.
printf '{"budget":{"runtime":{"turns":{"p90":99},"context":{"p90":350000},"compactions":{"p90":0}}}}\n' > "$BOX/w/.claude/plans/measured.status.json"
{ yes '{"type":"assistant"}' | head -3; echo '{"isCompactSummary":true}'; } > "$BOX/log-compact.jsonl"
printf '{"transcript_path":"%s/log-compact.jsonl","tool_name":"Edit"}\n' "$BOX" > "$BOX/input-compact"
check "a measured zero-compaction p90 blocks the first compaction" 2 "$(CLAUDE_PROJECT_DIR="$BOX/w" PANE_BUDGET_CONFIG="$BOX/budget.json" "$HOOK" < "$BOX/input-compact" >/dev/null 2>&1; echo $?)"
printf '{"budget":{"runtime":{"turns":{"p90":99},"context":{"p90":10},"compactions":{"p90":2}}}}\n' > "$BOX/w/.claude/plans/measured.status.json"
# The gate must let the handoff it demands be written, and must not count a
# main-checkout session (thousands of turns by design) against a worker budget.
printf '{"context":10,"compactions":2}\n' > "$BOX/budget.json"
printf '{"transcript_path":"%s/log.jsonl","tool_name":"Write","tool_input":{"file_path":"%s/w/.claude/briefs/w-handoff.md"}}\n' "$BOX" "$BOX" > "$BOX/input-handoff"
check "writing the missing handoff itself passes" 0 "$(CLAUDE_PROJECT_DIR="$BOX/w" PANE_BUDGET_CONFIG="$BOX/budget.json" "$HOOK" < "$BOX/input-handoff" >/dev/null 2>&1; echo $?)"
git init -q "$BOX/m" && git -C "$BOX/m" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && git -C "$BOX/m" worktree add -q "$BOX/lw" >/dev/null 2>&1
check "main checkout is exempt" 0 "$(CLAUDE_PROJECT_DIR="$BOX/m" PANE_BUDGET_CONFIG="$BOX/budget.json" "$HOOK" < "$BOX/input" >/dev/null 2>&1; echo $?)"
check "linked worktree is still gated" 2 "$(CLAUDE_PROJECT_DIR="$BOX/lw" PANE_BUDGET_CONFIG="$BOX/budget.json" "$HOOK" < "$BOX/input" >/dev/null 2>&1; echo $?)"
check "an inherited GIT_DIR cannot make a linked worktree look like main" 2 "$(GIT_DIR="$BOX/m/.git" CLAUDE_PROJECT_DIR="$BOX/lw" PANE_BUDGET_CONFIG="$BOX/budget.json" "$HOOK" < "$BOX/input" >/dev/null 2>&1; echo $?)"
# Edits made through Bash (sed -i, python heredocs) must hit the same budget.
printf '{"transcript_path":"%s/log.jsonl","tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ f"}}\n' "$BOX" > "$BOX/input-bash"
runbash() { CLAUDE_PROJECT_DIR="$BOX/w" PANE_BUDGET_CONFIG="$1" "$HOOK" < "$BOX/input-bash" 2>&1; }
rm -f "$BOX/w/.claude/briefs/w.md"
OUT=$(runbash "$BOX/budget.json"); RC=$?; check "over-budget bash blocks" 2 "$RC"; check "bash block names handoff" 0 "$(printf '%s' "$OUT" | grep -q 'w-handoff.md' && echo 0 || echo 1)"
check "under-budget bash passes" 0 "$(runbash "$BOX/budget-nocompact.json" >/dev/null; echo $?)"
printf '## decisions\n## unresolved findings\n## current commit\n## test evidence\n' > "$BOX/w/.claude/briefs/w-handoff.md"
check "handoff permits bash" 0 "$(runbash "$BOX/budget.json" >/dev/null; echo $?)"
rm "$BOX/w/.claude/briefs/w-handoff.md"
GATE_MATCHER=$(jq -r '[.hooks.PreToolUse[] | select(any(.hooks[]; .command | test("pane-budget-gate")))][0].matcher' "$ROOT/hooks/hooks.json")
check "settings wire the gate to Bash" 0 "$(jq -en --arg m "$GATE_MATCHER" '"Bash" | test("^(" + $m + ")$")' >/dev/null && echo 0 || echo 1)"
# A worker whose session has no serena server ran a whole
# cut on rg and sed (2026-09-18). The first tool call of a worker session, of
# any tool, checks for the server process under the session's claude
# process, refuses once when it is missing, and tells main once. Only where
# the project has serena.
check "settings run the gate on every tool, Read included" 0 "$(jq -en --arg m "$GATE_MATCHER" '"Read" | test("^(" + $m + ")$")' >/dev/null && echo 0 || echo 1)"
mkdir -p "$BOX/bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$ORCA_LOG"\n' > "$BOX/bin/orca-ide"; chmod +x "$BOX/bin/orca-ide"
# A stand-in for the claude process: it starts the named MCP servers as its
# children, then runs the hook as another. It runs under a copy of bash named
# claude, so its comm reads "claude" on Linux AND macOS, where a script's comm
# is its interpreter's.
cp "$(command -v bash)" "$BOX/claude"
cat > "$BOX/fake-claude.sh" <<'FAKE'
for s in "$@"; do case $s in
  serena) (exec -a "serena start-mcp-server" sleep 30) & ;;
  # The server one level further down, as a launcher's child.
  deep) bash -c '(exec -a "serena start-mcp-server" sleep 30) & wait' & ;;
  # The server two seconds after the session's first call started.
  late) (sleep 2; exec -a "serena start-mcp-server" sleep 30) & ;;
esac; done
sleep 0.3
"$HOOK" < "$IN" 2> "$ERR" >/dev/null; rc=$?
kill $(jobs -p) 2>/dev/null
exit $rc
FAKE
export ORCA_LOG="$BOX/orca.log" ERR="$BOX/err" HOOK COMMANDECK_RUN=run_t
first_call() { # session dir servers...
  jq -cn --arg sid "$1" --arg log "$BOX/log.jsonl" '{session_id:$sid, transcript_path:$log, tool_name:"Read", tool_input:{file_path:"/x"}}' > "$BOX/in-$1"
  local sid=$1 dir=$2; shift 2
  # No wait for a late server unless a case asks: every refusal would sit it out.
  IN="$BOX/in-$sid" CLAUDE_PROJECT_DIR="$dir" PANE_BUDGET_CONFIG="$BOX/budget-nocompact.json" PATH="$BOX/bin:$PATH" \
    COMMANDECK_MCP_WAIT=${WAIT:-0} "$BOX/claude" "$BOX/fake-claude.sh" "$@"; echo $?
}
S="mcp-$$-"; rm -f /tmp/claude-mcp-checked-"$S"*; : > "$ORCA_LOG"
check "worker with neither server: first call refused" 2 "$(first_call "${S}a" "$BOX/lw")"
check "the refusal names serena" 1 "$(grep -c 'serena is not running' "$ERR")"
# The first refusal asks the pane to make the call again and tells main
# nothing; the gate looks again on that call. Only the second refusal goes to
# main, and the call after it passes: main decides.
check "the first refusal asks for the same call again, not a wait for main" "1 0 0" \
  "$(grep -c 'Make the same call once more' "$ERR") $(grep -c "wait for main's answer" "$ERR") $(wc -l < "$ORCA_LOG" | tr -d ' ')"
check "the second call looks again and is refused" 2 "$(first_call "${S}a" "$BOX/lw")"
check "main is told once, as an escalation" 1 "$(grep -c -- '--type escalation' "$ORCA_LOG")"
check "the message names the unit" 1 "$(grep -c 'lw' "$ORCA_LOG")"
check "the second refusal says main was told" 1 "$(grep -c 'Main has been told' "$ERR")"
check "the next call of that session passes" 0 "$(first_call "${S}a" "$BOX/lw")"
check "and main is not told twice" 1 "$(wc -l < "$ORCA_LOG")"
check "worker with serena passes" 0 "$(first_call "${S}b" "$BOX/lw" serena)"
check "a project without serena is not checked" 0 "$(COMMANDECK_SERENA=0 first_call "${S}c" "$BOX/lw")"
# The claude pid the gate named was not the direct parent of the server.
check "a server that is a grandchild of the claude process: first call passes" 0 "$(first_call "${S}g" "$BOX/lw" deep)"
check "a server that appears after the session started: first call passes after the retry" 0 "$(WAIT=6 first_call "${S}h" "$BOX/lw" late)"
check "with no retry the same late server is refused" 2 "$(first_call "${S}i" "$BOX/lw" late)"
# The send's failure was swallowed, so the pane waited for an answer to a message main never got.
printf '#!/bin/sh\nexit 1\n' > "$BOX/bin/orca-ide"
first_call "${S}l" "$BOX/lw" >/dev/null
check "a failed send: the refusal does not claim main was told" "2 0 1" \
  "$(first_call "${S}l" "$BOX/lw") $(grep -c 'Main has been told' "$ERR") $(grep -c 'Main could NOT be told' "$ERR")"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$ORCA_LOG"\n' > "$BOX/bin/orca-ide"
: > "$ORCA_LOG"
check "the main checkout is exempt" 0 "$(first_call "${S}d" "$BOX/m")"
check "and tells main nothing" 0 "$(wc -l < "$ORCA_LOG")"
# The Chief-of-Staff relay pane denies the code server on purpose; only
# the exact directory name is exempt, so a look-alike worker stays gated.
git -C "$BOX/m" worktree add -q "$BOX/Chief-of-Staff" >/dev/null 2>&1; git -C "$BOX/m" worktree add -q "$BOX/Chief-of-Staff-x" >/dev/null 2>&1
check "Chief-of-Staff with neither server passes its first call" 0 "$(first_call "${S}e" "$BOX/Chief-of-Staff")"
check "and tells main nothing either" 0 "$(wc -l < "$ORCA_LOG")"
check "Chief-of-Staff-x with neither server is still refused" 2 "$(first_call "${S}f" "$BOX/Chief-of-Staff-x")"
rm -f /tmp/claude-mcp-checked-"$S"*

# No pane of any role is refused for its number of turns
# (owner ruling 2026-10-12). The shipped config is the one read.
mkdir -p "$BOX/r/.claude/briefs"
for n in 300 1200; do
  jq -cn --argjson n "$n" '{type:"assistant", message:{id:"m\(range($n))"}}' > "$BOX/log-$n.jsonl"
  printf '{"transcript_path":"%s/log-%s.jsonl","tool_name":"Edit"}\n' "$BOX" "$n" > "$BOX/input-$n"
done
role_run() { local n=$1; shift; env -u PANE_BUDGET_CONFIG -u COMMANDECK_ROUTING CLAUDE_PROJECT_DIR="$BOX/r" "$@" "$HOOK" < "$BOX/input-$n" >/dev/null 2>&1; echo $?; }
check "a pane 300 turns in is not refused" 0 "$(role_run 300)"
check "a pane 1200 turns in is not refused" 0 "$(role_run 1200)"
check "a design-coauthor pane 1200 turns in is not refused" 0 "$(role_run 1200 COMMANDECK_ROLE=design-coauthor)"
check "the shipped config carries no turn limit" null "$(jq -c '.turns' "$ROOT/config/pane-budget.json")"

# A handoff missing headings is refused ONCE, naming all of them with a ready
# skeleton, not one heading per refusal.
printf '## decisions\n' > "$BOX/w/.claude/briefs/w-handoff.md"
OUT=$(run); RC=$?
check "a handoff missing three headings still blocks" 2 "$RC"
check "one refusal names all three missing headings" 3 "$(printf '%s\n' "$OUT" | head -1 | grep -oE 'unresolved findings|current commit|test evidence' | wc -l | tr -d ' ')"
check "the refusal carries the full skeleton" 4 "$(printf '%s\n' "$OUT" | grep -cxE '## (decisions|unresolved findings|current commit|test evidence)')"
rm "$BOX/w/.claude/briefs/w-handoff.md"

echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
