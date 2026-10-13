#!/usr/bin/env bash
# Two projects with a unit of the same name shared one work folder and one
# page name: a review running beside another read the other's result.json, and
# a later one wrote over the earlier page. Each project has a folder of its
# own for both (a joined name would make project a-b unit c and project a unit b-c one file).
set -euo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for p in alpha beta; do
  git init -q -b main "$T/$p"
  git -C "$T/$p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
  git -C "$T/$p" worktree add -q "$T/ws-$p/unit-1" -b "builder/unit-1"
done
places() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import review; print(*review.places(sys.argv[2]))' "$REAL/skills/worktreereview/scripts" "$1"; }
A=$(places "$T/ws-alpha/unit-1") B=$(places "$T/ws-beta/unit-1/")
[ "$A" = "/tmp/commandeck/worktreereview/alpha/unit-1 alpha/unit-1" ] || { echo "FAIL: alpha's unit is placed at: $A" >&2; exit 1; }
[ "$B" = "/tmp/commandeck/worktreereview/beta/unit-1 beta/unit-1" ] || { echo "FAIL: beta's unit of the same name is placed at: $B" >&2; exit 1; }
echo "PASS: a build review's work folder and page are named by project and unit"
