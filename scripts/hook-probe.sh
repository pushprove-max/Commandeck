#!/usr/bin/env bash
# hook-probe.sh <hook> '<command or tool_input json>' [--tool <tool>] -- run one hook on a built payload, read-only.
# Prints `allow`, `refuse (<exit>)` or `ask`, then the hook's message. The hook runs with HOME, TMPDIR and the
# hook fire log in a new scratch folder that is removed after, so a probe changes nothing a session reads.
# Issue 250: a Codex reviewer of a guard could read it but not run it. <hook> is a path from the current folder or
# from this checkout's root (hooks/no-poll-loops.sh). --tool Bash (the default) takes a command; any other tool
# takes its tool_input as JSON. The payload is a PreToolUse call from the current folder.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
usage() { echo "usage: hook-probe.sh <hook> '<command or tool_input json>' [--tool <tool>]" >&2; exit 2; }
[ $# = 2 ] || { [ $# = 4 ] && [ "$3" = --tool ]; } || usage
HOOK=$1 ARG=$2 TOOL=${4:-Bash}
[ -f "$HOOK" ] || HOOK=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/$1
[ -f "$HOOK" ] || { echo "hook-probe: no hook $1" >&2; exit 2; }
if [ "$TOOL" = Bash ]; then IN=$(jq -cn --arg c "$ARG" '{command: $c}')
else IN=$(jq -c . <<<"$ARG" 2>/dev/null) || { echo "hook-probe: the tool_input for $TOOL is not JSON" >&2; exit 2; }; fi
S=$(mktemp -d "${TMPDIR:-/tmp}/hook-probe.XXXXXX") || exit 2
S=$(cd "$S" && pwd -P) || exit 2 # issue 308: a relative TMPDIR must not make the hook's HOME relative
trap 'rm -rf "$S"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM # a signal still runs the EXIT trap above
mkdir -p "$S/home" "$S/tmp"
jq -cn --arg t "$TOOL" --argjson i "$IN" --arg s "probe-$$" --arg d "$PWD" \
  '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: $i, session_id: $s, cwd: $d}' > "$S/payload"
HOME=$S/home TMPDIR=$S/tmp COMMANDECK_HOOK_FIRE_LOG=$S/fire.jsonl bash "$HOOK" < "$S/payload" > "$S/out" 2> "$S/err"; RC=$?
DEC=$(jq -r '.hookSpecificOutput.permissionDecision // empty' "$S/out" 2>/dev/null)
if [ "$RC" != 0 ] || [ "$DEC" = deny ]; then echo "refuse ($RC)"; elif [ "$DEC" = ask ]; then echo ask; else echo allow; fi
cat "$S/err"; jq -r '.hookSpecificOutput.permissionDecisionReason // .hookSpecificOutput.additionalContext // empty' "$S/out" 2>/dev/null
exit 0
