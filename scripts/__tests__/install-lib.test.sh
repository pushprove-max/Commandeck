#!/usr/bin/env bash
# install-lib.test.sh -- the install's data-safety rules, on a hand-written HOME, by the functions setup.sh and
# uninstall.sh call (no whole run of either). What this pins: another tool's Codex hooks keep their places and
# its trust entries stay as they were, since Codex keys trust by position; the manifest records what was at a path
# with its hash and keeps the bytes; the restore puts those bytes back, and leaves a file edited since and names it;
# a plan writes nothing, manifest included.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
H=$T/home C=$T/home/.codex PROJ=$T/proj
mkdir -p "$C" && git init -q -b main "$PROJ"
# Another tool's Codex hooks and its trust entry, one of them disabled.
cat > "$C/hooks.json" <<'EOF'
{"hooks": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "/opt/other-tool/hook.sh", "timeout": 5}]}],
           "SessionEnd": [{"hooks": [{"type": "command", "command": "/opt/other-tool/end.sh"}]}]}}
EOF
cat > "$C/config.toml" <<EOF
model = "other"

[hooks.state."$C/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:0000"
enabled = false
EOF
cp "$C/hooks.json" "$T/hooks.before"; cp "$C/config.toml" "$T/config.before"
# lib <shell> [args] -- run it with paths.sh and install-lib.sh loaded and the args as "$1"..., in the project, on the hand-written HOME.
lib() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH -u CODEX_HOME HOME="$H" \
  bash -c '. "$0/paths.sh" && . "$0/install-lib.sh" && c=$1 && shift && eval "$c"' "$REAL/scripts" "$@"); }
snap() { (cd "$T" && find home proj -path '*/.git' -prune -o -print | sort | while IFS= read -r f; do [ -f "$f" ] && sha256sum < "$f" | cut -c1-16; echo "$f"; done); }
SETUP='il_record "$IL_MACHINE" merge "$IL_CODEX/hooks.json" "$IL_CODEX/config.toml" && il_record "$IL_PROJECT" own "$IL_CONFIG" \
  && il_codex_hooks "$IL_ROOT" && python3 "$PP_SCRIPTS/codex-hook-trust.py" "$IL_CODEX" >/dev/null'

