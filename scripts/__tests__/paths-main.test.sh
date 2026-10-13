#!/usr/bin/env bash
# paths-main.test.sh -- an installed plugin's scripts sit in Claude Code's
# plugin cache, which is no checkout, and one copy serves every project on the
# machine. So the project a script works for is the one it is run in, never
# the one the script file sits in: resolving from the file would send every
# project's scratch, ledgers and worktrees to the plugin's own folder.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

export HOME=$T/home; mkdir -p "$HOME" "$T/nowhere" "$T/installed"
cp -R "$REAL/scripts" "$REAL/config" "$T/installed/"   # a copy outside any checkout, as the plugin cache is
for p in one two; do
  git init -q -b main "$T/$p" && git -C "$T/$p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
done
git -C "$T/one" worktree add -q "$T/one-wt" -b wt

# main <paths.sh> <cwd> [VAR=value]... -- PP_MAIN as a script run there resolves it, or the failure's text.
main() {
  local f=$1 d=$2; shift 2
  ( cd "$d" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH "$@" \
      bash -c '. "$0" >/dev/null && printf %s "$PP_MAIN"' "$f" 2>&1 )
}
I=$T/installed/scripts/paths.sh

check "an installed copy works for the project it is run in" "$T/one" "$(main "$I" "$T/one")"
check "run in a worktree, it names that project's main checkout" "$T/one" "$(main "$I" "$T/one-wt")"
check "the session's project wins over wherever the shell has wandered" "$T/one" "$(main "$I" "$T/two" CLAUDE_PROJECT_DIR="$T/one-wt")"
check "a session project that is no checkout falls back to the folder it is run in" "$T/two" "$(main "$I" "$T/two" CLAUDE_PROJECT_DIR="$T/nowhere")"
check "the override is honoured as given" "$T/two" "$(main "$I" "$T/one" COMMANDECK_MAIN="$T/two" CLAUDE_PROJECT_DIR="$T/one")"
check "the plugin's own checkout is never the answer for another project" "$T/two" "$(main "$REAL/scripts/paths.sh" "$T/two")"
OUT=$(main "$I" "$T/nowhere"); RC=$?
check "outside any project it fails" 1 "$RC"
check "and says how to name one" 1 "$(grep -c 'COMMANDECK_MAIN' <<<"$OUT")"
check "the scratch and the worktrees follow the project, not the plugin" "$HOME/orca/workspaces/two $HOME/.commandeck/scratch/$(printf %s "$T/two" | tr -c 'A-Za-z0-9' '-')" \
  "$(cd "$T/two" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH bash -c '. "$0" >/dev/null && printf "%s %s" "$PP_WORKSPACES" "$PP_SCRATCH"' "$I" 2>&1)"

# The project's Orca run is named in its scratch folder. The hooks cannot pay
# for all of paths.sh on every tool call, so hooks/lib/project.sh spells the
# same path; the two must agree, or a pane asks one run and the watcher another.
runfile() { ( cd "$1" && shift && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH "$@" \
    bash -c '. "$0" >/dev/null && . "$1" && printf "%s %s" "$PP_RUN_FILE" "$(pp_run_file)"' "$I" "$REAL/hooks/lib/project.sh" 2>&1 ); }
W="$HOME/.commandeck/scratch/$(printf %s "$T/two" | tr -c 'A-Za-z0-9' '-')/current-run"
check "the run file is the project's, and the hooks name the same one" "$W $W" "$(runfile "$T/two")"
W="$HOME/.commandeck/scratch/$(printf %s "$T/one" | tr -c 'A-Za-z0-9' '-')/current-run"
check "a worktree pane reads its project's run file" "$W $W" "$(runfile "$T/one-wt")"
check "the session's project decides it, as for everything else" "$W $W" "$(runfile "$T/two" CLAUDE_PROJECT_DIR="$T/one-wt")"
check "a scratch override moves both" "$T/s/current-run $T/s/current-run" "$(runfile "$T/two" COMMANDECK_SCRATCH="$T/s")"
check "a named project moves both" "$W $W" "$(runfile "$T/two" COMMANDECK_MAIN="$T/one")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
