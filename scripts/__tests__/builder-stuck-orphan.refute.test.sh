#!/usr/bin/env bash
# A call denied before it runs (another hook's block, the auto-mode classifier)
# logs a tool-start and never an end. On 2026-10-12 that flagged a working
# Builder STUCK for the rest of its log and had it nudged and escalated.
# Only the batch's own end row may close such a call: later calls prove nothing.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
B=1791764428
ts() { jq -rn --argjson t "$1" '$t | todate'; }
# start <epoch> <use> <kind>; end <epoch> <use>; batch <epoch> <use>...
start() { printf '{"ts":"%s","event":"tool-start","use":"%s","tool":"Bash","kind":"%s","call":"%s"}\n' "$(ts "$1")" "$2" "$3" "$2"; }
end() { printf '{"ts":"%s","event":"tool-end","use":"%s","ok":true}\n' "$(ts "$1")" "$2"; }
batch() { local at=$1; shift; jq -cn --arg ts "$(ts "$at")" '{ts: $ts, event: "batch-end", uses: $ARGS.positional}' --args "$@"; }
# signals <now> -- "kind:since" of each signal, sorted, from the rows on stdin
signals() { jq -s --argjson now "$1" -f "$ROOT/scripts/dashboard_builders.jq" | jq -r '[.signals[] | "\(.kind):\(.since)"] | sort | join(" ")'; }

# The log shape of the issue: a denied call (a) beside one that ran (b), then the pane works on.
orphan() { start "$B" a shell; start $((B + 4)) b shell; end $((B + 5)) b; batch $((B + 5)) a b; start $((B + 10)) c shell; end $((B + 60)) c; batch $((B + 60)) c; }
got=$(orphan | signals $((B + 200)))
[ "$got" = "" ] || fail "a denied call whose batch ended reads as: $got"
# QUIET reads the same rows: the denied call must not count as an open call for good.
got=$(orphan | signals $((B + 400)))
[ "$got" = "quiet:$((B + 60))" ] || fail "a pane silent for 340 s after a denied call reads as: '$got'"

got=$(start "$B" a shell | signals $((B + 200)))
[ "$got" = "stuck:$B" ] || fail "a lone call open past its limit reads as: '$got'"

got=$({ start "$B" a shell; start "$B" b shell; end $((B + 5)) b; } | signals $((B + 200)))
[ "$got" = "stuck:$B" ] || fail "one of two parallel calls left open reads as: '$got'"

# Parallel calls can start one after another, so later starts and ends do not show the first is over.
got=$({ start "$B" a shell; start $((B + 4)) b shell; end $((B + 5)) b; start $((B + 10)) c shell; end $((B + 60)) c; } | signals $((B + 200)))
[ "$got" = "stuck:$B" ] || fail "a call open while later calls of its batch start and end reads as: '$got'"

# A subagent's finished batch says nothing about the pane's open call.
got=$({ start "$B" a shell; start $((B + 4)) x1 tool; end $((B + 5)) x1; batch $((B + 5)) x1; start $((B + 10)) x2 tool; end $((B + 190)) x2; batch $((B + 190)) x2; } | signals $((B + 200)))
[ "$got" = "stuck:$B" ] || fail "a main call open while a subagent logs rows reads as: '$got'"

# The hook: what it classes as a test run, and the end rows of a batch and of a denied call.
export CLAUDE_PROJECT_DIR="$T" COMMANDECK_HOOK_FIRE_LOG="$T/hook-fire.jsonl"
LOG=$T/.claude/builder-events.jsonl
hook() { jq -cn --arg e "$1" --arg u "$2" --arg c "$3" --argjson x "${4:-{\}}" \
  '{hook_event_name: $e, session_id: "00000000-0000-4000-8000-000000000002", tool_name: "Bash", tool_use_id: $u, tool_input: {command: $c}} + $x' \
  | bash "$ROOT/hooks/builder-event-log.sh"; }
kind() { hook PreToolUse k "$1"; jq -r 'select(.use == "k") | .kind' "$LOG" | tail -1; }
for c in 'timeout 360 bash scripts/__tests__/main-watch-*.refute.test.sh' \
         'bash scripts/__tests__/builder.test.sh > /tmp/b.out 2>&1; echo rc=$?' \
         'cd /tmp && timeout -k 5 90s ./slow-build'; do
  [ "$(kind "$c")" = test ] || fail "'$c' is classed $(kind "$c"), so a healthy test run gets the 180 s shell limit"
done
for c in 'ls -la' 'wc -l scripts/__tests__/builder.test.sh'; do
  [ "$(kind "$c")" = shell ] || fail "'$c' is classed $(kind "$c"), not shell"
done
# The batch-end payload as Claude Code 2.1.296 sends it: every call of the batch, a blocked one included.
: > "$LOG"
hook PreToolUse d1 'echo one'; hook PreToolUse d2 'echo two'; hook PostToolUse d1 'echo one'
jq -cn '{hook_event_name: "PostToolBatch", session_id: "00000000-0000-4000-8000-000000000002",
  tool_calls: [{tool_name: "Bash", tool_use_id: "d1", tool_response: "one"}, {tool_name: "Bash", tool_use_id: "d2", tool_response: "PreToolUse:Bash hook error"}]}' \
  | bash "$ROOT/hooks/builder-event-log.sh"
[ "$(jq -c 'select(.event == "batch-end") | .uses' "$LOG")" = '["d1","d2"]' ] || fail "the batch-end row does not name the batch's calls: $(tail -1 "$LOG")"
NOW=$(jq -rs '(.[0].ts | fromdateiso8601) + 1900' "$LOG")
got=$(signals "$NOW" < "$LOG")
[ "${got%%:*}" = quiet ] || fail "a call blocked in a finished batch reads as: '$got'"
# The classifier's denial has its own event, in case no batch row follows it.
: > "$LOG"
hook PreToolUse p1 'ls'; hook PermissionDenied p1 'ls' '{"reason":"denied by the auto mode classifier"}'
got=$(signals "$NOW" < "$LOG")
[ "${got%%:*}" = quiet ] || fail "a lone call the classifier denied reads as: '$got'"
echo "PASS: a denied call is closed by its batch's end row, and nothing else hides an open call"
