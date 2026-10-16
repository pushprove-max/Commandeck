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
# Consumers compare "$PP_WORKSPACES/..." as text with the paths Orca and the transcripts
# report: a trailing / or /. left in it made that "//" or "/./" and matched nothing. Nothing
# else is respelled (a link or .. too), or Orca's spelling of the same folder stops matching.
# COMMANDECK_MAIN is kept as given: the install manifest and the scratch folder are keyed by it.
spell() { ( cd "$T/one" && env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$1" COMMANDECK_WORKSPACES="$2" bash -c '. "$0" && pp_main_resolve && printf "%s %s" "$PP_MAIN" "$PP_WORKSPACES"' "$REAL/scripts/project-main.sh" ); }
ln -s "$T" "$T/link"
check "trailing slashes on the worktrees folder are dropped, COMMANDECK_MAIN's are kept" "$T/one/ $T/ws" "$(spell "$T/one/" "$T/ws//")"
check "a trailing /. on the worktrees folder is dropped, COMMANDECK_MAIN's is kept" "$T/one/. $T/ws" "$(spell "$T/one/." "$T/ws/./")"
check "a link's spelling of both is kept" "$T/link/one $T/link/ws" "$(spell "$T/link/one" "$T/link/ws")"

# #99: builder-launch.sh branches only from a main fast-forwarded from origin (pp_sync_main);
# a release marked published on origin and not fetched was rebuilt as a draft.
O=$T/one
git clone -q --bare "$O" "$T/origin.git"; git -C "$O" remote add origin "$T/origin.git"; git clone -q "$T/origin.git" "$T/other"
push() { git -C "$T/other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1" && git -C "$T/other" push -q origin HEAD:main; }
sync() { ( cd "$O" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES COMMANDECK_MAIN="$O" bash -c '. "$0" && pp_sync_main "$@"' "$REAL/scripts/paths.sh" "$O" "$@" 2>&1; echo "rc=$?" ); }
push "release: mark published"
check "--check with origin ahead moves nothing" "rc=0 first" "$(sync --check) $(git -C "$O" log -1 --format=%s main)"
check "with origin ahead, main is fast-forwarded" "rc=0 release: mark published" "$(sync) $(git -C "$O" log -1 --format=%s main)"
push "release: next"; git -C "$O" checkout -q -b off
check "off main, the main branch itself is fast-forwarded" "rc=0 release: next" "$(sync) $(git -C "$O" log -1 --format=%s main)"
git -C "$O" checkout -q main; git -C "$O" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "local only"; push "release: third"
check "a diverged main refuses with the reason" "1 rc=1 local only" "$(sync | grep -c 'cannot fast-forward') $(sync | tail -1) $(git -C "$O" log -1 --format=%s main)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
