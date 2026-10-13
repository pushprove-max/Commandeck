#!/usr/bin/env bash
# board-run.test.sh -- one machine runs several projects, and Orca keeps one
# machine-wide "current run" file. A watcher that followed it would post one
# project's wakes into another project's run, and rebind that run to the wrong
# pane. So each project keeps its own run file, and board.sh, which main runs
# first in every session, is its one writer: it records the run main's own
# terminal is bound to, and binds an unbound main to the recorded one.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

mkdir -p "$T/bin" "$T/home/.config/orca" "$T/scratch"
git init -q -b main "$T/main" && git -C "$T/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$T/main" worktree add -q "$T/wt" -b wt
echo run_foreign > "$T/home/.config/orca/current-run"
cat > "$T/bin/orca-ide" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
  *run-current*) [ -z "${BOUND_TO-}" ] && echo '{"ok":true,"result":{"run":null}}' || printf '{"ok":true,"result":{"run":{"id":"%s"}}}\n' "$BOUND_TO" ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
STUB
chmod +x "$T/bin/orca-ide"
board() { : > "$T/calls"; (cd "$1" && shift && env "$@" PATH="$T/bin:$PATH" HOME="$T/home" CALLS="$T/calls" COMMANDECK_SCRATCH="$T/scratch" \
  COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_HOST_OS=Linux timeout 60 bash "$ROOT/scripts/board.sh" 2>&1); }
F=$T/scratch/current-run

OUT=$(board "$T/main")
check "with no run of its own, the project has none: the machine-wide file is another project's" 1 "$(grep -c '^RUN=NONE ' <<<"$OUT")"
check "and nothing is bound to the foreign run" 0 "$(grep -c 'run-use' "$T/calls")"
check "main is told it is not bound" 1 "$(grep -c 'NOT BOUND TO A RUN' <<<"$OUT")"
OUT=$(board "$T/main" BOUND_TO=run_mine)
check "the run main's terminal is bound to is recorded for the project" run_mine "$(cat "$F" 2>/dev/null)"
check "and it is the run the board shows" 1 "$(grep -c '^RUN=run_mine ' <<<"$OUT")"
OUT=$(board "$T/main")
check "an unbound main is bound to the project's recorded run" 1 "$(grep -c 'run-use --id run_mine' "$T/calls")"
OUT=$(board "$T/wt" BOUND_TO=run_worker)
check "a worktree pane never moves the project's run" run_mine "$(cat "$F" 2>/dev/null)"
check "the machine-wide file is never written" run_foreign "$(cat "$T/home/.config/orca/current-run")"
# This project carries no scripts/ folder, as no project an installed plugin serves does.
check "the board's own helpers are the plugin's, not looked for in the project" 0 "$(board "$T/main" BOUND_TO=run_mine | grep -c 'No such file')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
