#!/usr/bin/env bash
# Self-test for batch-independent-looks.sh: which Bash calls count as a look. The commands are read with their
# quoted text set aside (issue 213): a `|`, `;` or `>` inside a quoted pattern is data, so `rg -n "foo|bar"`, echo
# separators and `for` loops are looks. A real redirect and a command substitution, even inside double quotes, are
# not, and a quote inside the other kind of quote never hides the command between. Three turns per case, on a
# fresh session; a planner seat, which hears the nudge in every tier.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/batch-independent-looks.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
export BATCH_SIBLING_MS=200 BATCH_STREAK_THRESHOLD=3 COMMANDECK_SEAT=plan-author; unset COMMANDECK_BUILDER
# Each case runs in a subshell, so the sessions are cleaned up by their shared prefix.
trap 'rm -f /tmp/claude-batch-bil$$-*' EXIT
fresh() { S="bil$$-$RANDOM$RANDOM"; }
# turn <command> -- one call of a new turn (a gap past the sibling window): nudge, quiet, or rc=<n>
turn() {
  local out rc; sleep 0.3
  out=$(jq -cn --arg s "$S" --arg c "$1" '{session_id: $s, tool_name: "Bash", tool_input: {command: $c}}' | bash "$HOOK" 2>/dev/null); rc=$?
  [ "$rc" = 0 ] || { echo "rc=$rc"; return; }
  case "$out" in *BATCHING:*) echo nudge ;; *) echo quiet ;; esac
}
looks3() { fresh; turn "$1" >/dev/null; turn "$1" >/dev/null; turn "$1"; }
two_then() { fresh; turn 'ls' >/dev/null; turn 'ls' >/dev/null; echo "$(turn "$1")/$(turn 'ls')"; }

check "a quoted | and => with echo separators are looks" nudge \
  "$(looks3 $'rg -n "foo|bar" a.ts | head -5; echo ---; sed -n \'1,5p\' b.ts | rg \'=>\'')"
check "a for loop of gh issue view is a look" nudge "$(looks3 'for n in 1 2; do gh issue view $n; done')"
check "git rev-parse and ls-files are looks" nudge "$(looks3 'git rev-parse HEAD; git ls-files templates')"
check "a real redirect resets the streak, and the next look starts from one" quiet/quiet "$(two_then 'rg -n "a|b" f > out.txt')"
check "a command substitution inside double quotes is not a look" quiet/quiet "$(two_then 'echo "$(touch x)"')"
check "a quote inside the other kind of quote hides no command" quiet/quiet "$(two_then "echo \"'\"; touch out.txt; echo \"'\"")"

# Issue 247: a Builder pays for every lone look across a whole build, so it hears the nudge at its second; a planner
# keeps three. Both hear it in every tier.
check "a Builder is nudged at its second lone look" quiet/nudge \
  "$(export -n BATCH_STREAK_THRESHOLD; export COMMANDECK_BUILDER=1 COMMANDECK_SEAT=; fresh; echo "$(turn ls)/$(turn ls)")"
check "a planner is not nudged at its second, and is at its third" quiet/quiet/nudge \
  "$(export -n BATCH_STREAK_THRESHOLD; fresh; echo "$(turn ls)/$(turn ls)/$(turn ls)")"

# Issue 249: the nudging call waited a fixed sibling window (1.5 s) even when the sibling landed at once. It polls:
# a sibling written 200 ms in ends the wait by 400 ms, and the batched turn is not nudged.
TR=$(mktemp); trap 'rm -f /tmp/claude-batch-bil$$-* "$TR"' EXIT
msg() { jq -cn --arg u "$1" '{type: "assistant", message: {id: "m1", content: [{type: "tool_use", id: $u}]}}'; }
sibling_wait() {
  fresh; turn ls >/dev/null; turn ls >/dev/null; sleep 0.3
  msg u1 > "$TR"; ( sleep 0.2; msg u2 >> "$TR" ) &
  local t0 out; t0=$(date +%s%3N)
  out=$(jq -cn --arg s "$S" --arg t "$TR" '{session_id: $s, tool_name: "Bash", tool_input: {command: "ls"},
    transcript_path: $t, tool_use_id: "u1"}' | BATCH_SIBLING_MS=1500 bash "$HOOK" 2>/dev/null)
  wait
  case "$out" in *BATCHING:*) printf nudge ;; *) printf quiet ;; esac
  [ $(( $(date +%s%3N) - t0 )) -lt 400 ] && echo " by-400ms" || echo " slow"
}
check "a sibling landing 200 ms in ends the wait by 400 ms, with no nudge" "quiet by-400ms" "$(sibling_wait)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
