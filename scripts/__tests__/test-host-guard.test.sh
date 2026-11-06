#!/usr/bin/env bash
# covers: scripts/test-host-guard.sh scripts/run-shell-tests.sh
# Issue 665, widened (main answers answer-1793897806-20012 and answer-1793897920-58931): a Builder's script started
# main-watch.test.sh on the Mac and ran it for 38 minutes; the Bash hook sees only the typed command, never a test a
# script starts. scripts/test-host-guard.sh is loaded through BASH_ENV, so bash reads it at the start of every
# non-interactive script, nested ones included: on the Mac it refuses a `__tests__/*.test.sh` started without the
# runner's marker (COMMANDECK_TEST_RUNNER, set by run-shell-tests.sh for each file it starts), and it does nothing on
# any other host or for any other script. The host is faked with COMMANDECK_HOST_OS, as the hook's test does.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GUARD=$ROOT/scripts/test-host-guard.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
# A Commandeck checkout (its __tests__ beside scripts/run-shell-tests.sh, the hook's rule) and another project's tests.
CD=$BOX/cd OTHER=$BOX/other HOSTCL=$BOX/host/.claude
mkdir -p "$CD/scripts/__tests__" "$OTHER/scripts/__tests__" "$HOSTCL/scripts/__tests__"
: > "$CD/scripts/run-shell-tests.sh"; : > "$HOSTCL/scripts/run-shell-tests.sh"
mkdir -p "$CD/.claude-plugin"; printf '{\n  "name": "commandeck",\n  "version": "0"\n}\n' > "$CD/.claude-plugin/plugin.json"
for f in "$CD/scripts/__tests__/inner.test.sh" "$OTHER/scripts/__tests__/health.test.sh" \
  "$HOSTCL/scripts/__tests__/own.test.sh" "$BOX/helper.sh"; do
  printf '#!/usr/bin/env bash\nset -u\necho RAN\n' > "$f"
done
# The script that starts a test file, as red-proof or break-run does: a bare `bash <file>`, nested inside another script.
printf '#!/usr/bin/env bash\nset -u\nbash "$1"\n' > "$BOX/starter.sh"
# run <host> <marker> <file>: the starter runs <file> with BASH_ENV set and the runner's marker unset unless given.
run() {
  local out rc=0
  out=$(env -u COMMANDECK_TEST_RUNNER ${2:+COMMANDECK_TEST_RUNNER=$2} COMMANDECK_HOST_OS="$1" BASH_ENV="$GUARD" \
    bash "$BOX/starter.sh" "$3" 2>&1) || rc=$?
  printf '%s %s' "$rc" "$(grep -c '^RAN$' <<<"$out")"
  grep -q 'run-shell-tests.sh' <<<"$out" && printf ' named'
}

# In order: a test file a script starts on the Mac without the runner's marker (refused, naming the runner); the same
# with the marker (runs); another host (runs); another script on the Mac (runs, nothing said); a test file started by
# its bare name, and by `./`, inside its __tests__ folder (refused); another project's test on the Mac (runs: settings
# set BASH_ENV for every project, and only a Commandeck checkout's tests are refused); run-shell-tests.sh setting the
# marker on each file it starts.
IN=$CD/scripts/__tests__/inner.test.sh
GOT="$(run Darwin "" "$IN") | $(run Darwin 1 "$IN") | $(run Linux "" "$IN") | $(run Darwin "" "$BOX/helper.sh")"
for n in inner.test.sh ./inner.test.sh; do
  GOT+=" | $(cd "$CD/scripts/__tests__" && env -u COMMANDECK_TEST_RUNNER COMMANDECK_HOST_OS=Darwin BASH_ENV="$GUARD" bash "$n" >/dev/null 2>&1; echo "rc=$?")"
done
GOT+=" | $(run Darwin "" "$OTHER/scripts/__tests__/health.test.sh")"
# Catches issue 668: a host project whose .claude folder holds its own scripts/run-shell-tests.sh read as a checkout.
GOT+=" | $(run Darwin "" "$HOSTCL/scripts/__tests__/own.test.sh")"
GOT+=" | $(grep -c 'COMMANDECK_TEST_RUNNER=1 .*timeout "\$lim" bash "\$2"' "$ROOT/scripts/run-shell-tests.sh")"
check "a test file a script starts on the Mac is refused unless the runner started it" \
  "2 0 named | 0 1 | 0 1 | 0 1 | rc=2 | rc=2 | 0 1 | 0 1 | 1" "$GOT"

# Issue 668: a checkout is told by Commandeck's own marker (.claude-plugin/plugin.json naming commandeck), never by a
# scripts/run-shell-tests.sh alone: a host project with its own runner, at its root or under .claude, runs its tests;
# another plugin's checkout (a plugin.json with another name) does too.
HOST=$BOX/hostroot PLUG=$BOX/otherplugin
mkdir -p "$HOST/scripts/__tests__" "$PLUG/scripts/__tests__" "$PLUG/.claude-plugin"
: > "$HOST/scripts/run-shell-tests.sh"; : > "$PLUG/scripts/run-shell-tests.sh"
printf '{ "name": "notcommandeck" }\n' > "$PLUG/.claude-plugin/plugin.json"
for f in "$HOST/scripts/__tests__/h.test.sh" "$PLUG/scripts/__tests__/p.test.sh"; do printf '#!/usr/bin/env bash\necho RAN\n' > "$f"; done
check "host_project_claude_folder_is_not_a_commandeck_checkout (#668): a host runner at the root or under .claude, or another plugin, runs" \
  "0 1 | 0 1 | 0 1 | 2 0 named" "$(run Darwin "" "$HOST/scripts/__tests__/h.test.sh") | $(run Darwin "" "$HOSTCL/scripts/__tests__/own.test.sh") | $(run Darwin "" "$PLUG/scripts/__tests__/p.test.sh") | $(run Darwin "" "$IN")"
# Issue 668: BASH_ENV comes from Commandeck's tracked project settings, never the user-wide ones, so it loads only in
# a Commandeck session; its value finds the guard from any folder of the checkout (bash expands BASH_ENV, and skips
# a file that is not there, so a folder outside any repository, or another repository, starts no guard).
BE=$(jq -r '.env.BASH_ENV // empty' "$ROOT/.claude/settings.json" 2>/dev/null)
git -C "$CD" init -q; cp "$GUARD" "$CD/scripts/test-host-guard.sh"; mkdir -p "$CD/docs" "$OTHER/sub"; git -C "$OTHER" init -q
bev() { (cd "$1" && env -u COMMANDECK_TEST_RUNNER COMMANDECK_HOST_OS=Darwin BASH_ENV="$BE" bash "$2" >/dev/null 2>&1; echo "rc=$?"); }
check "guard_bash_env_comes_from_tracked_project_settings (#668): set in .claude/settings.json, it refuses from a checkout's subfolder and runs elsewhere" \
  "set rc=2 rc=0 rc=0" "${BE:+set} $(bev "$CD/docs" "$IN") $(bev "$OTHER/sub" "$OTHER/scripts/__tests__/health.test.sh") $(bev "$BOX" "$BOX/helper.sh")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
