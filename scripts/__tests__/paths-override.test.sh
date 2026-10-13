#!/usr/bin/env bash
# paths-override.test.sh -- COMMANDECK_MAIN and COMMANDECK_WORKSPACES exist for
# the self-tests and the installed jobs. A Builder works in a linked worktree
# and controls its own shell: with either variable honoured there as given, it
# could point every plugin script at a checkout of its choosing (its own tree,
# with its own brief, rulings and config). What this pins: inside a linked
# worktree the project is the one git says the worktree belongs to, for every
# script family; and the variables still work where the tests need them.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

export HOME=$T/home; WS=$HOME/orca/workspaces/one; mkdir -p "$WS" "$T/bin" "$T/plain"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/orca-ide"; chmod +x "$T/bin/orca-ide"
for p in one two; do
  git init -q -b main "$T/$p" && git -C "$T/$p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
done
U=$WS/unit; git -C "$T/one" worktree add -q "$U" -b unit
SLUG=$(printf %s "$T/one" | tr -c 'A-Za-z0-9' '-')

# forged <command...> -- run in the Builder's worktree, both variables naming that worktree.
forged() { ( cd "$U" && env -u COMMANDECK_SCRATCH -u COMMANDECK_ROUTING PATH="$T/bin:$PATH" CLAUDE_PROJECT_DIR="$U" COMMANDECK_MAIN="$U" COMMANDECK_WORKSPACES="$U" "$@" 2>&1 ); }
# vars <file to source after paths.sh, or ''> <printf of PP_* names>
vars() { forged bash -c '. "$0" >/dev/null && { [ -z "$1" ] || . "$1"; } && eval "printf %s \"$2\""' "$REAL/scripts/paths.sh" "$1" "$2"; }

check "paths.sh: main is the checkout the worktree belongs to, and the worktrees are main's" "$T/one $WS" "$(vars '' '$PP_MAIN $PP_WORKSPACES')"
check "and so is the scratch folder" "$HOME/.commandeck/scratch/$SLUG" "$(vars '' '$PP_SCRATCH')"
check "hooks: the run file is main's" "$HOME/.commandeck/scratch/$SLUG/current-run" "$(forged bash -c '. "$0" && pp_run_file' "$REAL/hooks/lib/project.sh")"
check "set-up, doctor, uninstall: the config and the install record are main's" "$T/one/.claude/commandeck.json $HOME/.commandeck/install/$SLUG.json" "$(vars "$REAL/scripts/install-lib.sh" '$IL_CONFIG $IL_PROJECT')"
check "the relay's scripts: the run they read is main's" "$HOME/.commandeck/scratch/$SLUG/current-run" "$(forged bash -c '. "$0" >/dev/null && printf %s "$PP_RUN_FILE"' "$REAL/scripts/cos-lib.sh")"
check "the watcher: its job is named for main" 1 "$(forged bash "$REAL/scripts/main-watch.sh" --job-file | grep -c 'main-watch-one')"
check "the ledger: the one it looks for is main's" 1 "$(forged bash "$REAL/scripts/decision.sh" list | grep -c "$T/one/")"
echo '- one item' > "$T/batch.md"
OUT=$(forged bash "$REAL/scripts/builder-launch.sh" --dry-run next "$T/batch.md")
check "the Builder launch: the worktree it would make is under main's worktrees" "0" "$(grep -c "$U/next" <<<"$OUT")"
OUT=$(forged bash "$REAL/scripts/builder-codex-pass.sh" unit 1 adversarial)
check "the review pass: it looks for the unit under main's worktrees, not inside the Builder's tree" 0 "$(grep -c "$U/unit" <<<"$OUT")"
OUT=$(forged bash "$REAL/scripts/merge-queue.sh" unit)
check "the merge queue: its log is in main's scratch" 0 "$(ls "$HOME/.commandeck/scratch" 2>/dev/null | grep -vc "^$SLUG\$")"
OUT=$(forged env COMMANDECK_SEAT_REPO=other bash "$REAL/scripts/seat.sh" launch implementer next)
check "a seat in another repo: its worktrees are that repo's, not the Builder's tree" 0 "$(grep -c "$U/next" <<<"$OUT")"

