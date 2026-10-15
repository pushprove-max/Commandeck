#!/usr/bin/env bash
# project-main.test.sh -- a Builder works in a linked worktree and controls its
# own shell. COMMANDECK_MAIN and COMMANDECK_WORKSPACES are followed there only
# for a fixture under the temp folder, so a Builder cannot point the plugin's
# scripts at a checkout of its choosing. What this pins: Git's own routing
# variables do not hide the worktree from that rule, and a stand-in project is
# never paired with a worktrees folder outside the temp folder.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

for p in one samename/one; do
  mkdir -p "$T/$p" && git init -q -b main "$T/$p" && git -C "$T/$p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
done
U=$T/ws/unit; git -C "$T/one" worktree add -q "$U" -b unit
# resolve <env assignments...>: PP_MAIN and PP_WORKSPACES as the Builder in $U gets them.
resolve() { ( cd "$U" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN -u COMMANDECK_WORKSPACES "$@" bash -c '. "$0" && pp_main_resolve && printf "%s %s" "$PP_MAIN" "$PP_WORKSPACES"' "$REAL/scripts/project-main.sh" ); }

check "GIT_DIR naming main's git folder does not let the Builder name its own tree" "$T/one" \
  "$(resolve GIT_DIR="$(git -C "$U" rev-parse --path-format=absolute --git-common-dir)" COMMANDECK_MAIN="$U" COMMANDECK_WORKSPACES="$U" | cut -d' ' -f1)"
# A home outside the temp folder, as a real one is: the stand-in's default worktrees
# folder is then a real project's of the same name. Fixed, so a runner's HOME under temp cannot change it.
check "a stand-in project is not paired with a real project's worktrees folder of the same name" "$T/one" \
  "$(resolve HOME=/nonexistent-home COMMANDECK_MAIN="$T/samename/one" | cut -d' ' -f1)"
check "a stand-in project with its worktrees folder under the temp folder is followed" "$T/samename/one $T/home/orca/workspaces/one" \
  "$(resolve HOME="$T/home" COMMANDECK_MAIN="$T/samename/one")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
