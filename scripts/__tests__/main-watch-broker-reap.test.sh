#!/usr/bin/env bash
# main-watch.sh reaps leaked Codex plugin brokers every tick. The openai-codex
# plugin starts one detached `app-server-broker.mjs serve --cwd <dir>` per
# Claude session and stops it only in that session's SessionEnd hook, which a
# closed pane never runs; on 2026-09-28 about 2,000 leaked children hit
# kern.maxprocperuid and crashed the Mac. A reaper that kills a live session's
# broker or a review in flight breaks work instead, so both sides are cases.
# ps, lsof, sysctl and kill are stubs: nothing real is listed or signalled.
set -euo pipefail

SOURCE=$(git rev-parse --show-toplevel)
T=$(cd "$(mktemp -d /tmp/main-watch-reap.XXXXXX)" && pwd -P)
trap 'rm -rf "$T"' EXIT
REPO=$T/repo S=$T/scratch F=$T/fake
mkdir -p "$REPO/scripts" "$T/bin" "$S" "$F" "$T/home/.config/orca" "$T/ws"
git -C "$REPO" init -q
cp "$SOURCE/scripts/main-watch.sh" "$SOURCE/scripts/paths.sh" "$SOURCE/scripts/project-main.sh" \
   "$SOURCE/scripts/host-services.sh" "$SOURCE/scripts/orca-task-create.sh" "$REPO/scripts/"
# The machine-wide file names another project's run: each project reads its own.
echo run_foreign > "$T/home/.config/orca/current-run"
mkdir -p "$S" && echo run_test > "$S/current-run"
export COMMANDECK_HOST_OS=Linux  # the systemctl stub is the service manager
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/systemctl"
cat > "$T/bin/orca-ide" <<ORCA
#!/usr/bin/env bash
case "\$1 \$2" in
  "orchestration task-list") echo '{"result":{"tasks":[]}}' ;;
  "orchestration task-create") echo '{"ok":true,"result":{"task":{"id":"task_1"}}}' ;;
  "orchestration send") printf '%s\n' "\$*" >> "$F/sends"; echo '{"ok":true}' ;;
  *) echo '{}' ;;
esac
ORCA
printf '#!/usr/bin/env bash\ncat "%s/ps"\n' "$F" > "$T/bin/ps"
printf '#!/usr/bin/env bash\ncat "%s/lsof"\nexit "$(cat "%s/lsof-rc" 2>/dev/null || echo 0)"\n' "$F" "$F" > "$T/bin/lsof"
printf '#!/usr/bin/env bash\necho 2666\n' > "$T/bin/sysctl"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/kills"\n' "$F" > "$T/bin/kill"
chmod +x "$T/bin/"*

PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1 (expected '$2', got '$3')"; fi }
has() { if grep -qF -- "$2" "$3" 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1 (no '$2' in $3: $(cat "$3" 2>/dev/null))"; fi }
tick() { # one --once run from a clean slate
  rm -rf "$S/main-watch" "$F/kills" "$F/sends"
  (cd "$REPO" && PATH=$T/bin:$PATH HOME=$T/home COMMANDECK_SCRATCH=$S COMMANDECK_WORKSPACES=$T/ws \
    COMMANDECK_NOW=5000 bash scripts/main-watch.sh --once) > "$T/out" 2>"$T/err" \
    || { echo "FAIL main-watch exited non-zero: $(cat "$T/err")"; exit 1; }
}
ME=$(id -u)

# uid pid ppid etime command, as `ps -A -o uid=,pid=,ppid=,etime=,command=` prints.
cat > "$F/ps" <<PS
$ME 100 1 02:00:00 node /p/app-server-broker.mjs serve --cwd /ws/dead
$ME 101 100 01:59:00 codex app-server
$ME 102 101 01:59:00 python3 serena
$ME 103 100 01:59:00 node /p/cbm --cbm-daemon-internal
$ME 104 103 01:00:00 node /p/cbm-client
$ME 200 1 30:00 node /p/app-server-broker.mjs serve --cwd /ws/young
$ME 201 200 29:00 codex app-server
$ME 300 1 1-00:00:00 node /p/app-server-broker.mjs serve --cwd /ws/live
$ME 301 300 23:00:00 codex app-server
$ME 310 1 05:00 /usr/local/bin/claude --dangerously-skip-permissions
$ME 400 1 03:00:00 node /p/app-server-broker.mjs serve --cwd /ws/review
$ME 401 400 10:00 node /p/codex-companion.mjs review --wait
$ME 500 1 05:00:00 node /p/cbm --cbm-daemon-internal
0 600 1 09:00:00 node /p/app-server-broker.mjs serve --cwd /ws/root
PS
printf 'p310\nfcwd\nn/ws/live\n' > "$F/lsof"
tick
check "only the old abandoned broker's tree is killed, children first, the cbm daemon spared" \
  "-TERM 102 101 100" "$(cat "$F/kills" 2>/dev/null)"
has "each kill is logged with pid, cwd, age and child count" "pid=100 cwd=/ws/dead age=7200s children=2" "$T/out"
check "a normal process count posts nothing" 0 "$(cat "$F/sends" 2>/dev/null | wc -l | tr -d ' ')"

# An lsof that names no working directory would make every broker look
# abandoned, the live session's included.
: > "$F/lsof"
tick
check "an unanswered lsof kills nothing" "" "$(cat "$F/kills" 2>/dev/null)"
# An lsof that failed part-way named some sessions and not the rest: the ones
# it did not name look abandoned just the same.
printf 'p401\nfcwd\nn/ws/review\n' > "$F/lsof"; echo 1 > "$F/lsof-rc"
tick
check "an lsof that failed with part of an answer kills nothing" "" "$(cat "$F/kills" 2>/dev/null)"
rm -f "$F/lsof-rc"

families() { # <node> <python3> <codex> <bash> -- this user's processes, plus root's
  { for i in $(seq 1 "$1"); do echo "$ME $((10000 + i)) 1 01:00 /usr/bin/node x"; done
    for i in $(seq 1 "$2"); do echo "$ME $((20000 + i)) 1 01:00 /usr/bin/python3 y"; done
    for i in $(seq 1 "$3"); do echo "$ME $((30000 + i)) 1 01:00 codex z"; done
    for i in $(seq 1 "$4"); do echo "$ME $((40000 + i)) 1 01:00 bash w"; done
    for i in $(seq 1 50); do echo "0 $((50000 + i)) 1 01:00 launchd"; done; } > "$F/ps"
}
families 1200 500 200 100
tick
check "exactly 2,000 processes posts nothing" 0 "$(cat "$F/sends" 2>/dev/null | wc -l | tr -d ' ')"
families 1200 500 200 101
tick
has "past 2,000 the item names this user's count" "2001 processes" "$F/sends"
has "the item names the cap read from kern.maxprocperuid" "cap 2666" "$F/sends"
has "the item names the top three command families" "node 1200, python3 500, codex 200" "$F/sends"

# A tree just sent SIGTERM is still running: the warning counts what ps saw, so
# a reap in the same tick never hides a machine that is over the line.
families 1200 500 200 99
printf '%s\n' "$ME 100 1 02:00:00 node /p/app-server-broker.mjs serve --cwd /ws/dead" \
  "$ME 101 100 01:59:00 codex app-server" "$ME 102 101 01:59:00 python3 serena" >> "$F/ps"
tick
check "the leaked tree is killed" "-TERM 102 101 100" "$(cat "$F/kills" 2>/dev/null)"
has "the same tick still warns on the observed count" "2002 processes" "$F/sends"

# A checkout whose path has a space: the broker's --cwd is the whole path, not
# its first word. Cut at the space, it matched no live session and the tree of
# a session still running was killed.
cat > "$F/ps" <<PS
$ME 700 1 02:00:00 node /p/app-server-broker.mjs serve --cwd /ws/My Repo
$ME 701 700 01:59:00 codex app-server
$ME 710 1 05:00 /usr/local/bin/claude --dangerously-skip-permissions
$ME 800 1 02:00:00 node /p/app-server-broker.mjs serve --cwd /ws/My Other
$ME 801 800 01:59:00 codex app-server
PS
printf 'p710\nfcwd\nn/ws/My Repo\n' > "$F/lsof"
tick
check "a live session in a folder with a space keeps its broker; the abandoned one beside it goes" "-TERM 801 800" "$(cat "$F/kills" 2>/dev/null)"

echo "main-watch-broker-reap: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
