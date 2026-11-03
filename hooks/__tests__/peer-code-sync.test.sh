#!/usr/bin/env bash
# Self-test for peer-code-sync.sh: the SessionStart hook that moves the main checkout's main forward to the newest
# of origin/main and the peer's main, and never anything else. A wrong move here rewrites the owner's main on
# session start, so every refusal case asserts HEAD and the files are intact.
# Run: bash hooks/__tests__/peer-code-sync.test.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOOK=$ROOT/hooks/peer-code-sync.sh
T=$(mktemp -d)
LOCKPID=
trap '[ -z "$LOCKPID" ] || kill "$LOCKPID" 2>/dev/null; rm -rf "$T"' EXIT
pass=0 fail=0
check() { # name want got
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "ok   - $1"
  else fail=$((fail + 1)); echo "FAIL $1 (want '$2', got '$3')"; fi
}

mkdir -p "$T/home"
export HOME=$T/home COMMANDECK_HOOK_TIER=strict
unset ORCA_TERMINAL_HANDLE
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.t

# fresh -- origin (bare), a peer clone and the main clone, all at one base.
fresh() {
  rm -rf "$T/origin.git" "$T/peer" "$T/main" "$T/wt"
  git init -q --bare -b main "$T/origin.git"
  git clone -q "$T/origin.git" "$T/main" 2>/dev/null
  git -C "$T/main" checkout -q -b main 2>/dev/null
  printf 'base\n' > "$T/main/f.txt"
  git -C "$T/main" add -A && git -C "$T/main" commit -qm base && git -C "$T/main" push -q origin main
  git clone -q "$T/origin.git" "$T/peer"
}
commit_in() { # repo file text
  printf '%s\n' "$3" > "$1/$2"; git -C "$1" add -A; git -C "$1" commit -qm "$2 $3"; git -C "$1" rev-parse HEAD
}
run() { (cd "${1:-$T/main}" && COMMANDECK_PEER_REPO=${PEER-$T/peer} bash "$HOOK" </dev/null 2>/dev/null); }
head_of() { git -C "${1:-$T/main}" rev-parse HEAD; }

# Catches: the hook written but never registered, so no session syncs.
check "hook is wired at SessionStart" 1 \
  "$(jq '[.hooks.SessionStart[] | select(.matcher == null) | .hooks[].command | select(test("peer-code-sync.sh"))] | length' "$ROOT/hooks/hooks.json")"

fresh; peer_tip=$(commit_in "$T/peer" f.txt peer)
peer_refs=$(git -C "$T/peer" for-each-ref)
out=$(run)
check "behind the peer: fast-forwards and names it" "synced to $peer_tip from peer" "$out"
check "behind the peer: HEAD is the peer tip" "$peer_tip" "$(head_of)"
check "behind the peer: the peer is never written" "$peer_refs" "$(git -C "$T/peer" for-each-ref)"

fresh; origin_tip=$(commit_in "$T/peer" f.txt pushed); git -C "$T/peer" push -q origin main
git -C "$T/peer" reset -q --hard HEAD~1
check "behind origin: fast-forwards from origin" "synced to $origin_tip from origin" "$(run)"

fresh; commit_in "$T/peer" f.txt one >/dev/null; git -C "$T/peer" push -q origin main
peer_tip=$(commit_in "$T/peer" f.txt two)
check "origin and peer both ahead in line: takes the newest" "synced to $peer_tip from peer" "$(run)"

# Catches: a main with local commits moved or reset to a remote.
fresh; local_tip=$(commit_in "$T/main" g.txt local)
check "a main ahead is never moved (up to date)" "up to date" "$(run)"
check "a main ahead is never moved (HEAD unchanged)" "$local_tip" "$(head_of)"
fresh; base=$(head_of)
check "equal: up to date" "up to date" "$(run)"
check "equal: HEAD unchanged" "$base" "$(head_of)"

fresh; local_tip=$(commit_in "$T/main" g.txt local); commit_in "$T/peer" f.txt peer >/dev/null
out=$(run)
check "diverged: WARN" "WARN: diverged" "${out%% from*}"
check "diverged: HEAD unchanged" "$local_tip" "$(head_of)"

fresh; base=$(head_of); commit_in "$T/peer" f.txt peer >/dev/null
printf 'local edit\n' > "$T/main/f.txt"
out=$(run)
check "dirty tracked file: WARN" "WARN: fast-forward refused" "${out%% to*}"
check "dirty tracked file: HEAD unchanged" "$base" "$(head_of)"
check "dirty tracked file: edit intact" "local edit" "$(cat "$T/main/f.txt")"

fresh; base=$(head_of)
check "unreachable peer (path): skipped" "peer unreachable, skipped" "$(PEER=$T/no-such-peer run)"
check "unreachable peer: HEAD unchanged" "$base" "$(head_of)"

# Catches: no peer set and an unreachable origin failing the session start.
fresh; git -C "$T/main" remote set-url origin "$T/no-such-origin.git"
out=$(PEER='' run); rc=$?
check "no peer and dead origin exit 0" "0 up to date" "$rc $out"

fresh; commit_in "$T/peer" f.txt peer >/dev/null
git -C "$T/main" worktree add -q "$T/wt" -b unit 2>/dev/null
check "linked worktree: silent" "" "$(run "$T/wt")"
check "linked worktree: nothing moved" "$(head_of "$T/main")" "$(head_of "$T/wt")"
git -C "$T/main" checkout -q -b side
check "main checkout off branch main: silent" "" "$(run)"

# Catches: the fast-forward running on the default tier, which only notes.
fresh; base=$(head_of); commit_in "$T/peer" f.txt peer >/dev/null
out=$(COMMANDECK_HOOK_TIER=default run)
check "default tier: silent, main unmoved" "|$base" "$out|$(head_of)"

# Catches: main moved under a running merge (its state names a live pid).
fresh; base=$(head_of); commit_in "$T/peer" f.txt peer >/dev/null
printf 'pid=%s\nunit=u\n' "$$" > "$T/main/.git/merge-unit-local.state"
out=$(run)
check "a live merge leaves main unmoved" "merge in progress, main not moved|$base" "$out|$(head_of)"
rm -f "$T/main/.git/merge-unit-local.state"

# Catches: a merge that takes its lock after the state check, during the fetch, being moved under.
fresh; base=$(head_of); commit_in "$T/peer" f.txt peer >/dev/null
flock "$T/main/.git/merge-unit-local.lock" sleep 30 & LOCKPID=$!
sleep 1
out=$(run)
check "a merge that starts mid-fetch leaves main unmoved" "merge in progress, main not moved|$base" "$out|$(head_of)"
kill "$LOCKPID" 2>/dev/null; wait "$LOCKPID" 2>/dev/null; LOCKPID=

echo "---"
echo "pass $pass, fail $fail"
[ "$fail" -eq 0 ]