# A Builder that names some other checkout, or its own main's sibling worktree, gets main all the same.
git -C "$T/one" worktree add -q "$WS/other" -b other
check "another worktree of the same project is not main either" "$T/one" "$(cd "$U" && env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$WS/other" bash -c '. "$0" >/dev/null && printf %s "$PP_MAIN"' "$REAL/scripts/paths.sh")"
# Where the variables still decide: outside a linked worktree (the installed
# jobs, a main checkout), and for a fixture: a folder under the system's temp
# folder that is no checkout of the worktree's own project. Test fixtures are
# made there, and a self-test run from a Builder's worktree must reach its own.
check "in a main checkout the override is honoured as given" "$T/two $T/plain" "$(cd "$T/one" && env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$T/two" COMMANDECK_WORKSPACES="$T/plain" bash -c '. "$0" >/dev/null && printf "%s %s" "$PP_MAIN" "$PP_WORKSPACES"' "$REAL/scripts/paths.sh")"
check "in a linked worktree a fixture of another project is honoured" "$T/two $T/plain" "$(cd "$U" && env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$T/two" COMMANDECK_WORKSPACES="$T/plain" bash -c '. "$0" >/dev/null && printf "%s %s" "$PP_MAIN" "$PP_WORKSPACES"' "$REAL/scripts/paths.sh")"
check "a worktrees root given for what it is (the folder this worktree is in) is honoured anywhere" "$WS" "$(cd "$U" && env -u CLAUDE_PROJECT_DIR COMMANDECK_WORKSPACES="$WS" bash -c '. "$0" >/dev/null && printf %s "$PP_WORKSPACES"' "$REAL/scripts/paths.sh")"
# The session's project is a variable too. In a linked worktree it cannot name another project.
here() { ( cd "$U" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN -u COMMANDECK_WORKSPACES "$@" bash -c '. "$0" >/dev/null && printf "%s %s" "$PP_MAIN" "$PP_WORKSPACES"' "$REAL/scripts/paths.sh" ); }
# The plugin's own checkout stands in for "another project": it is a real one, outside the temp folder.
ELSE=$(git -C "$REAL" rev-parse --path-format=absolute --git-common-dir); ELSE=${ELSE%/.git}
check "a session project naming another project does not move a linked worktree's main" "$T/one $WS" "$(here CLAUDE_PROJECT_DIR="$ELSE")"
# The plugin's own tree is a linked worktree whenever a Builder runs this test.
check "nor does one naming another project's worktree" "$T/one $WS" "$(here CLAUDE_PROJECT_DIR="$REAL")"
check "a session in a worktree whose shell stands in a main checkout keeps the session's project" "$T/one" "$(cd "$T/two" && env -u COMMANDECK_MAIN -u COMMANDECK_WORKSPACES CLAUDE_PROJECT_DIR="$U" bash -c '. "$0" >/dev/null && printf %s "$PP_MAIN"' "$REAL/scripts/paths.sh")"
# A worktree that sits under the temp folder while its main checkout does not is no fixture:
# what counts is the checkout that would be acted on. Made here from this tree's own git
# pointer, read only; in a main checkout there is no pointer to copy.
if [ -f "$REAL/.git" ]; then
  mkdir "$T/tempwt"; cp "$REAL/.git" "$T/tempwt/.git"
  check "nor does a worktree of another project that only sits under the temp folder" "$T/one $WS" "$(here CLAUDE_PROJECT_DIR="$T/tempwt")"
  check "the same folder is no fixture for either variable" "$T/one $WS|$T/one $WS" "$(here COMMANDECK_MAIN="$T/tempwt")|$(here COMMANDECK_WORKSPACES="$T/tempwt/ws")"
else
  echo "SKIPPED (not run from a linked worktree): a temp-folder worktree of a project outside it"
fi
check "a session project that is a fixture is followed, as a hook's self-test needs" "$T/two" "$(here CLAUDE_PROJECT_DIR="$T/two" | cut -d' ' -f1)"
# Whichever input names a stand-in project, it is never paired with the real worktrees folder.
check "a fixture session project is not followed together with the real worktrees folder" "$T/one $WS" "$(here CLAUDE_PROJECT_DIR="$T/two" COMMANDECK_WORKSPACES="$WS")"
mkdir -p "$T/samename/one" && git init -q -b main "$T/samename/one" && git -C "$T/samename/one" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
check "nor one whose own default worktrees folder is the real one" "$T/one $WS|$T/one $WS" "$(here CLAUDE_PROJECT_DIR="$T/samename/one")|$(here COMMANDECK_MAIN="$T/samename/one")"
# A fixture is judged by where the path really is, never by how it is spelled.
check "a path spelled under the temp folder that climbs out of it is no fixture" "$T/one $WS" "$(here COMMANDECK_WORKSPACES="/tmp/../../../../../../usr/not-made-$$")"
check "nor is a folder not made yet inside a checkout of the worktree's own project" "$T/one $WS" "$(here COMMANDECK_WORKSPACES="$U/not-made")"
check "a fixture folder not made yet is still one" "$T/one $T/not-made/ws" "$(here COMMANDECK_WORKSPACES="$T/not-made/ws")"
ln -s "$HOME" "$T/link"
check "a link under the temp folder is judged by what it points at" "$T/one $WS" "$(here COMMANDECK_WORKSPACES="$T/link/orca/workspaces/one/unit")"
# The one place: no other script or hook reads either variable for itself.
check "only the one resolver reads the two variables" "scripts/project-main.sh" \
  "$(cd "$REAL" && grep -lE '\$\{?COMMANDECK_(MAIN|WORKSPACES)\b' scripts/*.sh hooks/*.sh hooks/lib/*.sh | paste -sd' ' -)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
