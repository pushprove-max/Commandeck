#!/usr/bin/env bash
# Self-test for agent-awareness.sh, main's every-prompt banner. Run directly.
# Orca lists every repo's worktrees: one from another project, listed here, is
# work main is told to verify and reconcile that is not its own. And the banner
# reaches main only, so startup-size.sh must not put it on a worker's row:
# a context trim aimed by that gauge would cut the wrong seat.
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
git init -q "$T/proj" && git -C "$T/proj" -c user.name=s -c user.email=s@s commit -q --allow-empty -m init
mkdir -p "$T/bin"
cat >"$T/bin/orca-ide" <<EOF
#!/bin/sh
[ "\$1 \$2" = "worktree ps" ] || { echo '{}'; exit 0; }
cat <<'J'
{"result":{"worktrees":[
 {"path":"$T/ws/ours","displayName":"Ours","branch":"refs/heads/ours","workspaceStatus":"in-progress","isMainWorktree":false},
 {"path":"$T/ws-other/theirs","displayName":"Theirs","branch":"refs/heads/theirs","workspaceStatus":"in-progress","isMainWorktree":false}]}}
J
EOF
chmod +x "$T/bin/orca-ide"
export PATH="$T/bin:$PATH" CLAUDE_PROJECT_DIR="$T/proj" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_HOOK_FIRE_LOG=/dev/null

OUT=$(cd "$T/proj" && echo '{}' | COMMANDECK_AWARENESS_DIR="$T/aw" bash "$HERE/hooks/agent-awareness.sh")
check "a worktree of this project is listed" 1 "$(case "$OUT" in *'Ours [ours]'*) echo 1 ;; *) echo 0 ;; esac)"
check "another project's worktree is not" 0 "$(case "$OUT" in *Theirs*) echo 1 ;; *) echo 0 ;; esac)"
# A trailing slash is a valid way to name a folder; it must not hide every worktree.
for s in / //; do
  OUT=$(cd "$T/proj" && echo '{}' | COMMANDECK_WORKSPACES="$T/ws$s" COMMANDECK_AWARENESS_DIR="$T/aw$s" bash "$HERE/hooks/agent-awareness.sh")
  check "a worktrees folder given ending in $s still lists this project's worktree" 1 "$(case "$OUT" in *'Ours [ours]'*) echo 1 ;; *) echo 0 ;; esac)"
done

# Per seat: main's row carries the banner, every other seat's is empty.
ROWS=$(bash "$HERE/scripts/startup-size.sh" --per-prompt 2>/dev/null | awk -F'\t' '$2 == "agent-awareness.sh" { printf "%s=%s ", $1, ($3 > 0) }')
check "startup-size --per-prompt shows the banner on main's row only" "main=1 worker=0 builder=0 chief-of-staff=0 " "$ROWS"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
