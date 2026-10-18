#!/usr/bin/env bash
set -u
export COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1
ROOT=$(git rev-parse --show-toplevel); HOOK="$ROOT/hooks/pane-budget-gate.sh"; PASS=0; FAIL=0
check() { [ "$2" = "$3" ] && { PASS=$((PASS+1)); echo "ok   $1"; } || { FAIL=$((FAIL+1)); echo "FAIL $1"; }; }
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT; mkdir -p "$BOX/w/.claude/briefs" "$BOX/w/.claude/plans"; printf '{"context":10,"compactions":2}\n' > "$BOX/budget.json"; printf '{"transcript_path":"%s/log.jsonl","tool_name":"Edit"}\n' "$BOX" > "$BOX/input"; yes '{"type":"assistant"}' | head -3 > "$BOX/log.jsonl"
run() { CLAUDE_PROJECT_DIR="$BOX/w" PANE_BUDGET_CONFIG="$BOX/budget.json" "$HOOK" < "$BOX/input" 2>&1; }
OUT=$(run); RC=$?; check "over-budget edit blocks" 2 "$RC"; check "block names handoff" 0 "$(printf '%s' "$OUT" | grep -q 'w-handoff.md' && echo 0 || echo 1)"; check "block lists all four recovery options" 4 "$(printf '%s\n' "$OUT" | grep -oE 'simplify the unit|reset the pane|reassign to a fresh pane|escalate to a design pane' | wc -l)"; printf '## decisions\n## unresolved findings\n## current commit\n## test evidence\n' > "$BOX/w/.claude/briefs/w-handoff.md"; check "handoff permits edit" 0 "$(run >/dev/null; echo $?)"
rm "$BOX/w/.claude/briefs/w-handoff.md"
# The shipped config has no compactions key (Codex rollouts carry no compaction
# event); a missing limit must not turn every Claude worker edit into a block.
printf '{"context":350000}\n' > "$BOX/budget-nocompact.json"
check "config with no compactions limit lets an under-budget edit through" 0 "$(CLAUDE_PROJECT_DIR="$BOX/w" PANE_BUDGET_CONFIG="$BOX/budget-nocompact.json" "$HOOK" < "$BOX/input" >/dev/null 2>&1; echo $?)"
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
# A limit that is not a whole number admits nothing: a null context, a text compactions value and a missing file all block.
printf '{"context":null}\n' > "$BOX/budget-null.json"; printf '{"context":99999999,"compactions":"x"}\n' > "$BOX/budget-text.json"
check "a null context limit blocks" 2 "$(runbash "$BOX/budget-null.json" >/dev/null; echo $?)"
check "a non-numeric compactions limit blocks" 2 "$(runbash "$BOX/budget-text.json" >/dev/null; echo $?)"
check "a missing config blocks" 2 "$(runbash "$BOX/none.json" >/dev/null; echo $?)"
# The turn count is a pass over the whole transcript on every Edit, Write and Bash: a within-budget call skips it
# (the sort it ends in leaves a marker), an over-budget one still names turns= in its message.
mkdir -p "$BOX/shim"; printf '#!/bin/sh\ntouch "%s/sorted"\nexec /usr/bin/sort "$@"\n' "$BOX" > "$BOX/shim/sort"; chmod +x "$BOX/shim/sort"
rm -f "$BOX/sorted"; PATH="$BOX/shim:$PATH" runbash "$BOX/budget-nocompact.json" >/dev/null
check "a within-budget call does not count the turns" 1 "$([ -e "$BOX/sorted" ]; echo $?)"
check "an over-budget message still names the turns" 1 "$(PATH="$BOX/shim:$PATH" runbash "$BOX/budget.json" | grep -c 'turns=3 ')"
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
check "worker with serena passes" 0 "$(first_call "${S}b" "$BOX/lw" serena)"
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

echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
