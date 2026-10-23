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
# Issue 308: a relative TMPDIR made the scratch folder, and so the hook's HOME, a relative path: a hook that changes
# folder then wrote into a real folder. A signal left the scratch folder behind, as bash skips an EXIT trap on one.
mkdir -p "$T/hooks" "$T/wt/rel-tmp"
printf '#!/usr/bin/env bash\necho "HOME=$HOME" >&2\n' > "$T/hooks/home.sh"
printf '#!/usr/bin/env bash\nsleep 3\n' > "$T/hooks/slow.sh"
check "a relative TMPDIR still gives the hook an absolute HOME" "HOME=/" \
  "$(cd "$T/wt" && HOME="$T/home" TMPDIR=rel-tmp bash "$REAL/scripts/hook-probe.sh" "$T/hooks/home.sh" true 2>&1 | grep -o '^HOME=.')"
(cd "$T/wt" && HOME="$T/home" TMPDIR="$T/tmp" exec bash "$REAL/scripts/hook-probe.sh" "$T/hooks/slow.sh" true >/dev/null 2>&1) & PID=$!
sleep 1; kill -TERM $PID; wait $PID 2>/dev/null; RC=$?
check "TERM during a probe removes the scratch folder and exits 143" "143 0" "$RC $(find "$T/tmp" -mindepth 1 | wc -l | tr -d ' ')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
