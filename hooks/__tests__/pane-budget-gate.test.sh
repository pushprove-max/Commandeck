#!/usr/bin/env bash
set -u
export COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1
ROOT=$(git rev-parse --show-toplevel); HOOK="$ROOT/hooks/pane-budget-gate.sh"; PASS=0; FAIL=0
check() { [ "$2" = "$3" ] && { PASS=$((PASS+1)); echo "ok   $1"; } || { FAIL=$((FAIL+1)); echo "FAIL $1"; }; }
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT; mkdir -p "$BOX/w/.claude/briefs" "$BOX/w/.claude/plans"; printf '{"context":10,"compactions":2}\n' > "$BOX/budget.json"; printf '{"transcript_path":"%s/log.jsonl","tool_name":"Edit"}\n' "$BOX" > "$BOX/input"; yes '{"type":"assistant"}' | head -3 > "$BOX/log.jsonl"
run() { CLAUDE_PROJECT_DIR="$BOX/w" PANE_BUDGET_CONFIG="$BOX/budget.json" "$HOOK" < "$BOX/input" 2>&1; }
OUT=$(run); RC=$?; check "over-budget edit blocks" 2 "$RC"; check "block names handoff" 0 "$(printf '%s' "$OUT" | grep -q 'w-handoff.md' && echo 0 || echo 1)"; check "block lists all four recovery options" 4 "$(printf '%s\n' "$OUT" | grep -oE 'simplify the unit|reset the pane|reassign to a fresh pane|escalate to main' | wc -l)"; printf '## decisions\n## unresolved findings\n## current commit\n## test evidence\n' > "$BOX/w/.claude/briefs/w-handoff.md"; check "handoff permits edit" 0 "$(run >/dev/null; echo $?)"
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
# A file named orca-refuse makes the send fail, as an Orca that refuses it does.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$ORCA_LOG"\n[ ! -e "%s/orca-refuse" ] || exit 1\n' "$BOX" > "$BOX/bin/orca-ide"; chmod +x "$BOX/bin/orca-ide"
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
export ORCA_LOG="$BOX/orca.log" ERR="$BOX/err" HOOK COMMANDECK_RUN=run_t COMMANDECK_SCRATCH="$BOX/sc"
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
# Issue 331: the missing-server escalation Orca takes writes one sent line; one Orca refuses writes one refused line.
WLJ=$BOX/sc/wake-log.jsonl
logged() { jq -rs 'map("\(.from):\(.to):\(.result)") | join(",")' "$WLJ" 2>/dev/null; }
# The first refusal tells nobody: the gate looks again on the same call repeated, and tells main on that second look.
rm -f "$WLJ"; first_call "${S}c" "$BOX/lw" >/dev/null; first_call "${S}c" "$BOX/lw" >/dev/null
check "the escalation Orca accepts writes one sent line to main's run" "pane-budget-gate:run:run_t:sent" "$(logged)"
rm -f "$WLJ" /tmp/claude-mcp-checked-"$S"*; touch "$BOX/orca-refuse"; first_call "${S}d" "$BOX/lw" >/dev/null; first_call "${S}d" "$BOX/lw" >/dev/null; rm -f "$BOX/orca-refuse"
check "and one it refuses writes one refused line" "pane-budget-gate:run:run_t:refused" "$(logged)"
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

# Issue 275: past the clear line main may only write its checkpoint and end the turn, so it restarts instead of
# compacting. context-line.sh leaves the marker; the gate reads it for main only, before the strict-tier exit.
H=$BOX/home; mkdir -p "$H/.claude/checkpoints"; CPF=$H/.claude/checkpoints/msid.md
printf '%s\n' '{"message":{"usage":{"cache_read_input_tokens":500,"input_tokens":1}}}' > "$BOX/main-log.jsonl"
line_hook() { (cd "$BOX/m" && jq -cn --arg t "$BOX/main-log.jsonl" '{session_id:"msid", transcript_path:$t, prompt:"go"}' \
  | HOME=$H COMMANDECK_CLEAR_LINE=$1 bash "$ROOT/hooks/context-line.sh" >/dev/null 2>&1); }
