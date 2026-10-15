#!/usr/bin/env bash
# subagent-usage.sh runs on every dashboard collect over every subagent
# transcript on the machine, so it picks the ones to parse with one stat and
# one awk, not a stat, a grep and a date per file. What this pins: a run
# finished 10 minutes or more ago is recorded once; a run still being written
# waits; a run that went on after its row gets a new row; a run in another
# project whose folder name starts with this one's is not this project's.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
git init -q -b main "$T/proj" && git -C "$T/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
P=$T/projects; slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '-'; }
# run <folder> <agent id> <cwd> <minutes ago>
run() { local f="$P/$1/s1/subagents/agent-$2.jsonl"; mkdir -p "${f%/*}"
  printf '{"type":"user","cwd":"%s","timestamp":"2026-10-10T12:00:00Z"}\n' "$3" > "$f"; touch -d "@$(( $(date +%s) - $4 * 60 ))" "$f"; }
usage() { (cd "$T/proj" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/proj" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_CLAUDE_PROJECTS="$P" bash "$REAL/scripts/subagent-usage.sh"); }
rows() { jq -r .agentId "$T/proj/.claude/metrics/subagent-usage.jsonl" 2>/dev/null | sort | tr '\n' ' '; }

run "$(slug "$T/proj")" main1 "$T/proj" 20
run "$(slug "$T/proj")" live1 "$T/proj" 1
run "$(slug "$T/ws")-u1" wt1 "$T/ws/u1" 30
run "$(slug "$T/ws")-private-x" other1 "$T/ws-private/x" 30
usage
check "a finished run in main or a worktree is recorded; one still written waits; another project's is left" "main1 wt1 " "$(rows)"
usage
check "a second collect with nothing new records nothing" "main1 wt1 " "$(rows)"
touch -d "@$(( $(date +%s) - 15 * 60 ))" "$P/$(slug "$T/proj")/s1/subagents/agent-main1.jsonl"
usage
check "a run written since its row gets a new one" "main1 main1 wt1 " "$(rows)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
