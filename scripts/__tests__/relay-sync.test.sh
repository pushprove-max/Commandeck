#!/usr/bin/env bash
# relay-sync.sh tells setup and update whether the relay (Chief of Staff) worktree is behind main, and rebases it only
# when asked. The relay's hooks and rules come from its checkout, so one left behind runs old rules. What this pins:
# commits behind are counted against the project's local main; --rebase brings it current; a relay with uncommitted
# changes or a conflicting commit is refused and left exactly as it was (no rebase half done).
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home; mkdir -p "$HOME" "$T/ws"
P=$T/proj R=$T/ws/Chief-of-Staff
g() { git -C "$P" -c user.name=t -c user.email=t@t "$@"; }
git init -q -b main "$P" && echo base > "$P/a.txt" && g add a.txt && g commit -q -m base
sync() { (cd "$P" && env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$P" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch" bash "$REAL/scripts/relay-sync.sh" "$@" 2>&1); }
check "no relay worktree: none" "relay: none" "$(sync)"
git -C "$P" worktree add -q "$R" -b relay main
check "a relay at main: current" "relay: current" "$(sync)"
for i in 1 2; do echo "m$i" > "$P/m$i.txt"; g add "m$i.txt"; g commit -q -m "m$i"; done
check "a relay two commits behind main says so" "relay: 2 commits behind main" "$(sync)"
BEFORE=$(git -C "$R" rev-parse HEAD)
check "asking changes nothing" "$BEFORE" "$(sync >/dev/null; git -C "$R" rev-parse HEAD)"
echo dirty >> "$R/a.txt"
OUT=$(sync --rebase); RC=$?
check "a relay with uncommitted changes is refused, HEAD unchanged" "1:1:$BEFORE" "$RC:$(grep -c 'uncommitted' <<<"$OUT"):$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -- a.txt
sync --rebase >/dev/null
check "--rebase brings a clean relay to main" "relay: current" "$(sync)"
# A relay commit that conflicts with main: the rebase is aborted, not left half done.
echo relay > "$R/c.txt"; git -C "$R" add c.txt; git -C "$R" -c user.name=t -c user.email=t@t commit -q -m relay-c
echo main > "$P/c.txt"; g add c.txt; g commit -q -m main-c
BEFORE=$(git -C "$R" rev-parse HEAD)
OUT=$(sync --rebase); RC=$?
check "a conflicting relay commit is refused, HEAD unchanged, no rebase in progress" "1:$BEFORE:0" \
  "$RC:$(git -C "$R" rev-parse HEAD):$(ls -d "$(git -C "$R" rev-parse --absolute-git-dir)"/rebase-* 2>/dev/null | wc -l | tr -d ' ')"
# A relay the owner paused at an interactive rebase's edit step is clean but mid-rebase: refused, and their rebase kept (not aborted).
GD=$(git -C "$R" rev-parse --absolute-git-dir)
git -C "$R" reset -q --hard HEAD~1
echo relay2 > "$R/d.txt"; git -C "$R" add d.txt; git -C "$R" -c user.name=t -c user.email=t@t commit -q -m relay-d
GIT_SEQUENCE_EDITOR="sed -i.bak 1s/pick/edit/" git -C "$R" -c user.name=t -c user.email=t@t rebase -q -i HEAD~1 >/dev/null 2>&1
BEFORE=$(git -C "$R" rev-parse HEAD)
OUT=$(sync --rebase); RC=$?
check "a relay paused in the owner's rebase is refused and the rebase kept" "1:1:$BEFORE:1" \
  "$RC:$(grep -c 'middle of a rebase' <<<"$OUT"):$(git -C "$R" rev-parse HEAD):$(ls -d "$GD"/rebase-* 2>/dev/null | wc -l | tr -d ' ')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
