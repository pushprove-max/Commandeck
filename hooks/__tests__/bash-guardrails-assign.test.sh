#!/usr/bin/env bash
# covers: hooks/bash-guardrails.sh
# Issue 593: an assignment after `&&` or `||` may never run, so the path it names is not known to be the search's, and
# the binding before it may be gone: the variable reads unresolved (the warning). A plain assignment still binds.
# Its own file: bash-guardrails.test.sh runs near the 500-line cap.
set -u
export COMMANDECK_REVIEWER=0 COMMANDECK_HOOK_TIER=strict
HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
json() { jq -cn --arg cmd "$1" '{tool_input:{command:$cmd}}'; }
# A disposable main checkout, as bash-guardrails.test.sh uses, so the main-only search check runs.
MAIN_TMP=$(mktemp -d); trap 'rm -rf "$MAIN_TMP"' EXIT
git -C "$MAIN_TMP" init -q; printf '{}\n' > "$MAIN_TMP/package.json"; mkdir -p "$MAIN_TMP/hooks"
# Prints "<rc> <1 if the note names the unbounded path> <1 if rewritten>", as bash-guardrails.test.sh's warn_state.
run_warn() {
  local O RC; O=$(cd "$MAIN_TMP" && json "$1" | "$HOOK" 2>/dev/null; echo "rc=$?"); RC=${O##*rc=}
  echo "$RC $(grep -q 'over an unbounded path:' <<<"$O" && echo 1 || echo 0) $(grep -q updatedInput <<<"$O" && echo 1 || echo 0)"
}

check "a search path from an assignment after && is judged unresolved" "0 1 0" "$(run_warn 'F=.; true && F=hooks; rg foo "$F"')"
check "a search path from an assignment after || is judged unresolved" "0 1 0" "$(run_warn 'F=.; false || F=hooks; rg foo "$F"')"
check "a search path from a plain assignment is still read" "0 0 0" "$(run_warn 'true; F=hooks; rg foo "$F"')"
check "a search after && still reads a binding made before it" "0 0 0" "$(run_warn 'F=hooks; true && rg foo "$F"')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
