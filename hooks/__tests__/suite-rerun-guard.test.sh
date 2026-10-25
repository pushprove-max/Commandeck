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
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
