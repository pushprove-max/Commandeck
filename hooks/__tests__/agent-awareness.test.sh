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
mkdir -p "$T/bin" "$T/ws/ours" # a listed worktree exists on disk
ln -s "$T/ws" "$T/lnk"
cat >"$T/bin/orca-ide" <<EOF
#!/bin/sh
[ "\$1 \$2" = "worktree ps" ] || { echo '{}'; exit 0; }
cat <<'J'
{"result":{"worktrees":[
 {"path":"$T/ws/ours","displayName":"Ours","branch":"refs/heads/ours","workspaceStatus":"in-progress","isMainWorktree":false},
 {"path":"$T/lnk/linked","displayName":"Linked","branch":"refs/heads/linked","workspaceStatus":"in-progress","isMainWorktree":false},
 {"path":"$T/ws-other/theirs","displayName":"Theirs","branch":"refs/heads/theirs","workspaceStatus":"in-progress","isMainWorktree":false}]}}
J
EOF
chmod +x "$T/bin/orca-ide"
export PATH="$T/bin:$PATH" CLAUDE_PROJECT_DIR="$T/proj" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_HOOK_FIRE_LOG=/dev/null

OUT=$(cd "$T/proj" && echo '{}' | COMMANDECK_AWARENESS_DIR="$T/aw" bash "$HERE/hooks/agent-awareness.sh")
check "a worktree of this project is listed" 1 "$(case "$OUT" in *'Ours [ours]'*) echo 1 ;; *) echo 0 ;; esac)"
check "another project's worktree is not" 0 "$(case "$OUT" in *Theirs*) echo 1 ;; *) echo 0 ;; esac)"
# A trailing slash or /. is a valid way to name a folder; it must not hide every worktree.
n=0
for s in / // /.; do
  n=$((n+1)) # its own record folder: "$T/aw$s" is one folder for every $s, and a repeat banner is held back
  OUT=$(cd "$T/proj" && echo '{}' | COMMANDECK_WORKSPACES="$T/ws$s" COMMANDECK_AWARENESS_DIR="$T/aw-$n" bash "$HERE/hooks/agent-awareness.sh")
  check "a worktrees folder given ending in $s still lists this project's worktree" 1 "$(case "$OUT" in *'Ours [ours]'*) echo 1 ;; *) echo 0 ;; esac)"
done
# A /./ or // inside the path is a valid spelling too.
for w in "$T/./ws" "$T//ws/./"; do
  n=$((n+1)); OUT=$(cd "$T/proj" && echo '{}' | COMMANDECK_WORKSPACES="$w" COMMANDECK_AWARENESS_DIR="$T/aw-$n" bash "$HERE/hooks/agent-awareness.sh")
  check "a worktrees folder given as <tmp>${w#"$T"} still lists this project's worktree" 1 "$(case "$OUT" in *'Ours [ours]'*) echo 1 ;; *) echo 0 ;; esac)"
done
# Orca names a worktree as it was made, a link's spelling too: the folder given by that spelling still lists it.
OUT=$(cd "$T/proj" && echo '{}' | COMMANDECK_WORKSPACES="$T/lnk" COMMANDECK_AWARENESS_DIR="$T/aw-lnk" bash "$HERE/hooks/agent-awareness.sh")
check "a worktrees folder given by a link's spelling lists the worktree Orca names by it" 1 "$(case "$OUT" in *'Linked [linked]'*) echo 1 ;; *) echo 0 ;; esac)"
# main-watch's state and the owner's open asks are fetched beside the Orca calls; both still
# print every turn, or main misses that nothing wakes it and that the owner is waiting.
(cd "$T/proj" && COMMANDECK_RULING_LOG="$T/rulings.jsonl" bash "$HERE/scripts/decision.sh" add d1 "Ship it?" yes chat >/dev/null 2>&1)
OUT=$(cd "$T/proj" && echo '{}' | COMMANDECK_RULING_LOG="$T/rulings.jsonl" COMMANDECK_AWARENESS_DIR="$T/aw4" bash "$HERE/hooks/agent-awareness.sh")
check "main-watch down and an open decision both print" "1 1" "$(case "$OUT" in *'MAIN-WATCH NOT RUNNING'*) echo 1 ;; *) echo 0 ;; esac) $(case "$OUT" in *'Open decisions for the owner: d1'*) echo 1 ;; *) echo 0 ;; esac)"

# Per seat: main's row carries the banner, every other seat's is empty.
ROWS=$(bash "$HERE/scripts/startup-size.sh" --per-prompt 2>/dev/null | awk -F'\t' '$2 == "agent-awareness.sh" { printf "%s=%s ", $1, ($3 > 0) }')
check "startup-size --per-prompt shows the banner on main's row only" "main=1 worker=0 builder=0 chief-of-staff=0 " "$ROWS"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