line_hook 1000
check "under the line context-line.sh leaves no marker" no "$([ -e "$H/.claude/checkpoints/msid.past-line" ] && echo yes || echo no)"
line_hook 10
check "past the line it leaves the marker" yes "$([ -e "$H/.claude/checkpoints/msid.past-line" ] && echo yes || echo no)"
gate() { # dir tool input-json -> exit code
  jq -cn --arg tool "$2" --argjson in "$3" '{session_id:"msid", tool_name:$tool, tool_input:$in}' \
    | HOME=$H CLAUDE_PROJECT_DIR=$1 COMMANDECK_HOOK_TIER=default "$HOOK" >/dev/null 2>"$BOX/gate.err"; echo $?; }
check "main past the line: a Bash call is refused" 2 "$(gate "$BOX/m" Bash '{"command":"git status"}')"
check "the refusal says write the checkpoint, then end the turn" 1 "$(grep -c "write the checkpoint $CPF.*then end the turn" "$BOX/gate.err")"
check "an Edit of another file is refused" 2 "$(gate "$BOX/m" Edit '{"file_path":"/x/other.md"}')"
check "the checkpoint Write is allowed" 0 "$(gate "$BOX/m" Write "$(jq -cn --arg f "$CPF" '{file_path:$f}')")"
check "a Read of the checkpoint template is allowed" 0 "$(gate "$BOX/m" Read "$(jq -cn --arg f "$ROOT/templates/checkpoint.md" '{file_path:$f}')")"
check "a Read of the checkpoint it resumed from is allowed" 0 \
  "$(echo "$H/.claude/checkpoints/old.md" > "$H/.claude/checkpoints/msid.resumed-from"; gate "$BOX/m" Read "$(jq -cn --arg f "$H/.claude/checkpoints/old.md" '{file_path:$f}')")"
check "state-snapshot.sh --out is allowed" 0 "$(gate "$BOX/m" Bash "$(jq -cn --arg c "bash $ROOT/scripts/state-snapshot.sh --out $CPF --force" '{command:$c}')")"
check "checkpoint-context.py carry is allowed" 0 "$(gate "$BOX/m" Bash "$(jq -cn --arg c "python3 $ROOT/scripts/checkpoint-context.py carry ~/a.md ~/b.md" '{command:$c}')")"
check "state-snapshot.sh --out with the checkpoint written ~/... is allowed" 0 "$(gate "$BOX/m" Bash "$(jq -cn --arg c "bash $ROOT/scripts/state-snapshot.sh --out ~/.claude/checkpoints/msid.md" '{command:$c}')")"
# The allowed command is read word by word, so allowed text elsewhere in a command lets nothing through: another
# program, another copy of the script, another interpreter, another operation or argument count, another --out
# file, an env prefix, a quote or a glob.
for c in "python3 -c print(123) checkpoint-context.py carry a b" "python3 -c 'print(123)' $ROOT/scripts/checkpoint-context.py carry a b" \
  "python3 /p/scripts/checkpoint-context.py carry a b" "bash $ROOT/scripts/checkpoint-context.py carry a b" \
  "python3 $ROOT/scripts/checkpoint-context.py dedupe a" "python3 $ROOT/scripts/checkpoint-context.py carry a b c" \
  "python3 $ROOT/scripts/checkpoint-context.py carry -x b" "bash $ROOT/scripts/state-snapshot.sh --out /tmp/other.md" \
  "bash $ROOT/scripts/state-snapshot.sh --out $CPF --force x" "env X=1 python3 $ROOT/scripts/checkpoint-context.py carry a b" \
  "python3 $ROOT/scripts/checkpoint-context.py carry a *" "python3 $ROOT/scripts/checkpoint-context.py carry a {b,c}" \
  "python3 -X importtime $ROOT/scripts/checkpoint-context.py carry a b" ""; do
  check "past the line, refused: ${c:-an empty command}" 2 "$(gate "$BOX/m" Bash "$(jq -cn --arg c "$c" '{command:$c}')")"
