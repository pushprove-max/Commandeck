#!/usr/bin/env bash
# uninstall-codex.test.sh -- what uninstall owes Codex's own files. What this
# pins: a hook the owner added after the plugin's keeps its trust and its off
# switch when the plugin's entries come out from in front of it (Codex keys
# both by position); and every Codex home setup wrote to is cleaned, not only
# the one in use on the day of the uninstall.
set -uo pipefail
. "$(dirname "$0")/install-fixture.sh"
CX=$HOME/.codex
cp -R "$CX" "$T/cx0"; cp -R "$CX" "$T/cx2"; cp -R "$CX" "$T/cx3"
# run, with another Codex home in use (CXH, the second one unless set).
run2() { local d=$1 s=$2; shift 2
  ( cd "$d" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH -u COMMANDECK_DASHBOARD_DIR \
      -u COMMANDECK_HOOK_FIRE_LOG -u COMMANDECK_ROUTING CODEX_HOME="${CXH:-$T/cx2}" PATH="$BIN:$PATH" COMMANDECK_HOST_OS=Linux bash "$PLUGIN/scripts/$s" "$@" </dev/null ); }

run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "setup succeeds" 0 $?
run2 "$PROJ" setup.sh >"$T/out" 2>&1; check "setup again, with another Codex home in use, succeeds" 0 $?
check "the second home has the plugin's entries" 5 "$(jq '[.hooks[][].hooks[] | select(.command | contains("/hooks/codex-dispatch.sh"))] | length' "$T/cx2/hooks.json")"

# An update that fails is taken back whole, the Codex home it was the first to write to included.
touch "$T/orca-down"; KEEP=$(snap)
CXH=$T/cx3 run2 "$PROJ" update.sh >"$T/out" 2>&1; check "an update the doctor fails is refused" 1 $?
rm "$T/orca-down"
check "it says the files are back" 1 "$(grep -c 'Every file is back' "$T/out")"
check "and the Codex home it was the first to write to is as it was" '' "$(diff -r "$T/cx0" "$T/cx3" 2>&1 | head -3)"

# The same, when the Codex home's hooks.json is the owner's link to a file not made yet.
mkdir -p "$T/cx4" "$T/dot"; cp "$T/cx0/config.toml" "$T/cx4/"; ln -s "$T/dot/hooks.json" "$T/cx4/hooks.json"
touch "$T/orca-down"
CXH=$T/cx4 run2 "$PROJ" update.sh >"$T/out" 2>&1; check "an update the doctor fails is refused again" 1 $?
rm "$T/orca-down"
check "the owner's link is back as it was, and what was written through it is gone" "$T/dot/hooks.json no" \
  "$(readlink "$T/cx4/hooks.json" 2>/dev/null) $([ -e "$T/dot/hooks.json" ] && echo yes || echo no)"

# The owner adds a hook after the plugin's and switches it off in Codex's /hooks.
jq '.hooks.PreToolUse += [{hooks: [{type: "command", command: "/opt/mine/late.sh"}]}]' "$CX/hooks.json" > "$T/h.json" && cp "$T/h.json" "$CX/hooks.json"
N=$(jq '.hooks.PreToolUse | length - 1' "$CX/hooks.json")
printf '\n[hooks.state."%s:pre_tool_use:%s:0"]\ntrusted_hash = "sha256:mine"\nenabled = false\n' "$CX/hooks.json" "$N" >> "$CX/config.toml"

run "$PROJ" uninstall.sh --delete-data >"$T/out" 2>&1; check "uninstall succeeds" 0 $?
NEW=$(jq '[.hooks.PreToolUse[].hooks[0].command] | index("/opt/mine/late.sh")' "$CX/hooks.json")
check "the owner's later hook moved up into the plugin's place" "$((N - 1))" "$NEW"
check "its trust and its off switch moved with it" 1 \
  "$(grep -A2 -F "[hooks.state.\"$CX/hooks.json:pre_tool_use:$NEW:0\"]" "$CX/config.toml" | grep -c '^enabled = false$')"
check "no state is left under its old position" 0 "$(grep -cF ":pre_tool_use:$N:0\"]" "$CX/config.toml")"
check "the Codex home that was not in use is as it was before setup" '' "$(diff -r "$T/cx0" "$T/cx2" 2>&1 | head -5)"

[ "$FAIL" = 0 ] || { echo "--- last output"; tail -15 "$T/out"; }
done_tests
