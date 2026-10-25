#!/usr/bin/env bash
# suite-rerun-guard.sh: the rerun block tells the worker to record a needed check as a main-only deferred item, never
# to ask main (message cuts: a blocked tool call is no question for main). The block itself is unchanged.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/suite-rerun-guard.sh"
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
P=$(jq -cn --arg d "$T/p" '{tool_name: "Bash", cwd: $d, tool_input: {command: "npm test"}}')
hook() { env COMMANDECK_HOOK_TIER=strict COMMANDECK_SUITE_RUNS_DIR="$T/runs" bash "$HOOK" "$@" <<<"$P" 2>&1 >/dev/null; echo "rc=$?"; }
check "the first run of a suite on a tree passes" "rc=0" "$(hook)"
env COMMANDECK_HOOK_TIER=strict COMMANDECK_SUITE_RUNS_DIR="$T/runs" bash "$HOOK" --record-complete <<<"$P" >/dev/null 2>&1
OUT=$(hook)
check "the same suite on the same tree is blocked" 1 "$(grep -c '^rc=2$' <<<"$OUT")"
check "and the block tells the worker to record a main-only deferred item, not to ask main" 1 \
  "$(grep -c 'Do not ask main: if you still need that check, record it as a main-only deferred item (one line under ## Main-only (deferred)' <<<"$OUT")"

# A worker in a linked worktree sees its diff against main once, before its first suite run of a session: the
# files outside its brief show then, not at review. Advice only: the exit code is the run's own.
git -C "$T/p" worktree add -q -b wk "$T/wk" && echo a > "$T/wk/in-brief.txt" && git -C "$T/wk" add in-brief.txt \
  && git -C "$T/wk" -c user.name=t -c user.email=t@t commit -q -m work
for i in $(seq 1 22); do echo u > "$T/wk/untracked-$i.txt"; done
run() { # <cwd> <session id or -> <command> [env...] -- the hook's stdout; its exit code goes to $T/rc
  local cwd=$1 sid=$2 cmd=$3; shift 3
  jq -cn --arg d "$cwd" --arg c "$cmd" --arg s "$sid" '{tool_name: "Bash", cwd: $d, tool_input: {command: $c}} + (if $s == "-" then {} else {session_id: $s} end)' \
    | env -u COMMANDECK_REVIEWER COMMANDECK_HOOK_TIER=strict COMMANDECK_SUITE_RUNS_DIR="$T/runs" "$@" bash "$HOOK" 2>/dev/null; echo $? > "$T/rc"; }
hits() { grep -c 'Your diff against main, before this first test run' <<<"$1"; }
O1=$(run "$T/wk" s1 'npm test')
check "the first suite run of a session in a worktree prints the diff against main, once" "1:0" "$(hits "$O1"):$(cat "$T/rc")"
check "it names the changed file" 1 "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$O1" | grep -c 'in-brief.txt')"
check "and names 20 untracked files, then a count of the rest" "20 1" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$O1" | grep -c '^untracked-') $(jq -r '.hookSpecificOutput.additionalContext' <<<"$O1" | grep -c '^\.\.\. and 2 more$')"
check "the second run of that session prints nothing" 0 "$(hits "$(run "$T/wk" s1 'npm run test:unit')")"
# Of two first runs released together, the noclobber marker lets exactly one print.
run "$T/wk" s2 'npm test' > "$T/o-a" & run "$T/wk" s2 'npm run typecheck' > "$T/o-b" & wait
check "two first suite runs released at once in one session print the diffstat exactly once" 1 "$(( $(hits "$(cat "$T/o-a")") + $(hits "$(cat "$T/o-b")") ))"
check "another session gets its own" 1 "$(hits "$(run "$T/wk" s3 'npm test')")"
check "the main checkout prints nothing" 0 "$(hits "$(run "$T/p" s4 'npm test')")"
check "a reviewer pane prints nothing" 0 "$(hits "$(run "$T/wk" s5 'npm test' COMMANDECK_REVIEWER=1)")"
check "a call with no session id prints nothing" 0 "$(hits "$(run "$T/wk" - 'npm test')")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
