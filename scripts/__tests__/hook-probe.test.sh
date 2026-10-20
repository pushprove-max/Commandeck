#!/usr/bin/env bash
# Issue 250: a Codex reviewer of a guard could only read it, never run it, so "this refuses X" was a guess. What
# this pins: hook-probe.sh runs a hook on a built payload and prints allow or refuse with the hook's message, and
# writes nothing outside its own scratch folder (a reviewer's HOME stays as it was).
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.claude" "$T/tmp"; echo keep > "$T/home/.claude/x"
# A worker worktree: a linked checkout, where no-poll-loops holds a wait to the prompt-cache budget.
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$T/p" worktree add -q "$T/wt" -b u
probe() { (cd "$T/wt" && HOME="$T/home" TMPDIR="$T/tmp" bash "$REAL/scripts/hook-probe.sh" "$@" 2>&1); }
before=$(find "$T/home" "$T/tmp" | sort)
OUT=$(probe hooks/no-poll-loops.sh 'sleep 400')
check "a 400 s sleep in a worker is refused, with the hook's message" "refuse (2) 1" \
  "$(head -1 <<<"$OUT") $(grep -c 'past the prompt cache' <<<"$OUT")"
check "a short sleep is allowed" allow "$(probe hooks/no-poll-loops.sh 'sleep 5' | head -1)"
check "nothing is written under HOME or TMPDIR" "$before" "$(find "$T/home" "$T/tmp" | sort)"
check "an unknown hook is a usage error" 2 "$(probe hooks/no-such.sh 'true' >/dev/null; echo $?)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