# --- a plan writes nothing, the manifest included ---
B=$(snap)
OUT=$(IL_PLAN=1 IL_WROTE=$T/wrote lib 'il_record "$IL_MACHINE" merge "$IL_CODEX/hooks.json" && il_codex_hooks "$IL_ROOT" && il_set "$IL_MACHINE" ".x = 1"
  printf "x\n" | il_write "$IL_CONFIG"' 2>&1)
check "a plan writes nothing, in HOME or the project, and no manifest" "$B" "$(snap)"
check "and says what it would change and create" '1:1' "$(grep -c "^plan: would change $C/hooks.json:" <<<"$OUT"):$(grep -c "^plan: would create $PROJ/.claude/commandeck.json" <<<"$OUT")"
# A plan reads what it would already have written: with no Codex hooks file yet, it would create one.
mv "$C/hooks.json" "$T/hooks.kept"
OUT=$(IL_PLAN=1 IL_WROTE=$T/wrote2 lib 'il_codex_hooks "$IL_ROOT"' 2>&1)
check "a plan with no Codex hooks file yet says it would create it, and does not" '0:1:no' "$?:$(grep -c "^plan: would create $C/hooks.json" <<<"$OUT"):$([ -e "$C/hooks.json" ] && echo yes || echo no)"
mv "$T/hooks.kept" "$C/hooks.json"

# --- setup's steps: record, then add the plugin's entries ---
lib "$SETUP"; check "the steps succeed" 0 $?
MF=$H/.commandeck/install/_machine.json PMF=$(ls "$H/.commandeck/install/"*.json | grep -v _machine)
check "a file that was there is recorded by its content hash" "sha256:$(sha256sum < "$T/hooks.before" | cut -d' ' -f1)" "$(jq -r --arg p "$C/hooks.json" '.entries[$p].prior' "$MF")"
check "and its bytes are kept under that hash" 0 "$(cmp -s "$H/.commandeck/install/blobs/$(sha256sum < "$T/hooks.before" | cut -d' ' -f1)" "$T/hooks.before"; echo $?)"
check "a file that was not there is recorded as such, and the folder setup must make as a folder" 'did not exist:dir' \
  "$(jq -r --arg p "$PROJ/.claude/commandeck.json" '.entries[$p].prior' "$PMF"):$(jq -r --arg p "$PROJ/.claude" '.entries[$p].kind' "$PMF")"
check "Codex has the plugin's five entries" 5 "$(lib il_codex_count)"
check "the other tool's Codex hooks are still first in their groups" '["/opt/other-tool/hook.sh","/opt/other-tool/end.sh"]' \
  "$(jq -c '[.hooks.PreToolUse[0].hooks[0].command, .hooks.SessionEnd[0].hooks[0].command]' "$C/hooks.json")"
check "the plugin's five entries are trusted" 5 "$(grep -c "^\[hooks.state.\"$C/hooks.json:" "$C/config.toml" | awk '{print $1 - 1}')"
check "the other tool's trust entry and its disabled flag are untouched" 2 "$(grep -A2 'pre_tool_use:0:0' "$C/config.toml" | grep -c 'sha256:0000\|enabled = false')"
# A second setup records nothing over the first record and adds no entry twice.
lib "$SETUP"
check "a second run adds no entry twice" 5 "$(lib il_codex_count)"
check "and keeps the first record of what was there" "sha256:$(sha256sum < "$T/hooks.before" | cut -d' ' -f1)" "$(jq -r --arg p "$C/hooks.json" '.entries[$p].prior' "$MF")"

# --- uninstall's steps: the plugin's entries out, then the recorded bytes back ---
UNDO='python3 "$PP_SCRIPTS/codex-hook-trust.py" --forget "$IL_CODEX" >/dev/null && il_codex_hooks "" && il_restore "$IL_MACHINE"'
cp -R "$H" "$T/home.kept"
OUT=$(lib "$UNDO" 2>&1); check "the restore succeeds and leaves nothing named" '0:' "$?:$OUT"
check "Codex's hooks file is back byte for byte" 0 "$(cmp -s "$C/hooks.json" "$T/hooks.before"; echo $?)"
check "and its config, the other tool's trust entry included" 0 "$(cmp -s "$C/config.toml" "$T/config.before"; echo $?)"
check "the machine's manifest is gone with it" no "$([ -e "$MF" ] && echo yes || echo no)"
# A file the owner edited after setup is theirs: the restore leaves it and says so.
rm -rf "$H"; mv "$T/home.kept" "$H"
jq '.hooks.Stop = [{"hooks": [{"type": "command", "command": "/opt/mine.sh"}]}]' "$C/hooks.json" > "$T/h" && cp "$T/h" "$C/hooks.json"
OUT=$(lib "$UNDO" 2>&1)
check "a file edited since setup is left with the owner's edit, and named" "1:1" \
  "$(jq '[.hooks.Stop[0].hooks[0].command] | index("/opt/mine.sh") + 1' "$C/hooks.json"):$(grep -c "^changed since setup, left as it is: $C/hooks.json$" <<<"$OUT")"

# --- auto mode: two plain-English lines in the classifier's environment list of ~/.claude/settings.json ---
# The list is the owner's: setup keeps "$defaults" (Claude Code's built-in rules) in it, adds its lines once, and
# touches nothing when the owner's list has no "$defaults" (it replaced the built-in rules on purpose). Leave
# changes nothing at all, in the settings file or the machine manifest: the manifest serves every project, so a
# second project answering Leave must not take the first project's lines back.
AS=$H/.claude/settings.json; MM=$H/.commandeck/install/_machine.json; mkdir -p "$H/.claude"
auto() { lib 'il_auto_mode "$IL_MACHINE" "$HOME/.claude/settings.json" '"$1" 2>&1; }
envs() { jq -c '.autoMode.environment | [.[0], length]' "$AS" 2>&1; }
rm -rf "$H/.commandeck"; rm -f "$AS"
auto add >/dev/null
check "no autoMode yet: the list is written with \"\$defaults\" first and setup's two lines" '["$defaults",3]' "$(envs)"
auto add >/dev/null
check "a second run adds nothing" '["$defaults",3]' "$(envs)"
check "the first line names the plugin's repo, the second the relay pane" '1:1' \
  "$(jq -r '.autoMode.environment[1]' "$AS" | grep -c '^Trusted repo: https://'):$(jq -r '.autoMode.environment[2]' "$AS" | grep -c 'Chief-of-Staff')"
B=$(sha256sum < "$AS"; sha256sum < "$MM")
auto leave >/dev/null
check "Leave after an earlier add changes neither the settings file nor the machine manifest" "$B" "$(sha256sum < "$AS"; sha256sum < "$MM")"
auto remove >/dev/null
check "taking them out, when setup made the list, leaves no autoMode and no record" 'null:null' "$(jq -c '.autoMode' "$AS"):$(jq -c '.entries[$f].autoMode' --arg f "$AS" "$MM")"
echo '{"theme":"dark","autoMode":{"environment":["$defaults","mine"]}}' > "$AS"
auto add >/dev/null; auto add >/dev/null
check "an owner's list with \"\$defaults\" gets the lines once, their own entry kept in place" '["$defaults",4]:mine' "$(envs):$(jq -r '.autoMode.environment[1]' "$AS")"
auto remove >/dev/null
check "taking them out removes only setup's lines, the owner's entry and the rest of the file stay" '{"theme":"dark","autoMode":{"environment":["$defaults","mine"]}}' "$(jq -c . "$AS")"
echo '{"autoMode":{"environment":["mine"]}}' > "$AS"; cp "$AS" "$T/as.before"; B=$(sha256sum < "$MM")
OUT=$(auto add)
check "an owner's list without \"\$defaults\" is left byte for byte, and setup says how to keep the built-in rules" '0:1' \
  "$(cmp -s "$AS" "$T/as.before"; echo $?):$(grep -c '"$defaults"' <<<"$OUT")"
check "and nothing is recorded for it, so taking the lines out later removes nothing of the owner's" "$B" "$(sha256sum < "$MM")"
rm -rf "$H/.commandeck" "$AS"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
