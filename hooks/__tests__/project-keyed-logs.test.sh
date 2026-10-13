#!/usr/bin/env bash
# The rulings log and the hook fire log live outside the repo, in one home
# directory every project on the machine shares. Each is named for the project
# the hook fired in, so two projects that enable the plugin never write one
# file, and a worktree writes its primary checkout's file, not one of its own.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home"
for p in proj-a "proj b"; do
  git init -q "$TMP/$p" && git -C "$TMP/$p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
done
git -C "$TMP/proj-a" worktree add -q "$TMP/wt-of-a" -b wt 2>/dev/null
prompt() { # cwd -- one owner prompt through ruling-log.sh, which arms the fire log itself
  (cd "$1" && printf '{"hook_event_name":"UserPromptSubmit","prompt":"go ahead","session_id":"s1","cwd":"%s"}' "$1" \
    | env -u COMMANDECK_RULING_LOG -u COMMANDECK_HOOK_FIRE_LOG -u CLAUDE_PROJECT_DIR HOME="$TMP/home" bash "$REAL/hooks/ruling-log.sh" >/dev/null 2>&1)
}
rows() { cat "$@" 2>/dev/null | wc -l | tr -d ' '; }
DAY=$(TZ=UTC0 date +%F)
R=$TMP/home/.claude/rulings H=$TMP/home/.claude/hook-fire-log
prompt "$TMP/proj-a"
check "a prompt in proj-a is logged under proj-a" 1 "$(rows "$R/proj-a.jsonl")"
check "its hook fire is logged under proj-a" 1 "$(rows "$H/proj-a.$DAY.jsonl")"
prompt "$TMP/wt-of-a"
check "a worktree's prompt joins its primary checkout's log" 2 "$(rows "$R/proj-a.jsonl")"
check "a worktree's hook fire joins its primary checkout's log" 2 "$(rows "$H/proj-a.$DAY.jsonl")"
prompt "$TMP/proj b"
check "a second project writes its own rulings log" "1 2" "$(rows "$R/proj-b.jsonl") $(rows "$R/proj-a.jsonl")"
check "a second project writes its own fire log" "1 2" "$(rows "$H/proj-b.$DAY.jsonl") $(rows "$H/proj-a.$DAY.jsonl")"
check "no log carries a fixed name" "" "$(ls "$R" "$H" | grep -i commandeck)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
