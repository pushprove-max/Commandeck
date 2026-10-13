#!/usr/bin/env bash
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export COMMANDECK_HOOK_FIRE_LOG="$T/fires.jsonl"
# The fingerprint is paid only by a blocked call and the session's next call
# (main ruling 2026-10-10), so the first action is a block (status 2).
row() {
  (
    . "$ROOT/hooks/lib/hook-fire-log.sh"
    payload=$(jq -cn --arg c "$1" --arg u "$2" \
      '{session_id:"11111111-2222-4333-8444-555555555555",
        hook_event_name:"PreToolUse",tool_name:"Bash",
        tool_input:{command:$c},tool_use_id:$u}')
    hook_fire_log_arm "$payload"
    exit "${3:-0}"
  ) || true
}
fail=0
for size in 500 5000; do
  printf -v pad '%*s' "$size" ''
  a="echo ${pad}aaaaaaaaaa"
  p=10
  [ "$size" -eq 5000 ] && p=4500
  b="${a:0:p}b${a:p+1}"
  row "$a" "toolu_a$size" 2
  row "$b" "toolu_b$size"
  if ! tail -2 "$COMMANDECK_HOOK_FIRE_LOG" |
    jq -se '.[0].call and .[1].call and .[0].call != .[1].call' >/dev/null; then
    printf 'different %s-byte actions share a fingerprint\n' "$size"
    fail=1
  fi
done
exit "$fail"