done
check "an allowed command chained to another is refused" "2 2 2" \
  "$(gate "$BOX/m" Bash '{"command":"python3 /p/scripts/checkpoint-context.py carry a b; rm -rf x"}') $(gate "$BOX/m" Bash '{"command":"python3 /p/scripts/checkpoint-context.py carry a b\nrm -rf x"}') $(gate "$BOX/m" Bash '{"command":"python3 /p/scripts/checkpoint-context.py carry a $(rm -rf x)"}')"
check "the task-list tools are allowed" 0 "$(gate "$BOX/m" TaskUpdate '{"taskId":"1","status":"completed"}')"
check "a worker pane with the marker is never refused" 0 "$(gate "$BOX/lw" Bash '{"command":"git status"}')"
check "a reviewer is never refused" 0 "$(COMMANDECK_REVIEWER=1 gate "$BOX/m" Bash '{"command":"git status"}')"
rm "$H/.claude/checkpoints/msid.past-line"
check "below the line nothing is refused" 0 "$(gate "$BOX/m" Bash '{"command":"git status"}')"
# The marker outlives a compaction (or a restart that never came): tools stayed blocked while the Stop hook would not
# restart below the line. The gate reads the context now, so a stale marker, however it got there, is cleared.
usage() { printf '{"message":{"usage":{"cache_read_input_tokens":%s,"input_tokens":1}}}\n' "$1" > "$BOX/main-log.jsonl"; }
tgate() { # dir tool input-json -> exit code, with the session's transcript
  jq -cn --arg tool "$2" --argjson in "$3" --arg t "$BOX/main-log.jsonl" '{session_id:"msid", transcript_path:$t, tool_name:$tool, tool_input:$in}' \
    | HOME=$H CLAUDE_PROJECT_DIR=$1 COMMANDECK_HOOK_TIER=default "$HOOK" >/dev/null 2>"$BOX/gate.err"; echo $?; }
usage 40000
for tick in 1 2; do
  : > "$H/.claude/checkpoints/msid.past-line"
  check "tick $tick: a marker left from before a compaction to 40K: git status passes and the marker is cleared" "0 no" \
    "$(cd "$BOX/m" && tgate "$BOX/m" Bash '{"command":"git status"}') $([ -e "$H/.claude/checkpoints/msid.past-line" ] && echo yes || echo no)"
done
: > "$H/.claude/checkpoints/msid.past-line"
check "a marker with no transcript to read still refuses" 2 "$(gate "$BOX/m" Bash '{"command":"git status"}')"
usage 250000
check "a marker still past the line still refuses" 2 "$(cd "$BOX/m" && tgate "$BOX/m" Bash '{"command":"git status"}')"
rm -f "$H/.claude/checkpoints/msid.past-line"
# A first-run HOME has no checkpoints folder: the marker write failed silently and the gate let everything through.
prompt_hook() { (cd "$BOX/m" && jq -cn --arg t "$BOX/main-log.jsonl" '{session_id:"msid", transcript_path:$t, prompt:"go"}' \
  | HOME=$H bash "$ROOT/hooks/context-line.sh" 2>&1); }
H=$BOX/home2; mkdir -p "$H" "$BOX/m/.claude"; usage 141001; printf '{"standardContext": true}\n' > "$BOX/m/.claude/commandeck.json"
prompt_hook >/dev/null
check "no checkpoints folder, standard context at 141001: the marker is written and git status is refused" "yes 2" \
  "$([ -e "$H/.claude/checkpoints/msid.past-line" ] && echo yes || echo no) $(cd "$BOX/m" && tgate "$BOX/m" Bash '{"command":"git status"}')"
# A marker that cannot be written at all is said, never silent: the gate cannot hold the session then.
H=$BOX/home3; mkdir -p "$H/.claude"; : > "$H/.claude/checkpoints"
check "a marker write that fails says so" 1 "$(prompt_hook | grep -c 'marker NOT written')"
rm -f "$BOX/m/.claude/commandeck.json"

echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
